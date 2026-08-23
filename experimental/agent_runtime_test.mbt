///|
/// Deterministic in-memory ports for the v2 owner-loop bridge: the reader is
/// fed from one unbounded queue (`None` is EOF), the writer records frames
/// and signals each write, and traces accumulate.  No real I/O, timers, or
/// sleeps are involved.
fn experimental_v2_agent_runtime_test_ports(
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
fn experimental_v2_agent_runtime_test_chunk(frame : String) -> Bytes? {
  Some(@utf8.encode(frame))
}

///|
fn experimental_v2_agent_runtime_test_initialize(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":2,\"info\":{\"name\":\"client\",\"version\":\"1\"},\"capabilities\":{}}}\n"
}

///|
fn experimental_v2_agent_runtime_test_offer(
  id : String,
  version : Int,
) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":" +
  version.to_string() +
  ",\"info\":{\"name\":\"client\",\"version\":\"1\"}}}\n"
}

///|
fn experimental_v2_agent_runtime_test_session_new(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/new\",\"params\":{\"cwd\":\"/\"}}\n"
}

///|
fn experimental_v2_agent_runtime_test_login(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"auth/login\",\"params\":{\"methodId\":\"token\"}}\n"
}

///|
fn experimental_v2_agent_runtime_test_decode(
  frame : Bytes,
) -> @jsonrpc.JsonRpcResponse raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Response(response) => response
    _ => fail("expected one JSON-RPC response frame")
  }
}

///|
fn experimental_v2_agent_runtime_test_success_id(
  frame : Bytes,
) -> @jsonrpc.RequestId raise {
  match experimental_v2_agent_runtime_test_decode(frame) {
    Success(success) => success.id
    Error(_) => fail("expected a successful JSON-RPC response")
  }
}

///|
fn experimental_v2_agent_runtime_test_error(
  frame : Bytes,
) -> (@jsonrpc.JsonRpcId, @jsonrpc.JsonRpcErrorCode) raise {
  match experimental_v2_agent_runtime_test_decode(frame) {
    Error(failure) => (failure.id, failure.error.code)
    Success(_) => fail("expected an error JSON-RPC response")
  }
}

///|
async fn experimental_v2_agent_runtime_test_run(
  endpoint : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  state : ExperimentalV2AgentAdapterState,
  ports : @runtime.RuntimePorts,
) -> Unit {
  @connection.connection_runtime_run_owner(
    ports,
    @runtime.runtime_default_options(),
    experimental_v2_agent_runtime_owner_port(
      endpoint~,
      context~,
      initial_state=state,
    ),
  )
}

///|
async test "v2 agent runtime bridge initialize round-trips and rejects duplicates" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = experimental_v2_agent_runtime_test_ports(
    input, output, written, traces,
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("again"),
    ),
  )
  input.put(None)
  experimental_v2_agent_runtime_test_run(
    endpoint,
    experimental_v2_agent_fail_fast_context(),
    experimental_v2_agent_test_adapter_state(endpoint),
    ports,
  )
  assert_eq(output.length(), 2)
  let result = match @jsonrpc.jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Success(success)) => success.result
    _ => fail("initialize must produce exactly one success response")
  }
  guard result is Object(fields) else {
    fail("initialize result must be an object")
  }
  guard fields.get("protocolVersion") is Some(Number(version, ..)) else {
    fail("initialize result must echo protocolVersion")
  }
  assert_eq(version, 2.0)
  let (second_id, second_code) = experimental_v2_agent_runtime_test_error(
    output[1],
  )
  assert_eq(second_id, String("again"))
  assert_eq(second_code, InvalidRequest)
}

///|
async test "v2 agent runtime bridge answers a version-1 offer without initializing" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = experimental_v2_agent_runtime_test_ports(
    input, output, written, traces,
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_offer("offer", 1),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("retry"),
    ),
  )
  input.put(None)
  experimental_v2_agent_runtime_test_run(
    endpoint,
    experimental_v2_agent_fail_fast_context(),
    experimental_v2_agent_test_adapter_state(endpoint),
    ports,
  )
  assert_eq(output.length(), 2)
  // The rejected offer is a success response carrying version 2.
  let answer = match @jsonrpc.jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Success(success)) => success.result
    _ => fail("the version negotiation answer must be a success response")
  }
  guard answer is Object(fields) else {
    fail("the negotiation answer must be an object")
  }
  guard fields.get("protocolVersion") is Some(Number(version, ..)) else {
    fail("the negotiation answer must echo protocolVersion")
  }
  assert_eq(version, 2.0)
  // The endpoint stayed pre-initialized, so the retry enters AgentInitialized.
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[1]),
    String("retry"),
  )
}

///|
async test "v2 agent runtime bridge completes two requests in reverse order exactly once" {
  let arrivals : Array[Int] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_first : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_second : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = experimental_v2_agent_test_endpoint(new_session=async fn(
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
    { session_id: "created", config_options: None, meta: None }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = experimental_v2_agent_runtime_test_ports(
    input, output, written, traces,
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_session_new("first"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_session_new("second"),
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_test_run(
        endpoint,
        experimental_v2_agent_fail_fast_context(),
        experimental_v2_agent_test_adapter_state(endpoint),
        ports,
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
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[0]),
    String("init"),
  )
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[1]),
    String("second"),
  )
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[2]),
    String("first"),
  )
}

///|
async test "v2 agent runtime bridge cancels one pending request by typed id" {
  let arrivals : Array[Int] = []
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_victim : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate_sibling : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = experimental_v2_agent_test_endpoint(new_session=async fn(
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
    { session_id: "created", config_options: None, meta: None }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = experimental_v2_agent_runtime_test_ports(
    input, output, written, traces,
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_session_new("victim"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_session_new("sibling"),
    ),
  )
  let cancel_frame = "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"victim\"}}\n"
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_test_run(
        endpoint,
        experimental_v2_agent_fail_fast_context(),
        experimental_v2_agent_test_adapter_state(endpoint),
        ports,
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get())
      ignore(arrived.get())
      ignore(arrived.get())
      input.put(experimental_v2_agent_runtime_test_chunk(cancel_frame))
      ignore(written.get())
      gate_sibling.put(())
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 3)
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[0]),
    String("init"),
  )
  let (victim_id, victim_code) = experimental_v2_agent_runtime_test_error(
    output[1],
  )
  assert_eq(victim_id, String("victim"))
  assert_eq(victim_code, RequestCancelled)
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[2]),
    String("sibling"),
  )
  assert_true(traces.any(event => event.phase == "cancel_requested"))
}

///|
async test "v2 agent runtime bridge close aborts a pending login and settles it" {
  let arrived : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let endpoint = experimental_v2_agent_test_endpoint(
    with_auth=true,
    new_session=experimental_v2_agent_test_new,
  )
  let login_gated : ExperimentalV2AgentEndpoint = experimental_v2_agent_endpoint_from_spec(
    try! experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(
        false,
        new_session=experimental_v2_agent_test_new,
      ),
      auth_methods=Some([experimental_v2_agent_test_token_method()]),
      auth=Some(
        experimental_v2_agent_auth_service(
          login=async fn(_context, _params) {
            arrived.put(())
            gate.get()
            { meta: None }
          },
          logout=experimental_v2_agent_test_logout,
        ),
      ),
    ),
  )
  ignore(endpoint)
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = experimental_v2_agent_runtime_test_ports(
    input, output, written, traces,
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_login("pending"),
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_test_run(
        login_gated,
        experimental_v2_agent_fail_fast_context(),
        experimental_v2_agent_test_adapter_state(login_gated),
        ports,
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
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[0]),
    String("init"),
  )
  let (pending_id, pending_code) = experimental_v2_agent_runtime_test_error(
    output[1],
  )
  assert_eq(pending_id, String("pending"))
  assert_eq(pending_code, InternalError)
  assert_true(traces.any(event => event.phase == "task_cancelled_on_close"))
}

///|
async fn experimental_v2_agent_test_outbound_new(
  context : ExperimentalV2AgentContext,
  _params : ExperimentalV2NewSessionParams,
) -> ExperimentalV2NewSessionResult {
  @async.pause()
  // The fail-fast broker raises a typed ContextUnavailable naming the
  // outbound method; the handler lets it escape so the boundary normalizes
  // it into a visible typed failure.
  let _reply : ExperimentalV2RequestPermissionResponse = context.request_permission({
      session_id: "created",
      title: "proceed?",
      description: None,
      subject: None,
      options: [
        {
          option_id: "allow",
          name: "Allow",
          kind: OptionKindAllowOnce,
          meta: None,
        },
      ],
      meta: None,
    },
  )
  { session_id: "never", config_options: None, meta: None }
}

///|
async test "v2 agent runtime bridge makes broker fail-fast visible typed" {
  let endpoint = experimental_v2_agent_test_endpoint(
    new_session=experimental_v2_agent_test_outbound_new,
  )
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = experimental_v2_agent_runtime_test_ports(
    input, output, written, traces,
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_agent_runtime_test_chunk(
      experimental_v2_agent_runtime_test_session_new("outbound"),
    ),
  )
  // EOF is gated behind both writes: the engine settles still-pending
  // inbounds at EOF, so the failure response must be written first.
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_test_run(
        endpoint,
        experimental_v2_agent_fail_fast_context(),
        experimental_v2_agent_test_adapter_state(endpoint),
        ports,
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
  assert_eq(
    experimental_v2_agent_runtime_test_success_id(output[0]),
    String("init"),
  )
  match experimental_v2_agent_runtime_test_decode(output[1]) {
    Error(failure) => {
      assert_eq(failure.error.code, InternalError)
      assert_true(
        failure.error.message.has_prefix("session/new: agent handler failed: "),
      )
    }
    Success(_) => fail("expected the broker failure to surface as an error")
  }
}

///|
test "v2 agent owner port plans local effects and synthesizes completions" {
  let endpoint = experimental_v2_agent_test_endpoint(with_auth=true)
  let port = experimental_v2_agent_runtime_owner_port(
    endpoint~,
    context=experimental_v2_agent_fail_fast_context(),
    initial_state=experimental_v2_agent_test_adapter_state(endpoint),
  )
  assert_eq(
    (port.plan_local_effect)(CancelRequest(request_id=RequestIdStr("victim"))),
    RuntimeOwnerCommands([
      RuntimeOwnerCancelInbound(request_id=String("victim")),
    ]),
  )
  assert_eq(
    (port.plan_local_effect)(
      TraceError(
        method_name="session/cancel",
        error=@jsonrpc.JsonRpcError::internal_error(),
      ),
    ),
    RuntimeOwnerCommands([RuntimeOwnerTrace(method_name="session/cancel")]),
  )
  let invocation : ExperimentalV2AgentInvocation = AuthLoginInvocation(
    id=String("login-1"),
    params={ method_id: "token", meta: None },
  )
  match
    (port.execute_cancel)(
      experimental_v2_agent_test_adapter_state(endpoint),
      invocation,
    ) {
    AuthLoginCompleted(id~, result~) => {
      assert_eq(id, String("login-1"))
      assert_true(result is Err(Cancelled))
    }
    _ => fail("expected a synthesized cancellation completion")
  }
  let failure_completion = (port.execute_failure)(
    experimental_v2_agent_test_adapter_state(endpoint),
    invocation,
  )
  match failure_completion {
    AuthLoginCompleted(id~, result~) => {
      assert_eq(id, String("login-1"))
      assert_true(result is Err(Application(_)))
    }
    _ => fail("expected a synthesized failure completion")
  }
  let (cancelled_state, completion) = (port.cancel_request)(
    {
      ..experimental_v2_agent_test_adapter_state(endpoint),
      reservation: LoginPending(String("login-1")),
    },
    String("login-1"),
    invocation,
  )
  // cancel_request only synthesizes the typed completion; the reservation
  // stays until that completion folds back through complete_request.
  assert_true(cancelled_state.reservation is LoginPending(String("login-1")))
  match completion {
    AuthLoginCompleted(id~, result~) => {
      assert_eq(id, String("login-1"))
      assert_true(result is Err(Cancelled))
    }
    _ => fail("expected a synthesized cancellation completion")
  }
}

///|
async test "v2 agent owner port executes a typed invocation" {
  let endpoint = experimental_v2_agent_test_endpoint(with_auth=true)
  let port = experimental_v2_agent_runtime_owner_port(
    endpoint~,
    context=experimental_v2_agent_fail_fast_context(),
    initial_state=experimental_v2_agent_test_adapter_state(endpoint),
  )
  let completion = (port.execute)(
    AuthLoginInvocation(id=String("login-1"), params={
      method_id: "token",
      meta: None,
    }),
  )
  match completion {
    AuthLoginCompleted(id~, result~) => {
      assert_eq(id, String("login-1"))
      assert_true(result is Ok(_))
    }
    _ => fail("expected a typed login completion")
  }
}
