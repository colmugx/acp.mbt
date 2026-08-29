///|
async fn agent_adapter_test_resume(
  _context : AgentContext,
  _params : ResumeSessionParams,
) -> ResumeSessionResult {
  @async.pause()
  { modes: Omitted, config_options: Omitted, meta: Omitted, }
}

///|
async fn agent_adapter_test_fork(
  _context : AgentContext,
  _params : ForkSessionParams,
) -> ForkSessionResult {
  @async.pause()
  {
    session_id: "forked",
    modes: Omitted,
    config_options: Omitted,
    meta: Omitted,
  }
}

///|
async fn agent_adapter_test_failing_fork(
  _context : AgentContext,
  _params : ForkSessionParams,
) -> ForkSessionResult {
  @async.pause()
  raise HandlerError::Application(message="fork failed")
}

///|
async fn agent_adapter_test_delete(
  _context : AgentContext,
  _params : DeleteSessionParams,
) -> DeleteSessionResult {
  @async.pause()
  { meta: Omitted, }
}

///|
async fn agent_adapter_test_close(
  _context : AgentContext,
  _params : CloseSessionParams,
) -> CloseSessionResult {
  @async.pause()
  { meta: Omitted, }
}

///|
async fn agent_adapter_test_set_mode(
  _context : AgentContext,
  _params : SetSessionModeParams,
) -> SetSessionModeResult {
  @async.pause()
  { meta: Omitted, }
}

///|
async fn agent_adapter_test_set_config(
  _context : AgentContext,
  _params : SetSessionConfigOptionParams,
) -> SetSessionConfigOptionResult {
  @async.pause()
  { config_options: [], meta: Omitted, }
}

///|
async fn agent_adapter_test_failing_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  raise HandlerError::Application(message="handler failed")
}

///|
async fn agent_adapter_test_cancelled_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  raise HandlerError::Cancelled
}

///|
async fn agent_adapter_test_thrown_cancel_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.pause()
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  abort("expected task cancellation")
}

///|
async fn agent_adapter_test_failing_auth(
  _context : AgentContext,
  _params : AuthenticateParams,
) -> AuthenticateResult {
  @async.pause()
  raise HandlerError::Application(message="authentication failed")
}

///|
async fn agent_adapter_test_cancelled_auth(
  _context : AgentContext,
  _params : AuthenticateParams,
) -> AuthenticateResult {
  @async.pause()
  raise HandlerError::Cancelled
}

///|
async fn agent_adapter_test_thrown_cancel_auth(
  _context : AgentContext,
  _params : AuthenticateParams,
) -> AuthenticateResult {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.pause()
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  abort("expected task cancellation")
}

///|
async fn agent_adapter_test_thrown_cancel_logout(
  _context : AgentContext,
  _params : LogoutParams,
) -> LogoutResult {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.pause()
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  abort("expected task cancellation")
}

///|
async fn agent_adapter_test_failing_cancel(
  _context : AgentContext,
  _params : CancelParams,
) -> Unit {
  @async.pause()
  raise HandlerError::Application(message="cancel failed")
}

///|
async fn agent_adapter_test_unknown_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  raise AgentContextError::AgentContextBrokerFailure(
    method_name="secret-handler-detail",
  )
}

///|
fn agent_adapter_test_sessions(
  new_session? : AgentNewSessionHandler = agent_service_test_new,
  cancel? : AgentCancelHandler = agent_service_test_cancel,
) -> AgentSessionService {
  agent_session_service(
    new_session~,
    prompt=agent_service_test_prompt,
    cancel~,
    load=agent_service_test_load,
    resume_session=agent_adapter_test_resume,
    fork_session=agent_adapter_test_fork,
    list=agent_service_test_list,
    delete=agent_adapter_test_delete,
    close=agent_adapter_test_close,
    set_mode=agent_adapter_test_set_mode,
    set_config_option=agent_adapter_test_set_config,
  )
}

///|
fn agent_adapter_test_endpoint(
  new_session? : AgentNewSessionHandler = agent_service_test_new,
  cancel? : AgentCancelHandler = agent_service_test_cancel,
) -> AgentEndpoint {
  let spec = agent_spec(
    info=agent_service_test_info("adapter"),
    sessions=agent_adapter_test_sessions(new_session~, cancel~),
    support=agent_support(),
  ).unwrap()
  agent_endpoint_from_spec(spec)
}

///|
fn agent_adapter_test_b09_endpoint(support : AgentSupport) -> AgentEndpoint {
  agent_endpoint_from_spec(
    agent_spec(
      info=agent_service_test_info("adapter-b09"),
      sessions=agent_adapter_test_sessions(),
      support~,
    ).unwrap(),
  )
}

///|
fn agent_adapter_test_auth_endpoint_with(
  authenticate : AgentAuthenticateHandler,
  logout? : AgentLogoutHandler = agent_service_test_logout,
) -> AgentEndpoint {
  let auth_method : AuthMethod = {
    id: "token",
    name: "Token",
    description: Omitted,
    meta: Omitted,
  }
  let auth = try
    agent_auth_service(methods=[auth_method], authenticate~, logout~)
  catch {
    _ => abort("adapter auth fixture must be valid")
  } noraise {
    value => value
  }
  let spec = agent_spec(
    info=agent_service_test_info("adapter-auth"),
    sessions=agent_adapter_test_sessions(),
    support=agent_support(),
    auth~,
  ).unwrap()
  agent_endpoint_from_spec(spec)
}

///|
fn agent_adapter_test_auth_endpoint() -> AgentEndpoint {
  agent_adapter_test_auth_endpoint_with(agent_service_test_authenticate)
}

///|
fn agent_adapter_test_state(endpoint : AgentEndpoint) -> AgentAdapterState {
  let config : AgentProtocolConfig = {
    agent_capabilities: Value(endpoint.capabilities()),
    auth_methods: endpoint.auth_methods(),
    agent_info: Omitted,
  }
  agent_adapter_state_new(protocol=agent_protocol_state_new(config~))
}

///|
fn agent_adapter_test_json(source : String) -> Json {
  protocol_parse_json(source) catch {
    _ => abort("adapter test fixture must be valid JSON")
  }
}

///|
fn agent_adapter_test_request(
  id : RequestId,
  method_name : String,
  params : String,
) -> JsonRpcMessage {
  let request = JsonRpcRequest::new(
    id~,
    method_name~,
    params=agent_adapter_test_json(params),
  ) catch {
    _ => abort("adapter test request must have structured params")
  }
  JsonRpcMessage::request(request)
}

///|
fn agent_adapter_test_notification(
  method_name : String,
  params : String,
) -> JsonRpcMessage {
  let notification = JsonRpcNotification::new(
    method_name~,
    params=agent_adapter_test_json(params),
  ) catch {
    _ => abort("adapter test notification must have structured params")
  }
  JsonRpcMessage::notification(notification)
}

///|
fn agent_adapter_test_response(
  step : AgentAdapterStep,
) -> JsonRpcResponse raise {
  match step.outputs[0] {
    Response(response) => response
    _ => fail("expected one JSON-RPC response")
  }
}

///|
fn agent_adapter_test_success(
  step : AgentAdapterStep,
  id : RequestId,
) -> Json raise {
  match agent_adapter_test_response(step) {
    Success(success) => {
      assert_eq(success.id, id)
      success.result
    }
    Error(_) => fail("expected a successful JSON-RPC response")
  }
}

///|
fn agent_adapter_test_error_code(
  step : AgentAdapterStep,
) -> JsonRpcErrorCode raise {
  match agent_adapter_test_response(step) {
    Error(failure) => failure.error.code
    Success(_) => fail("expected a JSON-RPC error response")
  }
}

///|
fn agent_adapter_test_initialized(
  endpoint : AgentEndpoint,
  id : RequestId,
) -> AgentAdapterStep {
  let admission = try
    agent_adapter_admit(
      agent_adapter_test_state(endpoint),
      endpoint,
      agent_adapter_test_request(
        id, "initialize", "{\"protocolVersion\":1,\"clientCapabilities\":{\"session\":{\"configOptions\":{\"boolean\":{}}}}}",
      ),
    )
  catch {
    _ => abort("initialize admission must not fail")
  } noraise {
    value => value
  }
  match admission {
    Immediate(step) => step
    Invoke(..) => abort("initialize must complete synchronously")
  }
}

///|
async fn agent_adapter_test_invoke(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
  context : AgentContext,
  message : JsonRpcMessage,
) -> AgentAdapterStep {
  let admission = try agent_adapter_admit(state, endpoint, message) catch {
    _ => abort("request admission must not fail")
  } noraise {
    value => value
  }
  match admission {
    Immediate(_) => abort("expected an admitted async invocation")
    Invoke(state=invocation_state, invocation~) => {
      let completion = agent_adapter_execute(invocation, endpoint, context)
      try
        agent_adapter_complete(invocation_state, invocation, completion)
      catch {
        _ => abort("typed invocation completion must match admission")
      } noraise {
        value => value
      }
    }
  }
}

///|
async test "adapter initializes immediately and rejects a second initialize" {
  let endpoint = agent_adapter_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let context = agent_service_test_context()
  let first = agent_adapter_test_initialized(endpoint, Number(1))
  assert_eq(first.state.protocol().phase, Initialized)
  ignore(agent_adapter_test_success(first, Number(1)))
  let second_admission = try
    agent_adapter_admit(
      first.state,
      endpoint,
      agent_adapter_test_request(
        String("second"),
        "initialize",
        "{\"protocolVersion\":1}",
      ),
    )
  catch {
    _ => abort("second initialize should be an immediate protocol error")
  } noraise {
    value => value
  }
  match second_admission {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
      assert_eq(step.state, first.state)
    }
    Invoke(..) => fail("second initialize must not start a handler")
  }
  ignore(context)
  ignore(initial)
}

///|
test "adapter rejects boolean config without client capability" {
  let endpoint = agent_adapter_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let initialized = match
    agent_adapter_admit(
      initial,
      endpoint,
      agent_adapter_test_request(
        Number(1),
        "initialize",
        "{\"protocolVersion\":1}",
      ),
    ) {
    Immediate(step) => step
    Invoke(..) => fail("initialize must complete synchronously")
  }
  let admission = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(2),
      "session/set_config_option",
      "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
    ),
  )
  match admission {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
    Invoke(..) => fail("denied boolean config must not invoke a handler")
  }
}

///|
test "adapter gates B09 MCP and workspace capabilities before invocation" {
  let unsupported_endpoint = agent_adapter_test_b09_endpoint(agent_support())
  let unsupported_initialized = agent_adapter_test_initialized(
    unsupported_endpoint,
    Number(1),
  )
  let transport_denied = agent_adapter_admit(
    unsupported_initialized.state,
    unsupported_endpoint,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]}",
    ),
  )
  match transport_denied {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, unsupported_initialized.state)
    }
    Invoke(..) => fail("denied MCP transport must not invoke a handler")
  }

  let roots_denied = agent_adapter_admit(
    unsupported_initialized.state,
    unsupported_endpoint,
    agent_adapter_test_request(
      Number(3),
      "session/new",
      "{\"cwd\":\"/\",\"additionalDirectories\":[\"/tmp/workspace\"],\"mcpServers\":[]}",
    ),
  )
  match roots_denied {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, unsupported_initialized.state)
    }
    Invoke(..) =>
      fail("denied additional directories must not invoke a handler")
  }

  let enabled_endpoint = agent_adapter_test_b09_endpoint(
    agent_support(mcp_http=true, additional_directories=true),
  )
  let enabled_initialized = agent_adapter_test_initialized(
    enabled_endpoint,
    Number(4),
  )
  let enabled = agent_adapter_admit(
    enabled_initialized.state,
    enabled_endpoint,
    agent_adapter_test_request(
      Number(5),
      "session/new",
      "{\"cwd\":\"/\",\"additionalDirectories\":[\"/tmp/workspace\"],\"mcpServers\":[{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]}",
    ),
  )
  match enabled {
    Invoke(state=_, invocation=SessionNewInvocation(id=Number(5), params=_)) =>
      ()
    Immediate(_) => fail("enabled MCP and workspace capabilities must invoke")
    Invoke(..) => fail("enabled B09 request admitted the wrong invocation")
  }
}

///|
async test "adapter admits executes and completes every stable session request" {
  let endpoint = agent_adapter_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let state = initialized.state
  let context = agent_service_test_context()
  ignore(agent_adapter_test_success(initialized, Number(1)))
  let new_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  ignore(agent_adapter_test_success(new_step, Number(2)))
  let load_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      String("load"),
      "session/load",
      "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
    ),
  )
  ignore(agent_adapter_test_success(load_step, String("load")))
  let resume_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(4),
      "session/resume",
      "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    ),
  )
  ignore(agent_adapter_test_success(resume_step, Number(4)))
  let list_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(Number(5), "session/list", "{}"),
  )
  ignore(agent_adapter_test_success(list_step, Number(5)))
  let delete_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(6),
      "session/delete",
      "{\"sessionId\":\"s\"}",
    ),
  )
  ignore(agent_adapter_test_success(delete_step, Number(6)))
  let close_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(7),
      "session/close",
      "{\"sessionId\":\"s\"}",
    ),
  )
  ignore(agent_adapter_test_success(close_step, Number(7)))
  let mode_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(8),
      "session/set_mode",
      "{\"sessionId\":\"s\",\"modeId\":\"code\"}",
    ),
  )
  ignore(agent_adapter_test_success(mode_step, Number(8)))
  let config_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(9),
      "session/set_config_option",
      "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
    ),
  )
  ignore(agent_adapter_test_success(config_step, Number(9)))
  let prompt_step = agent_adapter_test_invoke(
    state,
    endpoint,
    context,
    agent_adapter_test_request(
      String("prompt"),
      "session/prompt",
      "{\"sessionId\":\"s\",\"prompt\":[]}",
    ),
  )
  ignore(agent_adapter_test_success(prompt_step, String("prompt")))
}

///|
async test "adapter completes session fork with a typed frame for success and failure" {
  let endpoint = agent_adapter_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let context = agent_service_test_context()
  let forked = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(2),
      "session/fork",
      "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    ),
  )
  let decoded = fork_session_result_from_json(
    agent_adapter_test_success(forked, Number(2)),
  )
  assert_eq(decoded.session_id, "forked")
  let failing_endpoint = agent_endpoint_from_spec(
    agent_spec(
      info=agent_service_test_info("adapter-fork-failing"),
      sessions=agent_session_service(
        new_session=agent_service_test_new,
        prompt=agent_service_test_prompt,
        cancel=agent_service_test_cancel,
        fork_session=agent_adapter_test_failing_fork,
      ),
      support=agent_support(),
    ).unwrap(),
  )
  let failing_initialized = agent_adapter_test_initialized(
    failing_endpoint,
    Number(3),
  )
  let failed = agent_adapter_test_invoke(
    failing_initialized.state,
    failing_endpoint,
    context,
    agent_adapter_test_request(
      Number(4),
      "session/fork",
      "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(failed), InternalError)
  assert_eq(failed.outputs.length(), 1)
  match agent_adapter_test_response(failed) {
    Error(failure) => assert_true(failure.error.message.contains("fork failed"))
    Success(_) => fail("a failing fork handler must not produce success")
  }
}

///|
async test "adapter reserves authentication and releases it on success" {
  let endpoint = agent_adapter_test_auth_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, String("init"))
  let context = agent_service_test_context()
  let auth_message = agent_adapter_test_request(
    Number(22),
    "authenticate",
    "{\"methodId\":\"token\"}",
  )
  let auth_admission = try
    agent_adapter_admit(initialized.state, endpoint, auth_message)
  catch {
    _ => abort("authentication admission must not fail")
  } noraise {
    value => value
  }
  let pending_state_and_invocation = match auth_admission {
    Invoke(state=pending, invocation=admitted) => {
      assert_true(pending.reservation() is AuthenticatePending(_))
      (pending, admitted)
    }
    Immediate(_) => abort("authentication must produce a typed invocation")
  }
  let pending_state = pending_state_and_invocation.0
  let invocation = pending_state_and_invocation.1
  let second_auth = try
    agent_adapter_admit(pending_state, endpoint, auth_message)
  catch {
    _ => abort("pending authentication should be rejected immediately")
  } noraise {
    value => value
  }
  match second_auth {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
    Invoke(..) => fail("pending authentication must not admit another handler")
  }
  let pending_session = try
    agent_adapter_admit(
      pending_state,
      endpoint,
      agent_adapter_test_request(Number(23), "session/list", "{}"),
    )
  catch {
    _ => abort("pending authentication should gate session requests")
  } noraise {
    value => value
  }
  match pending_session {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), AuthRequired)
    Invoke(..) => fail("pending authentication must gate session handlers")
  }
  let completion = agent_adapter_execute(invocation, endpoint, context)
  let completed = agent_adapter_complete(pending_state, invocation, completion)
  ignore(agent_adapter_test_success(completed, Number(22)))
  assert_eq(completed.state.protocol().authentication, Authenticated)
  assert_true(completed.state.reservation() is Idle)
  try agent_adapter_complete(completed.state, invocation, completion) catch {
    LateCompletion(request_id=Number(22)) => ()
    _ => fail("duplicate authentication completion must be late")
  } noraise {
    _ => fail("duplicate authentication completion must fail")
  }
}

///|
async test "adapter rejects pending logout and clears failed or cancelled auth" {
  let endpoint = agent_adapter_test_auth_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let context = agent_service_test_context()
  let auth_state_and_invocation = match
    (try
      agent_adapter_admit(
        initialized.state,
        endpoint,
        agent_adapter_test_request(
          Number(2),
          "authenticate",
          "{\"methodId\":\"token\"}",
        ),
      )
    catch {
      _ => abort("authentication admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("authentication must be pending")
  }
  let authenticated = agent_adapter_complete(
    auth_state_and_invocation.0,
    auth_state_and_invocation.1,
    agent_adapter_execute(auth_state_and_invocation.1, endpoint, context),
  )
  let logout_admission = try
    agent_adapter_admit(
      authenticated.state,
      endpoint,
      agent_adapter_test_request(String("logout"), "logout", "{}"),
    )
  catch {
    _ => abort("logout admission must not fail")
  } noraise {
    value => value
  }
  let logout_state_and_invocation = match logout_admission {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("logout must produce a typed invocation")
  }
  let logout_state = logout_state_and_invocation.0
  let logout_invocation = logout_state_and_invocation.1
  let duplicate_logout = try
    agent_adapter_admit(
      logout_state,
      endpoint,
      agent_adapter_test_request(Number(4), "logout", "{}"),
    )
  catch {
    _ => abort("pending logout should be rejected immediately")
  } noraise {
    value => value
  }
  match duplicate_logout {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
    Invoke(..) => fail("pending logout must not admit another handler")
  }
  let logout_session = try
    agent_adapter_admit(
      logout_state,
      endpoint,
      agent_adapter_test_request(Number(3), "session/list", "{}"),
    )
  catch {
    _ => abort("pending logout should gate session requests")
  } noraise {
    value => value
  }
  match logout_session {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
    Invoke(..) => fail("pending logout must gate session handlers")
  }
  let logout_completion = agent_adapter_execute(
    logout_invocation, endpoint, context,
  )
  let logged_out = agent_adapter_complete(
    logout_state, logout_invocation, logout_completion,
  )
  assert_eq(logged_out.state.protocol().authentication, AwaitingAuthentication)
  assert_true(logged_out.state.reservation() is Idle)

  let failing_endpoint = agent_adapter_test_auth_endpoint_with(
    agent_adapter_test_failing_auth,
  )
  let failing_initialized = agent_adapter_test_initialized(
    failing_endpoint,
    Number(5),
  )
  let failing_admission = match
    (try
      agent_adapter_admit(
        failing_initialized.state,
        failing_endpoint,
        agent_adapter_test_request(
          Number(6),
          "authenticate",
          "{\"methodId\":\"token\"}",
        ),
      )
    catch {
      _ => abort("failing authentication admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("failing authentication must be pending")
  }
  let failed = agent_adapter_complete(
    failing_admission.0,
    failing_admission.1,
    agent_adapter_execute(failing_admission.1, failing_endpoint, context),
  )
  assert_eq(agent_adapter_test_error_code(failed), InternalError)
  assert_true(failed.state.reservation() is Idle)

  let cancelled_endpoint = agent_adapter_test_auth_endpoint_with(
    agent_adapter_test_cancelled_auth,
  )
  let cancelled_initialized = agent_adapter_test_initialized(
    cancelled_endpoint,
    Number(7),
  )
  let cancelled_admission = match
    (try
      agent_adapter_admit(
        cancelled_initialized.state,
        cancelled_endpoint,
        agent_adapter_test_request(
          Number(8),
          "authenticate",
          "{\"methodId\":\"token\"}",
        ),
      )
    catch {
      _ => abort("cancelled authentication admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("cancelled authentication must be pending")
  }
  let cancelled = agent_adapter_complete(
    cancelled_admission.0,
    cancelled_admission.1,
    agent_adapter_execute(cancelled_admission.1, cancelled_endpoint, context),
  )
  assert_eq(agent_adapter_test_error_code(cancelled), RequestCancelled)
  assert_eq(cancelled.outputs.length(), 1)
  assert_true(cancelled.state.reservation() is Idle)
}

///|
async test "adapter maps real task cancellation and releases auth reservations" {
  let context = agent_service_test_context()
  let cancelled_session_endpoint = agent_adapter_test_endpoint(
    new_session=agent_adapter_test_thrown_cancel_new,
  )
  let cancelled_session_initialized = agent_adapter_test_initialized(
    cancelled_session_endpoint,
    Number(1),
  )
  let cancelled_session = agent_adapter_test_invoke(
    cancelled_session_initialized.state,
    cancelled_session_endpoint,
    context,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(cancelled_session), RequestCancelled)
  assert_eq(cancelled_session.outputs.length(), 1)

  let cancelled_auth_endpoint = agent_adapter_test_auth_endpoint_with(
    agent_adapter_test_thrown_cancel_auth,
  )
  let cancelled_auth_initialized = agent_adapter_test_initialized(
    cancelled_auth_endpoint,
    Number(10),
  )
  let cancelled_auth_admission = match
    (try
      agent_adapter_admit(
        cancelled_auth_initialized.state,
        cancelled_auth_endpoint,
        agent_adapter_test_request(
          Number(11),
          "authenticate",
          "{\"methodId\":\"token\"}",
        ),
      )
    catch {
      _ => abort("task-cancelled authentication admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("task-cancelled authentication must be pending")
  }
  let cancelled_auth_completion = agent_adapter_execute(
    cancelled_auth_admission.1,
    cancelled_auth_endpoint,
    context,
  )
  match cancelled_auth_completion {
    AuthenticateCompleted(id=Number(11), result=Err(Cancelled)) => ()
    _ => fail("real task cancellation must become a typed cancelled completion")
  }
  let cancelled_auth = agent_adapter_complete(
    cancelled_auth_admission.0,
    cancelled_auth_admission.1,
    cancelled_auth_completion,
  )
  assert_eq(agent_adapter_test_error_code(cancelled_auth), RequestCancelled)
  assert_eq(cancelled_auth.outputs.length(), 1)
  assert_true(cancelled_auth.state.reservation() is Idle)
  assert_true(
    cancelled_auth.state.protocol().authentication is AwaitingAuthentication,
  )

  let cancelled_logout_endpoint = agent_adapter_test_auth_endpoint_with(
    agent_service_test_authenticate,
    logout=agent_adapter_test_thrown_cancel_logout,
  )
  let cancelled_logout_initialized = agent_adapter_test_initialized(
    cancelled_logout_endpoint,
    Number(20),
  )
  let auth_admission = match
    (try
      agent_adapter_admit(
        cancelled_logout_initialized.state,
        cancelled_logout_endpoint,
        agent_adapter_test_request(
          Number(21),
          "authenticate",
          "{\"methodId\":\"token\"}",
        ),
      )
    catch {
      _ => abort("authentication admission before logout must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("authentication before logout must be pending")
  }
  let authenticated = agent_adapter_complete(
    auth_admission.0,
    auth_admission.1,
    agent_adapter_execute(auth_admission.1, cancelled_logout_endpoint, context),
  )
  ignore(agent_adapter_test_success(authenticated, Number(21)))
  assert_true(authenticated.state.protocol().authentication is Authenticated)
  let logout_admission = match
    (try
      agent_adapter_admit(
        authenticated.state,
        cancelled_logout_endpoint,
        agent_adapter_test_request(String("logout-cancel"), "logout", "{}"),
      )
    catch {
      _ => abort("task-cancelled logout admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("task-cancelled logout must be pending")
  }
  let cancelled_logout_completion = agent_adapter_execute(
    logout_admission.1,
    cancelled_logout_endpoint,
    context,
  )
  match cancelled_logout_completion {
    LogoutCompleted(id=String("logout-cancel"), result=Err(Cancelled)) => ()
    _ => fail("real task cancellation must cancel logout completion")
  }
  let cancelled_logout = agent_adapter_complete(
    logout_admission.0,
    logout_admission.1,
    cancelled_logout_completion,
  )
  assert_eq(agent_adapter_test_error_code(cancelled_logout), RequestCancelled)
  assert_eq(cancelled_logout.outputs.length(), 1)
  assert_true(cancelled_logout.state.reservation() is Idle)
  assert_true(cancelled_logout.state.protocol().authentication is Authenticated)
}

///|
async test "adapter completes concurrent prompts in reverse order with typed ids" {
  let endpoint = agent_adapter_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let context = agent_service_test_context()
  let first_admission = match
    (try
      agent_adapter_admit(
        initialized.state,
        endpoint,
        agent_adapter_test_request(
          Number(10),
          "session/prompt",
          "{\"sessionId\":\"s\",\"prompt\":[]}",
        ),
      )
    catch {
      _ => abort("first prompt admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("first prompt must be async")
  }
  let second_admission = match
    (try
      agent_adapter_admit(
        first_admission.0,
        endpoint,
        agent_adapter_test_request(
          String("prompt-2"),
          "session/prompt",
          "{\"sessionId\":\"s\",\"prompt\":[]}",
        ),
      )
    catch {
      _ => abort("second prompt admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("second prompt must be async")
  }
  let second_completion = agent_adapter_execute(
    second_admission.1,
    endpoint,
    context,
  )
  let second_completed = agent_adapter_complete(
    second_admission.0,
    second_admission.1,
    second_completion,
  )
  ignore(agent_adapter_test_success(second_completed, String("prompt-2")))
  let first_completion = agent_adapter_execute(
    first_admission.1,
    endpoint,
    context,
  )
  let first_completed = agent_adapter_complete(
    second_completed.state,
    first_admission.1,
    first_completion,
  )
  ignore(agent_adapter_test_success(first_completed, Number(10)))
}

///|
async test "adapter notifications emit no response and preserve cancellation ids" {
  let endpoint = agent_adapter_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let context = agent_service_test_context()
  let session_cancel = try
    agent_adapter_admit(
      initialized.state,
      endpoint,
      agent_adapter_test_notification("session/cancel", "{\"sessionId\":\"s\"}"),
    )
  catch {
    _ => abort("session cancellation admission must not fail")
  } noraise {
    value => value
  }
  match session_cancel {
    Invoke(state~, invocation~) => {
      let completed = agent_adapter_complete(
        state,
        invocation,
        agent_adapter_execute(invocation, endpoint, context),
      )
      assert_eq(completed.state, initialized.state)
      assert_eq(completed.outputs.length(), 0)
    }
    Immediate(_) => fail("session cancellation must invoke a typed handler")
  }
  let string_cancel = try
    agent_adapter_admit(
      initialized.state,
      endpoint,
      agent_adapter_test_notification(
        "$/cancel_request", "{\"requestId\":\"request-1\"}",
      ),
    )
  catch {
    _ => abort("string cancellation admission must not fail")
  } noraise {
    value => value
  }
  match string_cancel {
    Immediate(step) =>
      match step.outputs[0] {
        Command(CancelRequest(request_id=String(value))) =>
          assert_eq(value, "request-1")
        _ => fail("expected string cancellation command")
      }
    Invoke(..) => fail("$/cancel_request must not invoke an agent handler")
  }
  let integer_cancel = try
    agent_adapter_admit(
      initialized.state,
      endpoint,
      agent_adapter_test_notification("$/cancel_request", "{\"requestId\":42}"),
    )
  catch {
    _ => abort("integer cancellation admission must not fail")
  } noraise {
    value => value
  }
  match integer_cancel {
    Immediate(step) =>
      match step.outputs[0] {
        Command(CancelRequest(request_id=Number(value))) => assert_eq(value, 42)
        _ => fail("expected integer cancellation command")
      }
    Invoke(..) => fail("$/cancel_request must not invoke an agent handler")
  }
}

///|
test "adapter accepts unknown notifications as trace intents without responses" {
  let endpoint = agent_adapter_test_endpoint()
  let state = agent_adapter_test_state(endpoint)
  let admission = try
    agent_adapter_admit(
      state,
      endpoint,
      agent_adapter_test_notification("vendor/unknown", "{}"),
    )
  catch {
    _ => abort("unknown notification admission must not raise")
  } noraise {
    value => value
  }
  match admission {
    Immediate(step) => {
      assert_eq(step.state, state)
      assert_eq(step.outputs.length(), 1)
      match step.outputs[0] {
        Command(TraceError(method_name="vendor/unknown", error~)) => {
          assert_eq(error.code, MethodNotFound)
          assert_eq(error.message, "unknown method: vendor/unknown")
          assert_eq(
            error.data,
            Some(Json::string("unknown method: vendor/unknown")),
          )
        }
        Response(_) => fail("unknown notification must not emit a response")
        Notification(_) =>
          fail("unknown notification must not emit a notification")
        Command(_) => fail("unknown notification must emit a trace intent")
      }
    }
    Invoke(..) => fail("unknown notification must not invoke a handler")
  }
}

///|
async test "adapter maps unknown malformed and handler failures without success fallback" {
  let endpoint = agent_adapter_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let unknown = try
    agent_adapter_admit(
      initial,
      endpoint,
      agent_adapter_test_request(Number(1), "vendor/unknown", "{}"),
    )
  catch {
    _ => abort("unknown method admission must not raise")
  } noraise {
    value => value
  }
  match unknown {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), MethodNotFound)
    Invoke(..) => fail("unknown method must not invoke a handler")
  }
  let malformed = try
    agent_adapter_admit(
      initial,
      endpoint,
      agent_adapter_test_request(
        Number(2),
        "initialize",
        "{\"protocolVersion\":\"1\"}",
      ),
    )
  catch {
    _ => abort("malformed params admission must not raise")
  } noraise {
    value => value
  }
  match malformed {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidParams)
    Invoke(..) => fail("malformed params must not invoke a handler")
  }
  let not_initialized = try
    agent_adapter_admit(
      initial,
      endpoint,
      agent_adapter_test_request(
        Number(3),
        "session/new",
        "{\"cwd\":\"/\",\"mcpServers\":[]}",
      ),
    )
  catch {
    _ => abort("phase gate must not raise")
  } noraise {
    value => value
  }
  match not_initialized {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
    Invoke(..) => fail("uninitialized request must not invoke a handler")
  }
  let failing_endpoint = agent_adapter_test_endpoint(
    new_session=agent_adapter_test_failing_new,
  )
  let failing_initialized = agent_adapter_test_initialized(
    failing_endpoint,
    Number(4),
  )
  let failed = agent_adapter_test_invoke(
    failing_initialized.state,
    failing_endpoint,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(5),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(failed), InternalError)
  let cancelled_endpoint = agent_adapter_test_endpoint(
    new_session=agent_adapter_test_cancelled_new,
  )
  let cancelled_initialized = agent_adapter_test_initialized(
    cancelled_endpoint,
    Number(6),
  )
  let cancelled = agent_adapter_test_invoke(
    cancelled_initialized.state,
    cancelled_endpoint,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(7),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(cancelled), RequestCancelled)
  assert_eq(cancelled.outputs.length(), 1)

  let unknown_endpoint = agent_adapter_test_endpoint(
    new_session=agent_adapter_test_unknown_new,
  )
  let unknown_initialized = agent_adapter_test_initialized(
    unknown_endpoint,
    Number(8),
  )
  let unknown_admission = match
    (try
      agent_adapter_admit(
        unknown_initialized.state,
        unknown_endpoint,
        agent_adapter_test_request(
          Number(9),
          "session/new",
          "{\"cwd\":\"/\",\"mcpServers\":[]}",
        ),
      )
    catch {
      _ => abort("unknown handler admission must not fail")
    } noraise {
      value => value
    }) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => abort("unknown handler must produce an invocation")
  }
  let unknown_completion = agent_adapter_execute(
    unknown_admission.1,
    unknown_endpoint,
    agent_service_test_context(),
  )
  match unknown_completion {
    SessionNewCompleted(id=Number(9), result=Err(Application(message~))) => {
      // An unexpected exception names itself with the method context and
      // the error's display text, so users can paste it to a developer.
      assert_true(message.contains("session/new"))
      assert_true(message.contains("agent handler failed"))
    }
    _ => fail("unknown handler must become a detailed application failure")
  }
  let unknown = agent_adapter_complete(
    unknown_admission.0,
    unknown_admission.1,
    unknown_completion,
  )
  assert_eq(agent_adapter_test_error_code(unknown), InternalError)
  assert_eq(unknown.outputs.length(), 1)
  match agent_adapter_test_response(unknown) {
    Error(failure) => {
      assert_true(failure.error.message.contains("agent handler failed"))
      assert_eq(failure.error.data, Some(Json::string(failure.error.message)))
    }
    Success(_) => fail("unknown handler must not produce a success response")
  }
}

///|
async test "adapter traces failed session cancellation without a response" {
  let endpoint = agent_adapter_test_endpoint(
    cancel=agent_adapter_test_failing_cancel,
  )
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let admission = try
    agent_adapter_admit(
      initialized.state,
      endpoint,
      agent_adapter_test_notification("session/cancel", "{\"sessionId\":\"s\"}"),
    )
  catch {
    _ => abort("failed cancellation admission must not raise")
  } noraise {
    value => value
  }
  match admission {
    Invoke(state~, invocation~) => {
      let step = agent_adapter_complete(
        state,
        invocation,
        agent_adapter_execute(
          invocation,
          endpoint,
          agent_service_test_context(),
        ),
      )
      match step.outputs[0] {
        Command(TraceError(method_name="session/cancel", error=_)) => ()
        Response(_) => fail("notification failure must not emit a response")
        Command(_) => fail("unexpected notification command")
        Notification(_) =>
          fail("agent adapter must not emit a notification here")
      }
    }
    Immediate(_) => fail("failed cancellation must invoke a typed handler")
  }
}

///|
test "adapter fails fast when state and endpoint capabilities disagree" {
  let endpoint = agent_adapter_test_endpoint()
  let mismatched_config : AgentProtocolConfig = {
    agent_capabilities: Omitted,
    auth_methods: Omitted,
    agent_info: Omitted,
  }
  let mismatched = agent_adapter_state_new(
    protocol=agent_protocol_state_new(config=mismatched_config),
  )
  try
    agent_adapter_admit(
      mismatched,
      endpoint,
      agent_adapter_test_request(
        Number(1),
        "initialize",
        "{\"protocolVersion\":1}",
      ),
    )
  catch {
    EndpointMismatch(reason=_) => ()
    _ => fail("expected endpoint/state mismatch")
  } noraise {
    _ => fail("expected endpoint/state mismatch")
  }
}
