///|
fn experimental_v2_agent_test_json(source : String) -> Json {
  @json.parse(source) catch {
    _ => abort("v2 adapter test fixture must be valid JSON")
  }
}

///|
fn experimental_v2_agent_test_request(
  id : @jsonrpc.RequestId,
  method_name : String,
  params : String,
) -> @jsonrpc.JsonRpcMessage {
  let request = try! @jsonrpc.JsonRpcRequest::new(
    id~,
    method_name~,
    params=experimental_v2_agent_test_json(params),
  )
  @jsonrpc.JsonRpcMessage::request(request)
}

///|
fn experimental_v2_agent_test_notification(
  method_name : String,
  params : String,
) -> @jsonrpc.JsonRpcMessage {
  let notification = try! @jsonrpc.JsonRpcNotification::new(
    method_name~,
    params=experimental_v2_agent_test_json(params),
  )
  @jsonrpc.JsonRpcMessage::notification(notification)
}

///|
fn experimental_v2_agent_test_initialize_params() -> String {
  "{\"protocolVersion\":2,\"info\":{\"name\":\"client\",\"version\":\"1\"},\"capabilities\":{}}"
}

///|
fn experimental_v2_agent_test_initialized(
  endpoint : ExperimentalV2AgentEndpoint,
) -> ExperimentalV2AgentAdapterState raise {
  let admission = try! experimental_v2_agent_adapter_admit(
    experimental_v2_agent_test_adapter_state(endpoint),
    endpoint,
    experimental_v2_agent_test_request(
      String("init"),
      "initialize",
      experimental_v2_agent_test_initialize_params(),
    ),
  )
  match admission {
    Immediate(step) => step.state
    Invoke(..) => fail("initialize must be immediate")
  }
}

///|
fn experimental_v2_agent_test_step_response(
  step : ExperimentalV2AgentAdapterStep,
) -> @jsonrpc.JsonRpcResponse raise {
  match step.outputs {
    [Response(response)] => response
    _ => fail("expected exactly one response output")
  }
}

///|
fn experimental_v2_agent_test_success_result(
  step : ExperimentalV2AgentAdapterStep,
) -> Json raise {
  match experimental_v2_agent_test_step_response(step) {
    Success(success) => success.result
    Error(_) => fail("expected a successful response")
  }
}

///|
fn experimental_v2_agent_test_error_code(
  step : ExperimentalV2AgentAdapterStep,
) -> @jsonrpc.JsonRpcErrorCode raise {
  match experimental_v2_agent_test_step_response(step) {
    Error(failure) => failure.error.code
    Success(_) => fail("expected an error response")
  }
}

///|
async fn experimental_v2_agent_test_cycle(
  endpoint : ExperimentalV2AgentEndpoint,
  state : ExperimentalV2AgentAdapterState,
  message : @jsonrpc.JsonRpcMessage,
) -> ExperimentalV2AgentAdapterStep {
  let context = experimental_v2_agent_fail_fast_context()
  let admission = try! experimental_v2_agent_adapter_admit(
    state, endpoint, message,
  )
  match admission {
    Immediate(step) => step
    Invoke(state~, invocation~) =>
      try! experimental_v2_agent_adapter_complete(
        state,
        invocation,
        experimental_v2_agent_execute(invocation, endpoint, context),
      )
  }
}

///|
async test "v2 agent adapter initialize success and duplicate rejection" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let step = try! experimental_v2_agent_test_cycle(
    endpoint,
    experimental_v2_agent_test_adapter_state(endpoint),
    experimental_v2_agent_test_request(
      String("init"),
      "initialize",
      experimental_v2_agent_test_initialize_params(),
    ),
  )
  let result = try! experimental_v2_agent_test_success_result(step)
  guard result is Object(fields) else {
    fail("initialize result must be an object")
  }
  guard fields.get("protocolVersion") is Some(Number(version, ..)) else {
    fail("initialize result must echo protocolVersion")
  }
  assert_eq(version, 2.0)
  assert_true(step.state.protocol.phase is AgentInitialized)
  assert_true(step.state.protocol.client_info is Some(_))
  let duplicate = try! experimental_v2_agent_test_cycle(
    endpoint,
    step.state,
    experimental_v2_agent_test_request(
      String("again"),
      "initialize",
      experimental_v2_agent_test_initialize_params(),
    ),
  )
  assert_eq(
    try! experimental_v2_agent_test_error_code(duplicate),
    InvalidRequest,
  )
  assert_true(duplicate.state.protocol.phase is AgentInitialized)
}

///|
async test "v2 agent adapter answers a version-1 offer with 2 and keeps state" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let offer = "{\"protocolVersion\":1,\"info\":{\"name\":\"client\",\"version\":\"1\"}}"
  let step = try! experimental_v2_agent_test_cycle(
    endpoint,
    experimental_v2_agent_test_adapter_state(endpoint),
    experimental_v2_agent_test_request(String("offer"), "initialize", offer),
  )
  let result = try! experimental_v2_agent_test_success_result(step)
  guard result is Object(fields) else {
    fail("negotiation answer must be an object")
  }
  guard fields.get("protocolVersion") is Some(Number(version, ..)) else {
    fail("negotiation answer must echo protocolVersion")
  }
  assert_eq(version, 2.0)
  // State is exactly the pre-initialized snapshot: same phase, no client info.
  assert_true(step.state.protocol.phase is AgentAwaitingInitialize)
  assert_true(step.state.protocol.client_info is None)
  // The peer may retry with version 2 on the same connection.
  let retry = try! experimental_v2_agent_test_cycle(
    endpoint,
    step.state,
    experimental_v2_agent_test_request(
      String("retry"),
      "initialize",
      experimental_v2_agent_test_initialize_params(),
    ),
  )
  assert_true(retry.state.protocol.phase is AgentInitialized)
}

///|
async test "v2 agent adapter rejects requests before initialize" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let step = try! experimental_v2_agent_test_cycle(
    endpoint,
    experimental_v2_agent_test_adapter_state(endpoint),
    experimental_v2_agent_test_request(
      String("early"),
      "session/new",
      "{\"cwd\":\"/\"}",
    ),
  )
  assert_eq(try! experimental_v2_agent_test_error_code(step), InvalidRequest)
  assert_true(step.state.protocol.phase is AgentAwaitingInitialize)
}

///|
async test "v2 agent adapter completes every baseline session method" {
  let endpoint = experimental_v2_agent_test_endpoint(
    with_delete=true,
    with_fork=true,
  )
  let state = experimental_v2_agent_test_initialized(endpoint)
  // Meta-only baseline results encode as the empty object; the payload
  // carriers must keep their required keys.
  let cases : Array[(String, String, String?)] = [
    ("session/new", "{\"cwd\":\"/\"}", Some("sessionId")),
    ("session/list", "{}", Some("sessions")),
    ("session/resume", "{\"sessionId\":\"created\",\"cwd\":\"/\"}", None),
    ("session/close", "{\"sessionId\":\"created\"}", None),
    (
      "session/prompt",
      "{\"sessionId\":\"created\",\"prompt\":[{\"type\":\"text\",\"text\":\"hi\"}]}",
      None,
    ),
    (
      "session/set_config_option",
      "{\"type\":\"id\",\"sessionId\":\"created\",\"configId\":\"model\",\"value\":\"mini\"}",
      Some("configOptions"),
    ),
    ("session/delete", "{\"sessionId\":\"created\"}", None),
    (
      "session/fork",
      "{\"sessionId\":\"created\",\"cwd\":\"/\"}",
      Some("sessionId"),
    ),
  ]
  for index, entry in cases {
    let method_name = entry.0
    let step = try! experimental_v2_agent_test_cycle(
      endpoint,
      state,
      experimental_v2_agent_test_request(
        Number(index.to_int64()),
        method_name,
        entry.1,
      ),
    )
    let result = try! experimental_v2_agent_test_success_result(step)
    guard result is Object(fields) else {
      fail("result of " + method_name + " must be an object")
    }
    match entry.2 {
      Some(key) => assert_true(fields.contains(key))
      None => assert_eq(fields.length(), 0)
    }
    assert_true(step.state.reservation is Idle)
  }
}

///|
async test "v2 agent adapter maps typed handler failures onto wire errors" {
  let failing : ExperimentalV2AgentPromptHandler = async fn(_context, _params) {
    @async.pause()
    raise ExperimentalV2AgentHandlerError::Application(message="boom")
  }
  let endpoint = experimental_v2_agent_test_endpoint(prompt=failing)
  let state = experimental_v2_agent_test_initialized(endpoint)
  let step = try! experimental_v2_agent_test_cycle(
    endpoint,
    state,
    experimental_v2_agent_test_request(
      String("fails"),
      "session/prompt",
      "{\"sessionId\":\"created\",\"prompt\":[]}",
    ),
  )
  assert_eq(try! experimental_v2_agent_test_error_code(step), InternalError)
}

///|
async test "v2 agent adapter settles a typed cancellation as request cancelled" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  let context = experimental_v2_agent_fail_fast_context()
  let invocation : ExperimentalV2AgentInvocation = SessionNewInvocation(
    id=String("cancel-me"),
    params={
      cwd: "/",
      additional_directories: None,
      mcp_servers: None,
      meta: None,
    },
  )
  let step = try! experimental_v2_agent_adapter_complete(
    state,
    invocation,
    experimental_v2_agent_cancel_completion(invocation),
  )
  ignore(context)
  assert_eq(try! experimental_v2_agent_test_error_code(step), RequestCancelled)
}

///|
async test "v2 agent adapter gates capability-marked methods without invoking" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  let denied = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(
      String("denied"),
      "session/delete",
      "{\"sessionId\":\"created\"}",
    ),
  )
  match denied {
    Immediate(step) =>
      assert_eq(
        try! experimental_v2_agent_test_error_code(step),
        ResourceNotFound,
      )
    Invoke(..) => fail("a gated method must not invoke")
  }
  // Upstream unstable (RFD session-fork, Draft): the unadvertised fork method
  // denies without invoking too.
  let fork_denied = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(
      String("fork-denied"),
      "session/fork",
      "{\"sessionId\":\"created\",\"cwd\":\"/\"}",
    ),
  )
  match fork_denied {
    Immediate(step) =>
      assert_eq(
        try! experimental_v2_agent_test_error_code(step),
        ResourceNotFound,
      )
    Invoke(..) => fail("a gated method must not invoke")
  }
  let image = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(
      String("image"),
      "session/prompt",
      "{\"sessionId\":\"created\",\"prompt\":[{\"type\":\"image\",\"data\":\"aGVsbG8=\",\"mimeType\":\"image/png\"}]}",
    ),
  )
  match image {
    Immediate(step) =>
      assert_eq(
        try! experimental_v2_agent_test_error_code(step),
        ResourceNotFound,
      )
    Invoke(..) => fail("a gated method must not invoke")
  }
  let directories = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(
      String("dirs"),
      "session/new",
      "{\"cwd\":\"/\",\"additionalDirectories\":[\"/tmp\"]}",
    ),
  )
  match directories {
    Immediate(step) =>
      assert_eq(
        try! experimental_v2_agent_test_error_code(step),
        ResourceNotFound,
      )
    Invoke(..) => fail("a gated method must not invoke")
  }
  assert_eq(state, experimental_v2_agent_test_initialized(endpoint))
}

///|
async test "v2 agent adapter answers unknown and v1-only methods typed" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  for method_name in ["session/load", "authenticate", "session/set_mode"] {
    let step = try! experimental_v2_agent_test_cycle(
      endpoint,
      state,
      experimental_v2_agent_test_request(String("unknown"), method_name, "{}"),
    )
    assert_eq(try! experimental_v2_agent_test_error_code(step), MethodNotFound)
  }
}

///|
async test "v2 agent adapter answers malformed params typed" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  let step = try! experimental_v2_agent_test_cycle(
    endpoint,
    state,
    experimental_v2_agent_test_request(
      String("relative"),
      "session/new",
      "{\"cwd\":\"relative\"}",
    ),
  )
  assert_eq(try! experimental_v2_agent_test_error_code(step), InvalidParams)
}

///|
async test "v2 agent adapter login reserves, completes, and rejects duplicates" {
  let endpoint = experimental_v2_agent_test_endpoint(with_auth=true)
  let state = experimental_v2_agent_test_initialized(endpoint)
  assert_true(state.protocol.authentication is AuthPending)
  let admitted = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(
      String("login-1"),
      "auth/login",
      "{\"methodId\":\"token\"}",
    ),
  )
  let (reserved, invocation) : (
    ExperimentalV2AgentAdapterState,
    ExperimentalV2AgentInvocation,
  ) = match admitted {
    Invoke(state~, invocation~) => {
      assert_true(state.reservation is LoginPending(String("login-1")))
      assert_true(state.protocol.authentication is AuthPending)
      (state, invocation)
    }
    Immediate(_) => fail("login must invoke the auth handler")
  }
  let busy = try! experimental_v2_agent_adapter_admit(
    reserved,
    endpoint,
    experimental_v2_agent_test_request(
      String("login-2"),
      "auth/login",
      "{\"methodId\":\"token\"}",
    ),
  )
  match busy {
    Immediate(step) =>
      assert_eq(
        try! experimental_v2_agent_test_error_code(step),
        InvalidRequest,
      )
    Invoke(..) => fail("a reserved auth surface must answer busy")
  }
  let step = try! experimental_v2_agent_adapter_complete(
    reserved,
    invocation,
    AuthLoginCompleted(id=String("login-1"), result=Ok({ meta: None, })),
  )
  ignore(try! experimental_v2_agent_test_success_result(step))
  assert_true(step.state.protocol.authentication is AuthLoggedIn)
  assert_true(step.state.reservation is Idle)
  try
    experimental_v2_agent_adapter_complete(
      step.state,
      invocation,
      AuthLoginCompleted(id=String("login-1"), result=Ok({ meta: None, })),
    )
  catch {
    LateCompletion(request_id~) => assert_eq(request_id, String("login-1"))
    _ => fail("expected LateCompletion")
  } noraise {
    _ => fail("expected LateCompletion")
  }
}

///|
async test "v2 agent adapter logout lifecycle gates sessions while pending" {
  let endpoint = experimental_v2_agent_test_endpoint(with_auth=true)
  let state = experimental_v2_agent_test_initialized(endpoint)
  // Logout before login is a typed auth-state failure, not an invoke.
  let early = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(
      String("early-logout"),
      "auth/logout",
      "{}",
    ),
  )
  match early {
    Immediate(step) =>
      assert_eq(try! experimental_v2_agent_test_error_code(step), AuthRequired)
    Invoke(..) => fail("logout before login must not invoke")
  }
  // Log in first.
  let login = try! experimental_v2_agent_test_cycle(
    endpoint,
    state,
    experimental_v2_agent_test_request(
      String("login-1"),
      "auth/login",
      "{\"methodId\":\"token\"}",
    ),
  )
  assert_true(login.state.protocol.authentication is AuthLoggedIn)
  // Logout reserves; session requests answer busy until it settles.
  let logout = try! experimental_v2_agent_adapter_admit(
    login.state,
    endpoint,
    experimental_v2_agent_test_request(String("logout-1"), "auth/logout", "{}"),
  )
  let (reserved, _invocation) : (
    ExperimentalV2AgentAdapterState,
    ExperimentalV2AgentInvocation,
  ) = match logout {
    Invoke(state~, invocation~) => {
      assert_true(state.reservation is LogoutPending(String("logout-1")))
      (state, invocation)
    }
    Immediate(_) => fail("logout must invoke the auth handler")
  }
  let busy = try! experimental_v2_agent_adapter_admit(
    reserved,
    endpoint,
    experimental_v2_agent_test_request(
      String("blocked"),
      "session/new",
      "{\"cwd\":\"/\"}",
    ),
  )
  match busy {
    Immediate(step) =>
      assert_eq(
        try! experimental_v2_agent_test_error_code(step),
        InvalidRequest,
      )
    Invoke(..) => fail("a session request over a pending logout answers busy")
  }
}

///|
async test "v2 agent adapter completes logout back to pending" {
  let endpoint = experimental_v2_agent_test_endpoint(with_auth=true)
  let state = experimental_v2_agent_test_initialized(endpoint)
  let login = try! experimental_v2_agent_test_cycle(
    endpoint,
    state,
    experimental_v2_agent_test_request(
      String("login-1"),
      "auth/login",
      "{\"methodId\":\"token\"}",
    ),
  )
  let admitted = try! experimental_v2_agent_adapter_admit(
    login.state,
    endpoint,
    experimental_v2_agent_test_request(String("logout-1"), "auth/logout", "{}"),
  )
  match admitted {
    Invoke(state~, invocation~) => {
      let step = try! experimental_v2_agent_adapter_complete(
        state,
        invocation,
        AuthLogoutCompleted(id=String("logout-1"), result=Ok({ meta: None, })),
      )
      ignore(try! experimental_v2_agent_test_success_result(step))
      assert_true(step.state.protocol.authentication is AuthPending)
      assert_true(step.state.reservation is Idle)
    }
    Immediate(_) => fail("logout must invoke the auth handler")
  }
}

///|
async test "v2 agent adapter rejects an unadvertised auth method id" {
  let endpoint = experimental_v2_agent_test_endpoint(with_auth=true)
  let state = experimental_v2_agent_test_initialized(endpoint)
  let step = try! experimental_v2_agent_test_cycle(
    endpoint,
    state,
    experimental_v2_agent_test_request(
      String("unknown-method"),
      "auth/login",
      "{\"methodId\":\"oauth\"}",
    ),
  )
  assert_eq(try! experimental_v2_agent_test_error_code(step), AuthRequired)
}

///|
async test "v2 agent adapter rejects auth calls when auth is not advertised" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  let no_auth_cases : Array[(String, String)] = [
    ("auth/login", "{\"methodId\":\"token\"}"),
    ("auth/logout", "{}"),
  ]
  for entry in no_auth_cases {
    let step = try! experimental_v2_agent_test_cycle(
      endpoint,
      state,
      experimental_v2_agent_test_request(String("no-auth"), entry.0, entry.1),
    )
    assert_eq(try! experimental_v2_agent_test_error_code(step), InvalidRequest)
  }
}

///|
async test "v2 agent adapter completes late and mismatched typed" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  let admitted = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_request(String("list-1"), "session/list", "{}"),
  )
  let invocation : ExperimentalV2AgentInvocation = match admitted {
    Invoke(state~, invocation~) => {
      ignore(state)
      invocation
    }
    Immediate(_) => fail("session/list must invoke")
  }
  // A completion of a different constructor for the same id is a mismatch.
  try
    experimental_v2_agent_adapter_complete(
      state,
      invocation,
      SessionNewCompleted(
        id=String("list-1"),
        result=Ok({ session_id: "created", config_options: None, meta: None, }),
      ),
    )
  catch {
    CompletionMismatch(method_name~) =>
      inspect(method_name, content="session/list")
    _ => fail("expected CompletionMismatch")
  } noraise {
    _ => fail("expected CompletionMismatch")
  }
  // A completion for a different wire id is late.
  try
    experimental_v2_agent_adapter_complete(
      state,
      invocation,
      SessionListCompleted(
        id=String("other"),
        result=Ok({ sessions: [], next_cursor: None, meta: None, }),
      ),
    )
  catch {
    LateCompletion(request_id~) => assert_eq(request_id, String("other"))
    _ => fail("expected LateCompletion")
  } noraise {
    _ => fail("expected LateCompletion")
  }
}

///|
async test "v2 agent adapter consumes session cancel and forwards cancel request" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_initialized(endpoint)
  let cancel = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_notification(
      "session/cancel", "{\"sessionId\":\"created\"}",
    ),
  )
  match cancel {
    Immediate(step) => {
      assert_eq(step.outputs.length(), 0)
      assert_eq(step.state.protocol, state.protocol)
    }
    Invoke(..) => fail("session/cancel carries no owner invocation")
  }
  let cancel_cases : Array[(String, ExperimentalV2RequestId)] = [
    ("{\"requestId\":\"victim\"}", RequestIdStr("victim")),
    ("{\"requestId\":7}", RequestIdNumber(7)),
  ]
  for entry in cancel_cases {
    let expected = entry.1
    let forwarded = try! experimental_v2_agent_adapter_admit(
      state,
      endpoint,
      experimental_v2_agent_test_notification("$/cancel_request", entry.0),
    )
    match forwarded {
      Immediate(step) =>
        match step.outputs {
          [Command(CancelRequest(request_id~))] =>
            assert_eq(request_id, expected)
          _ => fail("expected one cancel command")
        }
      Invoke(..) => fail("$/cancel_request must be immediate")
    }
  }
}

///|
async test "v2 agent adapter traces notifications before initialize" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let state = experimental_v2_agent_test_adapter_state(endpoint)
  let early = try! experimental_v2_agent_adapter_admit(
    state,
    endpoint,
    experimental_v2_agent_test_notification(
      "session/cancel", "{\"sessionId\":\"created\"}",
    ),
  )
  match early {
    Immediate(step) => {
      assert_eq(step.outputs.length(), 1)
      match step.outputs[0] {
        Command(TraceError(method_name~, error=_)) =>
          inspect(method_name, content="session/cancel")
        _ => fail("expected one trace command")
      }
      assert_eq(step.state.protocol, state.protocol)
    }
    Invoke(..) => fail("a rejected notification must not invoke")
  }
}

///|
async test "v2 agent adapter fail-fast on endpoint drift and responses" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let other = experimental_v2_agent_endpoint_from_spec(
    try! experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("other"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
    ),
  )
  let state = experimental_v2_agent_test_adapter_state(endpoint)
  try
    experimental_v2_agent_adapter_admit(
      state,
      other,
      experimental_v2_agent_test_request(
        String("init"),
        "initialize",
        experimental_v2_agent_test_initialize_params(),
      ),
    )
  catch {
    EndpointMismatch(reason~) =>
      inspect(reason, content="state agent info does not match endpoint")
    _ => fail("expected EndpointMismatch")
  } noraise {
    _ => fail("expected EndpointMismatch")
  }
  try
    experimental_v2_agent_adapter_admit(
      state,
      endpoint,
      @jsonrpc.JsonRpcMessage::response(
        @jsonrpc.JsonRpcResponse::success(
          id=String("reply"),
          result=Json::null(),
        ),
      ),
    )
  catch {
    UnexpectedMessage(kind~) => inspect(kind, content="response")
    _ => fail("expected UnexpectedMessage")
  } noraise {
    _ => fail("expected UnexpectedMessage")
  }
}
