///|
/// Deterministic in-memory ports for the Client owner-loop bridge.  The
/// reader is fed from one unbounded queue (`None` is EOF), the writer records
/// frames and signals each write, and traces accumulate for order-independent
/// assertions.  No real I/O, timers, or sleeps are involved.
fn client_runtime_test_ports(
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
fn client_runtime_test_chunk(frame : String) -> Bytes? {
  Some(@utf8.encode(frame))
}

///|
fn client_runtime_test_read(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"fs/read_text_file\",\"params\":{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}}\n"
}

///|
fn client_runtime_test_write(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"fs/write_text_file\",\"params\":{\"sessionId\":\"session\",\"path\":\"/tmp/output\",\"content\":\"body\"}}\n"
}

///|
fn client_runtime_test_permission(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"session\",\"toolCall\":{\"toolCallId\":\"tool\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}}\n"
}

///|
fn client_runtime_test_update() -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"session\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}}\n"
}

///|
fn client_runtime_test_cancel(victim : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"" +
  victim +
  "\"}}\n"
}

///|
fn client_runtime_test_decode(frame : Bytes) -> JsonRpcResponse raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Response(response) => response
    _ => fail("expected one JSON-RPC response frame")
  }
}

///|
fn client_runtime_test_success_id(frame : Bytes) -> RequestId raise {
  match client_runtime_test_decode(frame) {
    Success(success) => success.id
    Error(_) => fail("expected a successful JSON-RPC response")
  }
}

///|
fn client_runtime_test_error(
  frame : Bytes,
) -> (JsonRpcId, JsonRpcErrorCode) raise {
  match client_runtime_test_decode(frame) {
    Error(failure) => (failure.id, failure.error.code)
    Success(_) => fail("expected an error JSON-RPC response")
  }
}

///|
fn client_runtime_test_request(frame : Bytes) -> JsonRpcRequest raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Request(request) => request
    _ => fail("expected one JSON-RPC request frame")
  }
}

///|
fn client_runtime_test_traced(
  traces : Array[@runtime.RuntimeTraceEvent],
  phase : String,
  method_name : String,
) -> Bool {
  traces.any(event => event.phase == phase && event.method_name == method_name)
}

///|
/// One Client endpoint whose `fs/read_text_file` handler is supplied by the
/// test, so inbound requests can be gated deterministically.
fn client_runtime_test_read_endpoint(
  read : ClientReadTextFileHandler,
) -> ClientEndpoint {
  let files = try! client_file_system_service(read~)
  let spec = client_spec(
    info=client_service_test_info("runtime-read"),
    session=client_service_test_session(),
    file_system=files,
  )
  @reader.Reader::run(client_program(@reader.Reader::pure(spec)), ()).unwrap()
}

///|
async test "client runtime bridge observes session updates and answers permissions" {
  let observed : Array[SessionUpdateParams] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let session = client_session_service(
    session_update=async fn(params : SessionUpdateParams) {
      observed.push(params)
      arrived.put(())
      @async.pause()
    },
    request_permission=async fn(_request : RequestPermissionRequest) {
      arrived.put(())
      @async.pause()
      {
        outcome: Selected({ option_id: "allow", meta: Omitted }),
        meta: Omitted,
      }
    },
  )
  let spec = client_spec(
    info=client_service_test_info("runtime-observe"),
    session~,
  )
  let endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(spec)),
    (),
  ).unwrap()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(client_runtime_test_chunk(client_runtime_test_update()))
  input.put(client_runtime_test_chunk(client_runtime_test_permission("perm")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run(
        endpoint~,
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(arrived.get()) // session/update observer arrived
      ignore(arrived.get()) // permission handler arrived
      ignore(written.get()) // permission response written
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  assert_eq(observed[0].session_id, "session")
  assert_eq(output.length(), 1)
  match client_runtime_test_decode(output[0]) {
    Success(success) => {
      assert_eq(success.id, String("perm"))
      let response = request_permission_response_from_json(success.result)
      match response.outcome {
        Selected(selected) => assert_eq(selected.option_id, "allow")
        Cancelled => fail("observed permission must select the offered option")
      }
    }
    Error(_) => fail("permission round-trip must produce one success response")
  }
}

///|
async test "client runtime bridge completes two requests in reverse order exactly once" {
  let arrivals : Array[Int] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_first : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_second : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = client_runtime_test_read_endpoint(async fn(
    _params : ReadTextFileParams,
  ) {
    arrivals.push(arrivals.length() + 1)
    arrived.put(())
    if arrivals[arrivals.length() - 1] == 1 {
      gate_first.get()
    } else {
      gate_second.get()
    }
    { content: "read", meta: Omitted }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(client_runtime_test_chunk(client_runtime_test_read("first")))
  input.put(client_runtime_test_chunk(client_runtime_test_read("second")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run(
        endpoint~,
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(arrived.get())
      ignore(arrived.get())
      gate_second.put(())
      ignore(written.get()) // second response written
      gate_first.put(())
      ignore(written.get()) // first response written
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(arrivals, [1, 2])
  assert_eq(output.length(), 2)
  assert_eq(client_runtime_test_success_id(output[0]), String("second"))
  assert_eq(client_runtime_test_success_id(output[1]), String("first"))
}

///|
async test "client runtime bridge cancels one pending request by typed id" {
  let arrivals : Array[Int] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_victim : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_sibling : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = client_runtime_test_read_endpoint(async fn(
    _params : ReadTextFileParams,
  ) {
    arrivals.push(arrivals.length() + 1)
    arrived.put(())
    if arrivals[arrivals.length() - 1] == 1 {
      gate_victim.get()
    } else {
      gate_sibling.get()
    }
    { content: "read", meta: Omitted }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(client_runtime_test_chunk(client_runtime_test_read("victim")))
  input.put(client_runtime_test_chunk(client_runtime_test_read("sibling")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run(
        endpoint~,
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(arrived.get())
      ignore(arrived.get())
      input.put(client_runtime_test_chunk(client_runtime_test_cancel("victim")))
      ignore(written.get()) // cancelled victim response written
      gate_sibling.put(())
      ignore(written.get()) // sibling success written
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 2)
  let (victim_id, victim_code) = client_runtime_test_error(output[0])
  assert_eq(victim_id, String("victim"))
  assert_eq(victim_code, RequestCancelled)
  assert_eq(client_runtime_test_success_id(output[1]), String("sibling"))
  assert_true(client_runtime_test_traced(traces, "cancel_requested", ""))
}

///|
async test "client runtime bridge close aborts pending work and settles inbound" {
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = client_runtime_test_read_endpoint(async fn(
    _params : ReadTextFileParams,
  ) {
    arrived.put(())
    gate.get()
    { content: "read", meta: Omitted }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(client_runtime_test_chunk(client_runtime_test_read("pending")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run(
        endpoint~,
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(arrived.get())
      input.put(None)
      ignore(written.get()) // close settle for the pending request
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  let (pending_id, pending_code) = client_runtime_test_error(output[0])
  assert_eq(pending_id, String("pending"))
  assert_eq(pending_code, InternalError)
  assert_true(traces.any(event => event.phase == "task_cancelled_on_close"))
}

///|
async test "client runtime bridge surfaces a typed handler failure" {
  let endpoint = client_runtime_test_read_endpoint(
    client_service_test_failing_read,
  )
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(client_runtime_test_chunk(client_runtime_test_read("fails")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run(
        endpoint~,
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  let (failure_id, failure_code) = client_runtime_test_error(output[0])
  assert_eq(failure_id, String("fails"))
  assert_eq(failure_code, InternalError)
}

///|
async test "client runtime bridge traces an unknown notification without replying" {
  let endpoint = client_runtime_test_read_endpoint(client_service_test_read)
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(
    client_runtime_test_chunk(
      "{\"jsonrpc\":\"2.0\",\"method\":\"vendor/unknown\",\"params\":{}}\n",
    ),
  )
  input.put(None)
  client_runtime_run(
    endpoint~,
    initial_state=client_adapter_test_state(endpoint),
    ports~,
    options=@runtime.runtime_default_options(),
  )
  assert_eq(output.length(), 0)
  assert_true(
    client_runtime_test_traced(traces, "owner_trace", "vendor/unknown"),
  )
}

///|
async test "client runtime bridge rejects a capability-gated request without state change" {
  let read_only = try! client_file_system_service(read=client_service_test_read)
  let spec = client_spec(
    info=client_service_test_info("runtime-gate"),
    session=client_service_test_session(),
    file_system=read_only,
  )
  let endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(spec)),
    (),
  ).unwrap()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  input.put(client_runtime_test_chunk(client_runtime_test_write("denied")))
  input.put(client_runtime_test_chunk(client_runtime_test_read("after")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run(
        endpoint~,
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // denied write response written
      ignore(written.get()) // read success written
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 2)
  let (denied_id, denied_code) = client_runtime_test_error(output[0])
  assert_eq(denied_id, String("denied"))
  assert_eq(denied_code, ResourceNotFound)
  assert_eq(client_runtime_test_success_id(output[1]), String("after"))
}

///|
/// Outbound-observing ports for the engine-channel bridge test: the response
/// callback records each settled reply id as text, and the outbound-failure
/// callback records each typed failure, so exactly-once settle is observable
/// without engine internals.
fn client_runtime_test_outbound_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[@runtime.RuntimeTraceEvent],
  responses : Array[String],
  failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)],
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
async test "client runtime outbound serves inbound requests while forwarding" {
  let endpoint = client_endpoint_test_endpoint("runtime-outbound", true)
  let connections : @aqueue.Queue[ClientConnection] = Queue(kind=Unbounded)
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[(RequestId, @runtime.RuntimeOutboundFailureKind)] = []
  let ports = client_runtime_test_outbound_ports(
    input, output, written, traces, responses, failures,
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      client_runtime_run_with_outbound(
        endpoint_factory=channel => {
          // The factory is synchronous by engine contract, so the handoff
          // uses the non-blocking bounded try_put exactly like the engine's
          // own channel-capture tests.
          let _ = connections.try_put(
            @broker.client_connection_over_channel(channel~),
          ) catch {
            _ => false
          }
          endpoint
        },
        initial_state=client_adapter_test_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let submitter = group.spawn(() => {
      let connection = connections.get()
      let initialized : @protocol_data.InitializeResult = connection.initialize({
          protocol_version: 1,
          client_capabilities: Omitted,
          client_info: Omitted,
          meta: Omitted,
        },
      )
      let created = connection.new_session({
        cwd: "/",
        additional_directories: Omitted,
        mcp_servers: [],
        meta: Omitted,
      })
      (initialized, created)
    })
    ignore(written.get()) // forward initialize request written
    let initialize_frame = client_runtime_test_request(output[0])
    assert_eq(initialize_frame.method_name, "initialize")
    assert_eq(initialize_frame.id, Number(1))
    input.put(
      client_runtime_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":1}}\n",
      ),
    )
    ignore(written.get()) // forward session/new request written
    let new_session_frame = client_runtime_test_request(output[1])
    assert_eq(new_session_frame.method_name, "session/new")
    assert_eq(new_session_frame.id, Number(2))
    input.put(client_runtime_test_chunk(client_runtime_test_read("inbound")))
    ignore(written.get()) // inbound fs/read response written
    input.put(
      client_runtime_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"created\"}}\n",
      ),
    )
    let (initialized, created) = submitter.wait()
    input.put(None)
    runtime.wait()
    assert_eq(initialized.protocol_version, 1)
    assert_eq(created.session_id, "created")
  })
  assert_eq(output.length(), 3)
  assert_eq(client_runtime_test_success_id(output[2]), String("inbound"))
  let inbound_result = match client_runtime_test_decode(output[2]) {
    Success(success) => success.result
    Error(_) => fail("inbound fs/read must produce one success response")
  }
  assert_eq(
    @protocol_data.read_text_file_result_from_json(inbound_result).content,
    "read",
  )
  assert_eq(responses, ["1", "2"])
  assert_eq(failures.length(), 0)
}
