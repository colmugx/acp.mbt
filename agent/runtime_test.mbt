///|
/// Deterministic in-memory ports for the Agent owner-loop bridge.  The reader
/// is fed from one unbounded queue (`None` is EOF), the writer records frames
/// and signals each write, and traces accumulate for order-independent
/// assertions.  No real I/O, timers, or sleeps are involved.
fn agent_runtime_test_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[@runtime.RuntimeTraceEvent],
) -> @runtime.RuntimePorts {
  {
    reader: { read: _ => input.get() },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
}

///|
fn agent_runtime_test_chunk(frame : String) -> Bytes? {
  Some(@utf8.encode(frame))
}

///|
fn agent_runtime_test_initialize(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":1}}\n"
}

///|
fn agent_runtime_test_session_new(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/new\",\"params\":{\"cwd\":\"/\",\"mcpServers\":[]}}\n"
}

///|
fn agent_runtime_test_decode(frame : Bytes) -> JsonRpcResponse raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Response(response) => response
    _ => fail("expected one JSON-RPC response frame")
  }
}

///|
fn agent_runtime_test_success_id(frame : Bytes) -> RequestId raise {
  match agent_runtime_test_decode(frame) {
    Success(success) => success.id
    Error(_) => fail("expected a successful JSON-RPC response")
  }
}

///|
fn agent_runtime_test_error(
  frame : Bytes,
) -> (JsonRpcId, JsonRpcErrorCode) raise {
  match agent_runtime_test_decode(frame) {
    Error(failure) => (failure.id, failure.error.code)
    Success(_) => fail("expected an error JSON-RPC response")
  }
}

///|
fn agent_runtime_test_traced(
  traces : Array[@runtime.RuntimeTraceEvent],
  phase : String,
  method_name : String,
) -> Bool {
  traces.any(event => event.phase == phase && event.method_name == method_name)
}

///|
async test "agent runtime bridge initialize round-trips and advances protocol state" {
  let endpoint = agent_adapter_test_endpoint()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("again")))
  input.put(None)
  agent_runtime_run(
    endpoint~,
    context=agent_service_test_context(),
    initial_state=agent_adapter_test_state(endpoint),
    ports~,
    options=@runtime.runtime_default_options(),
  )
  assert_eq(output.length(), 2)
  match @jsonrpc.jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Success(success)) => {
      assert_eq(success.id, String("init"))
      assert_true(success.result is Object(_))
    }
    _ => fail("initialize must produce exactly one success response")
  }
  let (second_id, second_code) = agent_runtime_test_error(output[1])
  assert_eq(second_id, String("again"))
  assert_eq(second_code, InvalidRequest)
}

///|
async test "agent runtime bridge completes two requests in reverse order exactly once" {
  let arrivals : Array[Int] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_first : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_second : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = agent_adapter_test_endpoint(new_session=async fn(
    _context,
    _params,
  ) {
    arrivals.push(arrivals.length() + 1)
    arrived.put(())
    if arrivals[arrivals.length() - 1] == 1 {
      gate_first.get()
    } else {
      gate_second.get()
    }
    {
      session_id: "created",
      modes: Omitted,
      config_options: Omitted,
      meta: Omitted,
    }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("first")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("second")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run(
        endpoint~,
        context=agent_service_test_context(),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(arrived.get())
      ignore(arrived.get())
      gate_second.put(())
      ignore(written.get())
      gate_first.put(())
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(arrivals, [1, 2])
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  assert_eq(agent_runtime_test_success_id(output[1]), String("second"))
  assert_eq(agent_runtime_test_success_id(output[2]), String("first"))
}

///|
async test "agent runtime bridge cancels one pending request by typed id" {
  let arrivals : Array[Int] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_victim : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_sibling : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = agent_adapter_test_endpoint(new_session=async fn(
    _context,
    _params,
  ) {
    arrivals.push(arrivals.length() + 1)
    arrived.put(())
    if arrivals[arrivals.length() - 1] == 1 {
      gate_victim.get()
    } else {
      gate_sibling.get()
    }
    {
      session_id: "created",
      modes: Omitted,
      config_options: Omitted,
      meta: Omitted,
    }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("victim")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("sibling")))
  let cancel_frame = "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"victim\"}}\n"
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run(
        endpoint~,
        context=agent_service_test_context(),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(arrived.get())
      ignore(arrived.get())
      input.put(agent_runtime_test_chunk(cancel_frame))
      ignore(written.get())
      gate_sibling.put(())
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  let (victim_id, victim_code) = agent_runtime_test_error(output[1])
  assert_eq(victim_id, String("victim"))
  assert_eq(victim_code, RequestCancelled)
  assert_eq(agent_runtime_test_success_id(output[2]), String("sibling"))
  assert_true(agent_runtime_test_traced(traces, "cancel_requested", ""))
}

///|
async test "agent runtime bridge close aborts pending work and settles inbound" {
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = agent_adapter_test_endpoint(new_session=async fn(
    _context,
    _params,
  ) {
    arrived.put(())
    gate.get()
    {
      session_id: "created",
      modes: Omitted,
      config_options: Omitted,
      meta: Omitted,
    }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("pending")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run(
        endpoint~,
        context=agent_service_test_context(),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(arrived.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 2)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  let (pending_id, pending_code) = agent_runtime_test_error(output[1])
  assert_eq(pending_id, String("pending"))
  assert_eq(pending_code, InternalError)
  assert_true(traces.any(event => event.phase == "task_cancelled_on_close"))
}

///|
async test "agent runtime bridge surfaces a typed handler failure" {
  let endpoint = agent_adapter_test_endpoint(
    new_session=agent_adapter_test_failing_new,
  )
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("fails")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run(
        endpoint~,
        context=agent_service_test_context(),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 2)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  let (failure_id, failure_code) = agent_runtime_test_error(output[1])
  assert_eq(failure_id, String("fails"))
  assert_eq(failure_code, InternalError)
}

///|
async test "agent runtime bridge rejects a capability-gated request without state change" {
  let spec = agent_spec(
    info=agent_service_test_info("runtime-gate"),
    sessions=agent_session_service(
      new_session=agent_service_test_new,
      prompt=agent_service_test_prompt,
      cancel=agent_service_test_cancel,
    ),
    support=agent_support(),
  ).unwrap()
  let endpoint = agent_endpoint_from_spec(spec)
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(
    agent_runtime_test_chunk(
      "{\"jsonrpc\":\"2.0\",\"id\":\"denied\",\"method\":\"session/list\",\"params\":{}}\n",
    ),
  )
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("after")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run(
        endpoint~,
        context=agent_service_test_context(),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(written.get())
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  let (denied_id, denied_code) = agent_runtime_test_error(output[1])
  assert_eq(denied_id, String("denied"))
  assert_eq(denied_code, ResourceNotFound)
  assert_eq(agent_runtime_test_success_id(output[2]), String("after"))
}

///|
async test "agent runtime bridge traces an unknown notification without replying" {
  let endpoint = agent_adapter_test_endpoint()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(
    agent_runtime_test_chunk(
      "{\"jsonrpc\":\"2.0\",\"method\":\"agent/poke\",\"params\":{}}\n",
    ),
  )
  input.put(None)
  agent_runtime_run(
    endpoint~,
    context=agent_service_test_context(),
    initial_state=agent_adapter_test_state(endpoint),
    ports~,
    options=@runtime.runtime_default_options(),
  )
  assert_eq(output.length(), 0)
  assert_true(agent_runtime_test_traced(traces, "owner_trace", "agent/poke"))
}

///|
async test "agent runtime bridge fails visibly when the context broker fails" {
  let broker_calls : Array[String] = []
  let request_broker : AgentContextRequestBroker = _request => {
    broker_calls.push("called")
    Err(AgentContextBrokerFailure(method_name="fs/read_text_file"))
  }
  let notification_broker : AgentContextNotificationBroker = _notification => {
    Err(AgentContextBrokerFailure(method_name="session/update"))
  }
  let context = agent_context(request_broker~, notification_broker~)
  let endpoint = agent_adapter_test_endpoint(new_session=async fn(
    context,
    _params,
  ) {
    ignore(
      context.read_text_file({
        session_id: "s",
        path: "/agent-runtime-broker-test",
        line: Omitted,
        limit: Omitted,
        meta: Omitted,
      }),
    )
    {
      session_id: "created",
      modes: Omitted,
      config_options: Omitted,
      meta: Omitted,
    }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = agent_runtime_test_ports(input, output, written, traces)
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(agent_runtime_test_chunk(agent_runtime_test_session_new("broker")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run(
        endpoint~,
        context~,
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 2)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  let (broker_id, broker_code) = agent_runtime_test_error(output[1])
  assert_eq(broker_id, String("broker"))
  assert_eq(broker_code, InternalError)
  assert_eq(broker_calls, ["called"])
}
