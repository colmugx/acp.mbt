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
    reader: { read: _ => input.get(), },
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

///|
/// Outbound-observing ports for the engine-channel bridge tests: the response
/// callback records each settled reply id as text, and the outbound-failure
/// callback records each typed failure, so exactly-once settle is observable
/// without engine internals.
fn agent_runtime_test_outbound_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[@runtime.RuntimeTraceEvent],
  responses : Array[String],
  failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)],
) -> @runtime.RuntimePorts {
  {
    reader: { read: _ => input.get(), },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: response => {
        responses.push(
          match response {
            Success(success) => @runtime.runtime_request_id_text(success.id)
            Error(failure) =>
              match failure.id {
                String(value) => value
                Number(value) => value.to_string()
                Null => "null"
              }
          },
        )
      },
      outbound_failure: Some((id, failure) => {
        failures.push((id, failure.reason))
      }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
}

///|
fn agent_runtime_test_session_prompt(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/prompt\",\"params\":{\"sessionId\":\"created\",\"prompt\":[]}}\n"
}

///|
fn agent_runtime_test_notification(frame : Bytes) -> JsonRpcNotification raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Notification(notification) => notification
    _ => fail("expected one JSON-RPC notification frame")
  }
}

///|
fn agent_runtime_test_request(frame : Bytes) -> JsonRpcRequest raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Request(request) => request
    _ => fail("expected one JSON-RPC request frame")
  }
}

///|
fn agent_runtime_test_request_params(request : JsonRpcRequest) -> Json raise {
  match request.params {
    Some(params) => params
    None => fail("expected the outbound request to carry params")
  }
}

///|
fn agent_runtime_test_notification_params(
  notification : JsonRpcNotification,
) -> Json raise {
  match notification.params {
    Some(params) => params
    None => fail("expected the outbound notification to carry params")
  }
}

///|
fn agent_runtime_test_update_params(text : String) -> SessionUpdateParams {
  {
    session_id: "created",
    update: UserMessageChunk({
      content: Text({ annotations: Omitted, text, meta: Omitted, }),
      message_id: Omitted,
      meta: Omitted,
    }),
    meta: Omitted,
  }
}

///|
/// A wire-encodable permission request: unlike the pure context fixture it
/// carries one option, because the real protocol encoder rejects an empty
/// permission option list before any submission.
fn agent_runtime_test_permission_request() -> RequestPermissionRequest {
  {
    session_id: "created",
    tool_call: {
      tool_call_id: "tool-call",
      kind: Omitted,
      status: Omitted,
      title: Omitted,
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Omitted,
      meta: Omitted,
    },
    options: [
      {
        option_id: "allow-once",
        name: "Allow once",
        kind: AllowOnce,
        meta: Omitted,
      },
    ],
    meta: Omitted,
  }
}

///|
fn agent_runtime_test_prompt_endpoint(
  prompt : AgentPromptHandler,
) -> AgentEndpoint {
  agent_endpoint_from_spec(
    agent_spec(
      info=agent_service_test_info("runtime-outbound"),
      sessions=agent_session_service(
        new_session=agent_service_test_new,
        prompt~,
        cancel=agent_service_test_cancel,
      ),
      support=agent_support(),
    ).unwrap(),
  )
}

///|
async test "agent runtime outbound streams updates and round-trips permission" {
  let replies : Array[@protocol_data.RequestPermissionResponse] = []
  let endpoint = agent_runtime_test_prompt_endpoint(async fn(
    context : AgentContext,
    _params : PromptParams,
  ) -> PromptResult {
    context.session_update(agent_runtime_test_update_params("one"))
    context.session_update(agent_runtime_test_update_params("two"))
    let permission = context.request_permission(
      agent_runtime_test_permission_request(),
    )
    replies.push(permission)
    { stop_reason: EndTurn, meta: Omitted, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)] = []
  let ports = agent_runtime_test_outbound_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(
    agent_runtime_test_chunk(agent_runtime_test_session_prompt("prompt")),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => @broker.agent_context_over_channel(channel~),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/update "one"
      ignore(written.get()) // session/update "two"
      ignore(written.get()) // session/request_permission request
      input.put(
        agent_runtime_test_chunk(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"outcome\":{\"outcome\":\"cancelled\"}}}\n",
        ),
      )
      ignore(written.get()) // session/prompt response
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(replies.length(), 1)
  assert_true(replies[0].outcome is Cancelled)
  assert_eq(output.length(), 5)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  let first_update = agent_runtime_test_notification(output[1])
  assert_eq(first_update.method_name, "session/update")
  assert_true(
    @session_protocol.session_update_params_from_json(
      agent_runtime_test_notification_params(first_update),
    ) ==
    agent_runtime_test_update_params("one"),
  )
  let second_update = agent_runtime_test_notification(output[2])
  assert_eq(second_update.method_name, "session/update")
  assert_true(
    @session_protocol.session_update_params_from_json(
      agent_runtime_test_notification_params(second_update),
    ) ==
    agent_runtime_test_update_params("two"),
  )
  let permission_frame = agent_runtime_test_request(output[3])
  assert_eq(permission_frame.method_name, "session/request_permission")
  assert_eq(permission_frame.id, Number(1))
  assert_true(
    @protocol_data.request_permission_request_from_json(
      agent_runtime_test_request_params(permission_frame),
    ) ==
    agent_runtime_test_permission_request(),
  )
  assert_eq(agent_runtime_test_success_id(output[4]), String("prompt"))
  assert_eq(responses, ["1"])
  assert_eq(failures.length(), 0)
}

///|
async test "agent runtime outbound maps a peer error reply to a typed broker failure" {
  let observed : Array[AgentContextError] = []
  let endpoint = agent_runtime_test_prompt_endpoint(async fn(
    context : AgentContext,
    _params : PromptParams,
  ) -> PromptResult {
    try {
      ignore(
        context.request_permission(agent_runtime_test_permission_request()),
      )
      ()
    } catch {
      error => observed.push(error)
    }
    { stop_reason: EndTurn, meta: Omitted, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)] = []
  let ports = agent_runtime_test_outbound_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(
    agent_runtime_test_chunk(agent_runtime_test_session_prompt("prompt")),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => @broker.agent_context_over_channel(channel~),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/request_permission request
      input.put(
        agent_runtime_test_chunk(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32603,\"message\":\"denied\"}}\n",
        ),
      )
      ignore(written.get()) // session/prompt response
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  match observed[0] {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected a typed agent context broker failure")
  }
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  assert_eq(
    agent_runtime_test_request(output[1]).method_name,
    "session/request_permission",
  )
  assert_eq(agent_runtime_test_success_id(output[2]), String("prompt"))
  assert_eq(responses, ["1"])
  assert_eq(failures.length(), 0)
}

///|
async test "agent runtime outbound maps the cancelled error code to a typed cancel" {
  let observed : Array[AgentContextError] = []
  let endpoint = agent_runtime_test_prompt_endpoint(async fn(
    context : AgentContext,
    _params : PromptParams,
  ) -> PromptResult {
    try {
      ignore(
        context.request_permission(agent_runtime_test_permission_request()),
      )
      ()
    } catch {
      error => observed.push(error)
    }
    { stop_reason: EndTurn, meta: Omitted, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)] = []
  let ports = agent_runtime_test_outbound_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(
    agent_runtime_test_chunk(agent_runtime_test_session_prompt("prompt")),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => @broker.agent_context_over_channel(channel~),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/request_permission request
      input.put(
        agent_runtime_test_chunk(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32800,\"message\":\"Request cancelled\"}}\n",
        ),
      )
      ignore(written.get()) // session/prompt response
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  match observed[0] {
    AgentContextCancelled(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected a typed agent context cancellation")
  }
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[2]), String("prompt"))
}

///|
async test "agent runtime outbound settles a parked submitter once on close" {
  let observed : Array[AgentContextError] = []
  let endpoint = agent_runtime_test_prompt_endpoint(async fn(
    context : AgentContext,
    _params : PromptParams,
  ) -> PromptResult {
    try {
      ignore(
        context.request_permission(agent_runtime_test_permission_request()),
      )
      ()
    } catch {
      error => observed.push(error)
    }
    { stop_reason: EndTurn, meta: Omitted, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)] = []
  let ports = agent_runtime_test_outbound_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(
    agent_runtime_test_chunk(agent_runtime_test_session_prompt("prompt")),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => @broker.agent_context_over_channel(channel~),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/request_permission request
      input.put(None)
      ignore(written.get()) // close settle for the pending prompt request
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  match observed[0] {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ =>
      fail("expected a typed agent context broker failure after close settle")
  }
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[0]), String("init"))
  assert_eq(
    agent_runtime_test_request(output[1]).method_name,
    "session/request_permission",
  )
  let (prompt_id, prompt_code) = agent_runtime_test_error(output[2])
  assert_eq(prompt_id, String("prompt"))
  assert_eq(prompt_code, InternalError)
  assert_eq(responses.length(), 0)
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].0, Number(1))
  assert_true(failures[0].1 is EndOfInput)
}

///|
async test "agent runtime outbound maps an undecodable reply to a typed mismatch" {
  let observed : Array[AgentContextError] = []
  let endpoint = agent_runtime_test_prompt_endpoint(async fn(
    context : AgentContext,
    _params : PromptParams,
  ) -> PromptResult {
    try {
      ignore(
        context.request_permission(agent_runtime_test_permission_request()),
      )
      ()
    } catch {
      error => observed.push(error)
    }
    { stop_reason: EndTurn, meta: Omitted, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)] = []
  let ports = agent_runtime_test_outbound_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(agent_runtime_test_chunk(agent_runtime_test_initialize("init")))
  input.put(
    agent_runtime_test_chunk(agent_runtime_test_session_prompt("prompt")),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => @broker.agent_context_over_channel(channel~),
        initial_state=agent_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/request_permission request
      input.put(
        agent_runtime_test_chunk(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"unexpected\":true}}\n",
        ),
      )
      ignore(written.get()) // session/prompt response
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  match observed[0] {
    AgentContextReplyMismatch(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected a typed agent context reply mismatch")
  }
  assert_eq(output.length(), 3)
  assert_eq(agent_runtime_test_success_id(output[2]), String("prompt"))
  assert_eq(responses, ["1"])
  assert_eq(failures.length(), 0)
}
