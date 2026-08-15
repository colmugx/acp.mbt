///|
/// SDK-scope acceptance tests for the v1 stable Client -> Agent method matrix
/// (rows C01-C13 of docs/implementation-plan/04-v1-completeness-matrix.md).
///
/// The adapter owns phase/capability gates, strict typed decode before any
/// handler runs, and typed result encoding afterwards.  Service-owned
/// boundaries (session registries, turn state, replay execution, session id
/// uniqueness) are asserted where the SDK must stay typed and fail fast and
/// are documented inline where the SDK deliberately holds no state.

///|
async fn agent_matrix_test_new_with_modes(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  let ask : SessionMode = {
    id: "ask",
    name: "Ask",
    description: Omitted,
    meta: Omitted,
  }
  let code : SessionMode = {
    id: "code",
    name: "Code",
    description: Omitted,
    meta: Omitted,
  }
  let modes : SessionModeState = {
    current_mode_id: "code",
    available_modes: [ask, code],
    meta: Omitted,
  }
  {
    session_id: "matrix-1",
    modes: Value(modes),
    config_options: Omitted,
    meta: Omitted,
  }
}

///|
/// A buggy handler returning a degenerate empty session id.  The result codec
/// must turn this into an observable failure, never a success response.
async fn agent_matrix_test_empty_id_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  { session_id: "", modes: Omitted, config_options: Omitted, meta: Omitted }
}

///|
/// Unknown persisted sessions are service-owned state; the handler reports
/// them as an unavailable operation which the adapter maps to a typed
/// resource-not-found error.
async fn agent_matrix_test_load_unknown_session(
  _context : AgentContext,
  _params : LoadSessionParams,
) -> LoadSessionResult {
  @async.pause()
  raise HandlerError::UnavailableOperation(method_name="session/load")
}

///|
async fn agent_matrix_test_delete_ok(
  _context : AgentContext,
  _params : DeleteSessionParams,
) -> DeleteSessionResult {
  @async.pause()
  { meta: Omitted }
}

///|
async fn agent_matrix_test_delete_unknown_session(
  _context : AgentContext,
  _params : DeleteSessionParams,
) -> DeleteSessionResult {
  @async.pause()
  raise HandlerError::UnavailableOperation(method_name="session/delete")
}

///|
async fn agent_matrix_test_list(
  _context : AgentContext,
  _params : ListSessionsParams,
) -> ListSessionsResult {
  @async.pause()
  let info : SessionInfo = {
    session_id: "s-1",
    cwd: "/workspace",
    additional_directories: Omitted,
    title: Value("Matrix"),
    updated_at: Omitted,
    meta: Omitted,
  }
  { sessions: [info], next_cursor: Value("next-1"), meta: Omitted }
}

///|
fn agent_matrix_test_select_option() -> SessionConfigOption {
  {
    id: "model",
    name: "Model",
    description: Omitted,
    category: Omitted,
    kind: Select({
      current_value: "fast",
      options: Ungrouped([
        { value: "fast", name: "Fast", description: Omitted, meta: Omitted },
        {
          value: "quality",
          name: "Quality",
          description: Omitted,
          meta: Omitted,
        },
      ]),
    }),
    meta: Omitted,
  }
}

///|
/// Returns the complete replacement option set after one update.
async fn agent_matrix_test_set_config(
  _context : AgentContext,
  _params : SetSessionConfigOptionParams,
) -> SetSessionConfigOptionResult {
  @async.pause()
  {
    config_options: [
      {
        id: "confirm",
        name: "Confirm actions",
        description: Omitted,
        category: Omitted,
        kind: Boolean({ current_value: true }),
        meta: Omitted,
      },
      agent_matrix_test_select_option(),
    ],
    meta: Omitted,
  }
}

///|
/// The final prompt response of a cancelled turn carries stopReason
/// "cancelled" as a success result, not a JSON-RPC error.
async fn agent_matrix_test_cancelled_prompt(
  _context : AgentContext,
  _params : PromptParams,
) -> PromptResult {
  @async.pause()
  let stop_reason : StopReason = Cancelled
  { stop_reason, meta: Omitted }
}

///|
fn agent_matrix_test_endpoint(
  new_session? : AgentNewSessionHandler = agent_service_test_new,
  prompt? : AgentPromptHandler = agent_service_test_prompt,
  load? : AgentLoadSessionHandler = agent_service_test_load,
  delete? : AgentDeleteSessionHandler = agent_matrix_test_delete_ok,
) -> AgentEndpoint {
  let spec = agent_spec(
    info=agent_service_test_info("matrix"),
    sessions=agent_session_service(
      new_session~,
      prompt~,
      cancel=agent_service_test_cancel,
      load~,
      resume_session=agent_adapter_test_resume,
      list=agent_matrix_test_list,
      delete~,
      close=agent_adapter_test_close,
      set_mode=agent_adapter_test_set_mode,
      set_config_option=agent_matrix_test_set_config,
    ),
    support=agent_support(),
  ).unwrap()
  agent_endpoint_from_spec(spec)
}

///|
/// Required-operations-only endpoint: every optional session capability is
/// omitted from the advertisement, so the matching methods must be denied
/// before any handler exists to call.
fn agent_matrix_test_minimal_endpoint() -> AgentEndpoint {
  let spec = agent_spec(
    info=agent_service_test_info("matrix-minimal"),
    sessions=agent_service_test_sessions(false),
    support=agent_support(),
  ).unwrap()
  agent_endpoint_from_spec(spec)
}

///|
fn agent_matrix_test_invoke_admission(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
  message : JsonRpcMessage,
) -> (AgentAdapterState, AgentAdapterInvocation) raise {
  match agent_adapter_admit(state, endpoint, message) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => fail("expected an admitted typed invocation")
  }
}

///|
async test "matrix C01 initialize response shape version auth and info are exact" {
  let endpoint = agent_matrix_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let misordered = agent_adapter_admit(
    initial,
    endpoint,
    agent_adapter_test_request(
      Number(0),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  match misordered {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
      assert_eq(step.state, initial)
    }
    Invoke(..) => fail("a session method before initialize must not invoke")
  }
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let decoded = initialize_result_from_json(
    agent_adapter_test_success(initialized, Number(1)),
  )
  assert_eq(decoded.protocol_version, 1)
  assert_eq(decoded.agent_capabilities, Value(endpoint.capabilities()))
  assert_eq(decoded.auth_methods, Omitted)
  assert_eq(decoded.agent_info, Value(endpoint.info()))
  assert_eq(initialized.state.protocol().phase, Initialized)
  let auth_endpoint = agent_adapter_test_auth_endpoint()
  let auth_initialized = agent_adapter_test_initialized(
    auth_endpoint,
    Number(2),
  )
  let auth_decoded = initialize_result_from_json(
    agent_adapter_test_success(auth_initialized, Number(2)),
  )
  assert_eq(auth_decoded.auth_methods, auth_endpoint.auth_methods())
  let duplicate = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(3),
      "initialize",
      "{\"protocolVersion\":1}",
    ),
  )
  match duplicate {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
      assert_eq(step.state, initialized.state)
    }
    Invoke(..) => fail("duplicate initialize must not invoke")
  }
}

///|
async test "matrix C02 authenticate admits only advertised method ids" {
  let endpoint = agent_adapter_test_auth_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let unknown = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(2),
      "authenticate",
      "{\"methodId\":\"certificate\"}",
    ),
  )
  match unknown {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), AuthRequired)
      assert_eq(step.state, initialized.state)
      assert_true(step.state.reservation() is Idle)
    }
    Invoke(..) => fail("an unadvertised methodId must not start a handler")
  }
  let admission = agent_matrix_test_invoke_admission(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(3),
      "authenticate",
      "{\"methodId\":\"token\"}",
    ),
  )
  assert_true(admission.0.reservation() is AuthenticatePending(_))
  match admission.1 {
    AuthenticateInvocation(id=Number(3), params=_) => ()
    _ => fail("an advertised methodId must admit an authenticate invocation")
  }
}

///|
async test "matrix C04 session new validates cwd mcp and session id shape" {
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let context = agent_service_test_context()
  let relative_cwd = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"relative\",\"mcpServers\":[]}",
    ),
  )
  match relative_cwd {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidParams)
      assert_eq(step.state, initialized.state)
    }
    Invoke(..) => fail("a relative cwd must not invoke a handler")
  }
  let relative_command = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(3),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"local\",\"command\":\"bin/tool\",\"args\":[],\"env\":[]}]}",
    ),
  )
  match relative_command {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidParams)
    Invoke(..) => fail("a relative stdio command must not invoke a handler")
  }
  let modes_endpoint = agent_matrix_test_endpoint(
    new_session=agent_matrix_test_new_with_modes,
  )
  let modes_initialized = agent_adapter_test_initialized(
    modes_endpoint,
    Number(4),
  )
  let created = agent_adapter_test_invoke(
    modes_initialized.state,
    modes_endpoint,
    context,
    agent_adapter_test_request(
      Number(5),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  let decoded = new_session_result_from_json(
    agent_adapter_test_success(created, Number(5)),
  )
  assert_eq(decoded.session_id, "matrix-1")
  match decoded.modes {
    Value(modes) => {
      assert_eq(modes.current_mode_id, "code")
      assert_eq(modes.available_modes.length(), 2)
    }
    _ => fail("session/new must echo the service mode state")
  }
  // Session id uniqueness is service-owned; the SDK boundary only rejects the
  // degenerate empty id that could never address a session.
  let degenerate_endpoint = agent_matrix_test_endpoint(
    new_session=agent_matrix_test_empty_id_new,
  )
  let degenerate_initialized = agent_adapter_test_initialized(
    degenerate_endpoint,
    Number(6),
  )
  let degenerate = agent_adapter_test_invoke(
    degenerate_initialized.state,
    degenerate_endpoint,
    context,
    agent_adapter_test_request(
      Number(7),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(degenerate), InternalError)
}

///|
async test "matrix C05 session load is gated typed and never aliases resume" {
  let minimal = agent_matrix_test_minimal_endpoint()
  let minimal_initialized = agent_adapter_test_initialized(minimal, Number(1))
  let ungated = agent_adapter_admit(
    minimal_initialized.state,
    minimal,
    agent_adapter_test_request(
      Number(2),
      "session/load",
      "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
    ),
  )
  match ungated {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, minimal_initialized.state)
    }
    Invoke(..) => fail("session/load without loadSession must not invoke")
  }
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(3))
  let context = agent_service_test_context()
  let loaded = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(4),
      "session/load",
      "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
    ),
  )
  let decoded = load_session_result_from_json(
    agent_adapter_test_success(loaded, Number(4)),
  )
  assert_eq(decoded.modes, Omitted)
  assert_eq(decoded.config_options, Omitted)
  // Unknown persisted sessions are service-owned; their typed rejection
  // surfaces as resource-not-found with no protocol state side effects.
  let unknown_endpoint = agent_matrix_test_endpoint(
    load=agent_matrix_test_load_unknown_session,
  )
  let unknown_initialized = agent_adapter_test_initialized(
    unknown_endpoint,
    Number(5),
  )
  let unknown = agent_adapter_test_invoke(
    unknown_initialized.state,
    unknown_endpoint,
    context,
    agent_adapter_test_request(
      Number(6),
      "session/load",
      "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"missing\"}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(unknown), ResourceNotFound)
  assert_eq(unknown.state, unknown_initialized.state)
  // Replay (load) and no-replay (resume) results are distinct wire types;
  // crossing their completions fails fast instead of silently aliasing.
  let admission = agent_matrix_test_invoke_admission(
    unknown_initialized.state,
    unknown_endpoint,
    agent_adapter_test_request(
      Number(7),
      "session/load",
      "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"missing\"}",
    ),
  )
  try
    agent_adapter_complete(
      admission.0,
      admission.1,
      SessionResumeCompleted(
        id=Number(7),
        result=Ok({ modes: Omitted, config_options: Omitted, meta: Omitted }),
      ),
    )
  catch {
    CompletionMismatch(method_name="session/load") => ()
    _ => fail("expected a load/resume completion mismatch")
  } noraise {
    _ => fail("expected a load/resume completion mismatch")
  }
}

///|
async test "matrix C06 session resume is gated and completes without replay" {
  let minimal = agent_matrix_test_minimal_endpoint()
  let minimal_initialized = agent_adapter_test_initialized(minimal, Number(1))
  let ungated = agent_adapter_admit(
    minimal_initialized.state,
    minimal,
    agent_adapter_test_request(
      Number(2),
      "session/resume",
      "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    ),
  )
  match ungated {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, minimal_initialized.state)
    }
    Invoke(..) => fail("session/resume without session.resume must not invoke")
  }
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(3))
  let context = agent_service_test_context()
  let resumed = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(4),
      "session/resume",
      "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    ),
  )
  // The no-replay result carries mode/config state only; history replay is a
  // load-only contract and no field of this result can carry it.
  let decoded = resume_session_result_from_json(
    agent_adapter_test_success(resumed, Number(4)),
  )
  assert_eq(decoded.modes, Omitted)
  assert_eq(decoded.config_options, Omitted)
  let admission = agent_matrix_test_invoke_admission(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      String("resume-cross"),
      "session/resume",
      "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    ),
  )
  try
    agent_adapter_complete(
      admission.0,
      admission.1,
      SessionLoadCompleted(
        id=String("resume-cross"),
        result=Ok({ modes: Omitted, config_options: Omitted, meta: Omitted }),
      ),
    )
  catch {
    CompletionMismatch(method_name="session/resume") => ()
    _ => fail("expected a resume/load completion mismatch")
  } noraise {
    _ => fail("expected a resume/load completion mismatch")
  }
}

///|
async test "matrix C07 session list filters pass through and paging is exact" {
  let minimal = agent_matrix_test_minimal_endpoint()
  let minimal_initialized = agent_adapter_test_initialized(minimal, Number(1))
  let ungated = agent_adapter_admit(
    minimal_initialized.state,
    minimal,
    agent_adapter_test_request(Number(2), "session/list", "{}"),
  )
  match ungated {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, minimal_initialized.state)
    }
    Invoke(..) => fail("session/list without session.list must not invoke")
  }
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(3))
  let admission = agent_matrix_test_invoke_admission(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(4),
      "session/list",
      "{\"cwd\":\"/workspace\",\"cursor\":\"cursor-1\"}",
    ),
  )
  match admission.1 {
    SessionListInvocation(id=Number(4), params=list_params) => {
      assert_eq(list_params.cwd, Value("/workspace"))
      assert_eq(list_params.cursor, Value("cursor-1"))
    }
    _ => fail("list filters must reach the handler as typed params")
  }
  let listed = agent_adapter_complete(
    admission.0,
    admission.1,
    agent_adapter_execute(admission.1, endpoint, agent_service_test_context()),
  )
  let decoded = list_sessions_result_from_json(
    agent_adapter_test_success(listed, Number(4)),
  )
  assert_eq(decoded.sessions.length(), 1)
  assert_eq(decoded.sessions[0].session_id, "s-1")
  assert_eq(decoded.next_cursor, Value("next-1"))
}

///|
async test "matrix C08 session delete unknown id is typed resource not found" {
  let minimal = agent_matrix_test_minimal_endpoint()
  let minimal_initialized = agent_adapter_test_initialized(minimal, Number(1))
  let ungated = agent_adapter_admit(
    minimal_initialized.state,
    minimal,
    agent_adapter_test_request(
      Number(2),
      "session/delete",
      "{\"sessionId\":\"s\"}",
    ),
  )
  match ungated {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, minimal_initialized.state)
    }
    Invoke(..) => fail("session/delete without session.delete must not invoke")
  }
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(3))
  let context = agent_service_test_context()
  let deleted = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(4),
      "session/delete",
      "{\"sessionId\":\"s\"}",
    ),
  )
  let decoded = delete_session_result_from_json(
    agent_adapter_test_success(deleted, Number(4)),
  )
  assert_eq(decoded.meta, Omitted)
  // Unknown persisted ids are service-owned; their typed rejection surfaces
  // as resource-not-found with no protocol state side effects.
  let unknown_endpoint = agent_matrix_test_endpoint(
    delete=agent_matrix_test_delete_unknown_session,
  )
  let unknown_initialized = agent_adapter_test_initialized(
    unknown_endpoint,
    Number(5),
  )
  let unknown = agent_adapter_test_invoke(
    unknown_initialized.state,
    unknown_endpoint,
    context,
    agent_adapter_test_request(
      Number(6),
      "session/delete",
      "{\"sessionId\":\"missing\"}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(unknown), ResourceNotFound)
  assert_eq(unknown.state, unknown_initialized.state)
}

///|
async test "matrix C09 session close is gated and completes typed" {
  let minimal = agent_matrix_test_minimal_endpoint()
  let minimal_initialized = agent_adapter_test_initialized(minimal, Number(1))
  let ungated = agent_adapter_admit(
    minimal_initialized.state,
    minimal,
    agent_adapter_test_request(
      Number(2),
      "session/close",
      "{\"sessionId\":\"s\"}",
    ),
  )
  match ungated {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, minimal_initialized.state)
    }
    Invoke(..) => fail("session/close without session.close must not invoke")
  }
  // Boundary: cancelling the active turn during close and invalidating the
  // closed session id are service-owned runtime state.  The SDK provides the
  // capability gate, the typed request/response, and a completion that can
  // never be crossed with another session method.
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(3))
  let closed = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(4),
      "session/close",
      "{\"sessionId\":\"s\"}",
    ),
  )
  let decoded = close_session_result_from_json(
    agent_adapter_test_success(closed, Number(4)),
  )
  assert_eq(decoded.meta, Omitted)
}

///|
async test "matrix C10 set mode stays typed and mode states stay consistent" {
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let malformed = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(
      Number(2),
      "session/set_mode",
      "{\"sessionId\":\"s\"}",
    ),
  )
  match malformed {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidParams)
      assert_eq(step.state, initialized.state)
    }
    Invoke(..) => fail("set_mode without modeId must not invoke a handler")
  }
  let set = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(3),
      "session/set_mode",
      "{\"sessionId\":\"s\",\"modeId\":\"code\"}",
    ),
  )
  let decoded = set_session_mode_result_from_json(
    agent_adapter_test_success(set, Number(3)),
  )
  assert_eq(decoded.meta, Omitted)
  // Boundary: modeId membership is validated against the session's advertised
  // availableModes by the service, while the mode-state codec independently
  // rejects any state whose currentModeId is not available, so an unknown
  // modeId can never become a silent default (protocol/session tests).
}

///|
async test "matrix C11 set config option returns the complete option set" {
  let endpoint = agent_matrix_test_endpoint()
  // The shared initialized fixture negotiates session.configOptions.boolean.
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let configured = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(2),
      "session/set_config_option",
      "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
    ),
  )
  let decoded = set_session_config_option_result_from_json(
    agent_adapter_test_success(configured, Number(2)),
  )
  assert_eq(decoded.config_options.length(), 2)
  assert_true(
    decoded.config_options[0].kind is Boolean({ current_value: true }),
  )
  // Boundary: configId membership in the advertised set is service-owned;
  // the SDK never applies values itself, and boolean values additionally
  // require the negotiated client capability.
  let bare = match
    agent_adapter_admit(
      agent_adapter_test_state(endpoint),
      endpoint,
      agent_adapter_test_request(
        Number(3),
        "initialize",
        "{\"protocolVersion\":1}",
      ),
    ) {
    Immediate(step) => step
    Invoke(..) => fail("initialize must complete synchronously")
  }
  let denied = agent_adapter_admit(
    bare.state,
    endpoint,
    agent_adapter_test_request(
      Number(4),
      "session/set_config_option",
      "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
    ),
  )
  match denied {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, bare.state)
    }
    Invoke(..) =>
      fail(
        "a boolean config value without the client capability must not invoke",
      )
  }
}

///|
async test "matrix C12 prompt final response always carries stop reason" {
  let endpoint = agent_matrix_test_endpoint()
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let prompted = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(2),
      "session/prompt",
      "{\"sessionId\":\"s\",\"prompt\":[]}",
    ),
  )
  let decoded = prompt_result_from_json(
    agent_adapter_test_success(prompted, Number(2)),
  )
  assert_eq(decoded.stop_reason, EndTurn)
  // Decode-side strictness for missing/unknown stopReason is proven in
  // protocol/session/prompt_test.mbt; the typed PromptResult struct makes an
  // encode without a stop reason unrepresentable.
}

///|
async test "matrix C13 turn cancellation settles cancelled without side effects" {
  let endpoint = agent_matrix_test_endpoint(
    prompt=agent_matrix_test_cancelled_prompt,
  )
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let context = agent_service_test_context()
  // A cancel with no waiting turn completes silently and keeps state intact;
  // the service decides whether a turn exists for the session id.
  let cancel_admission = agent_matrix_test_invoke_admission(
    initialized.state,
    endpoint,
    agent_adapter_test_notification("session/cancel", "{\"sessionId\":\"s\"}"),
  )
  match cancel_admission.1 {
    SessionCancelInvocation(params=cancel_params) =>
      assert_eq(cancel_params.session_id, "s")
    _ => fail("session/cancel must admit a typed cancel invocation")
  }
  let cancelled = agent_adapter_complete(
    cancel_admission.0,
    cancel_admission.1,
    agent_adapter_execute(cancel_admission.1, endpoint, context),
  )
  assert_eq(cancelled.state, initialized.state)
  assert_eq(cancelled.outputs.length(), 0)
  // The next prompt on the same session still dispatches normally: an idle
  // cancel can never cancel a future turn.
  let prompted = agent_adapter_test_invoke(
    cancelled.state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(2),
      "session/prompt",
      "{\"sessionId\":\"s\",\"prompt\":[]}",
    ),
  )
  // After a turn cancellation the final prompt response is a success result
  // carrying stopReason "cancelled", never a JSON-RPC error.
  let decoded = prompt_result_from_json(
    agent_adapter_test_success(prompted, Number(2)),
  )
  assert_eq(decoded.stop_reason, Cancelled)
  // A completion that no longer belongs to the cancel notification fails fast
  // instead of settling a wrong reservation.
  let late_admission = agent_matrix_test_invoke_admission(
    cancelled.state,
    endpoint,
    agent_adapter_test_notification("session/cancel", "{\"sessionId\":\"s\"}"),
  )
  try
    agent_adapter_complete(
      late_admission.0,
      late_admission.1,
      SessionPromptCompleted(
        id=Number(99),
        result=Ok({ stop_reason: Cancelled, meta: Omitted }),
      ),
    )
  catch {
    CompletionMismatch(method_name="session/cancel") => ()
    _ => fail("expected a cancel completion mismatch")
  } noraise {
    _ => fail("expected a cancel completion mismatch")
  }
}
