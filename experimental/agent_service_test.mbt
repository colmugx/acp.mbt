///|
fn experimental_v2_agent_test_info(
  name : String,
) -> ExperimentalV2Implementation {
  { name, title: None, version: "test", meta: None, }
}

///|
fn experimental_v2_agent_test_capabilities(
  delete? : Bool = false,
  fork? : Bool = false,
) -> ExperimentalV2AgentCapabilities {
  {
    session: MarkerSupported({
      prompt: MarkerUnsupported,
      mcp: MarkerUnsupported,
      delete: if delete {
        MarkerSupported({ meta: None, })
      } else {
        MarkerUnsupported
      },
      additional_directories: MarkerUnsupported,
      fork: if fork {
        MarkerSupported({ meta: None, })
      } else {
        MarkerUnsupported
      },
      meta: None,
    }),
    auth: MarkerUnsupported,
    meta: None,
  }
}

///|
fn experimental_v2_agent_test_token_method() -> ExperimentalV2AuthMethod {
  Known({ method_id: "token", name: "Token", description: None, meta: None, })
}

///|
async fn experimental_v2_agent_test_new(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2NewSessionParams,
) -> ExperimentalV2NewSessionResult {
  @async.pause()
  { session_id: "created", config_options: None, meta: None, }
}

///|
async fn experimental_v2_agent_test_list(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2ListSessionsParams,
) -> ExperimentalV2ListSessionsResult {
  @async.pause()
  { sessions: [], next_cursor: None, meta: None, }
}

///|
async fn experimental_v2_agent_test_resume(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2ResumeSessionParams,
) -> ExperimentalV2ResumeSessionResult {
  @async.pause()
  { config_options: None, meta: None, }
}

///|
async fn experimental_v2_agent_test_close(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2CloseSessionParams,
) -> ExperimentalV2CloseSessionResult {
  @async.pause()
  { meta: None, }
}

///|
async fn experimental_v2_agent_test_prompt(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2PromptParams,
) -> ExperimentalV2PromptResult {
  @async.pause()
  { meta: None, }
}

///|
async fn experimental_v2_agent_test_set_config(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2SetConfigOptionParams,
) -> ExperimentalV2SetConfigOptionResult {
  @async.pause()
  { config_options: [], meta: None, }
}

///|
async fn experimental_v2_agent_test_delete(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2DeleteSessionParams,
) -> ExperimentalV2DeleteSessionResult {
  @async.pause()
  { meta: None, }
}

///|
async fn experimental_v2_agent_test_fork(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2ForkSessionParams,
) -> ExperimentalV2ForkSessionResult {
  @async.pause()
  { session_id: "forked", config_options: None, meta: None, }
}

///|
async fn experimental_v2_agent_test_login(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2LoginParams,
) -> ExperimentalV2LoginResult {
  @async.pause()
  { meta: None, }
}

///|
async fn experimental_v2_agent_test_logout(
  _context : ExperimentalV2AgentContext,
  _params : ExperimentalV2LogoutParams,
) -> ExperimentalV2LogoutResult {
  @async.pause()
  { meta: None, }
}

///|
fn experimental_v2_agent_test_sessions(
  with_delete : Bool,
  prompt? : ExperimentalV2AgentPromptHandler = experimental_v2_agent_test_prompt,
  new_session? : ExperimentalV2AgentNewSessionHandler = experimental_v2_agent_test_new,
  fork_session? : ExperimentalV2AgentForkSessionHandler? = None,
) -> ExperimentalV2AgentSessionService {
  experimental_v2_agent_session_service(
    new_session~,
    list=experimental_v2_agent_test_list,
    resume_session=experimental_v2_agent_test_resume,
    close=experimental_v2_agent_test_close,
    prompt~,
    set_config_option=experimental_v2_agent_test_set_config,
    delete=if with_delete {
      Some(experimental_v2_agent_test_delete)
    } else {
      None
    },
    fork_session~,
  )
}

///|
fn experimental_v2_agent_test_spec(
  with_delete? : Bool = false,
  with_auth? : Bool = false,
  prompt? : ExperimentalV2AgentPromptHandler = experimental_v2_agent_test_prompt,
  new_session? : ExperimentalV2AgentNewSessionHandler = experimental_v2_agent_test_new,
  with_fork? : Bool = false,
) -> ExperimentalV2AgentSpec {
  try! experimental_v2_agent_spec(
    info=experimental_v2_agent_test_info("agent"),
    capabilities=experimental_v2_agent_test_capabilities(
      delete=with_delete,
      fork=with_fork,
    ),
    sessions=experimental_v2_agent_test_sessions(
      with_delete,
      prompt~,
      new_session~,
      fork_session=if with_fork {
        Some(experimental_v2_agent_test_fork)
      } else {
        None
      },
    ),
    auth_methods=if with_auth {
      Some([experimental_v2_agent_test_token_method()])
    } else {
      None
    },
    auth=if with_auth {
      Some(
        experimental_v2_agent_auth_service(
          login=experimental_v2_agent_test_login,
          logout=experimental_v2_agent_test_logout,
        ),
      )
    } else {
      None
    },
  )
}

///|
fn experimental_v2_agent_test_endpoint(
  with_delete? : Bool = false,
  with_auth? : Bool = false,
  prompt? : ExperimentalV2AgentPromptHandler = experimental_v2_agent_test_prompt,
  new_session? : ExperimentalV2AgentNewSessionHandler = experimental_v2_agent_test_new,
  with_fork? : Bool = false,
) -> ExperimentalV2AgentEndpoint {
  experimental_v2_agent_endpoint_from_spec(
    experimental_v2_agent_test_spec(
      with_delete~,
      with_auth~,
      prompt~,
      new_session~,
      with_fork~,
    ),
  )
}

///|
fn experimental_v2_agent_test_adapter_state(
  endpoint : ExperimentalV2AgentEndpoint,
) -> ExperimentalV2AgentAdapterState {
  experimental_v2_agent_adapter_state_new(
    protocol=try! experimental_v2_agent_state_new(config=endpoint.config()),
  )
}

///|
test "v2 agent spec rejects an empty implementation identity" {
  try
    experimental_v2_agent_spec(
      info={ name: "", title: None, version: "1", meta: None, },
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
    )
  catch {
    InvalidImplementation(reason~) =>
      inspect(reason, content="agent name must not be empty")
    _ => fail("expected InvalidImplementation")
  } noraise {
    _ => fail("expected InvalidImplementation")
  }
  try
    experimental_v2_agent_spec(
      info={ name: "agent", title: None, version: "", meta: None, },
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
    )
  catch {
    InvalidImplementation(reason~) =>
      inspect(reason, content="agent version must not be empty")
    _ => fail("expected InvalidImplementation")
  } noraise {
    _ => fail("expected InvalidImplementation")
  }
}

///|
test "v2 agent spec requires the session capability marker" {
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities={
        session: MarkerUnsupported,
        auth: MarkerUnsupported,
        meta: None,
      },
      sessions=experimental_v2_agent_test_sessions(false),
    )
  catch {
    SessionMarkerMissing => ()
    _ => fail("expected SessionMarkerMissing")
  } noraise {
    _ => fail("expected SessionMarkerMissing")
  }
}

///|
test "v2 agent spec rejects an ambiguous or duplicated auth method list" {
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
      auth_methods=Some([]),
      auth=Some(
        experimental_v2_agent_auth_service(
          login=experimental_v2_agent_test_login,
          logout=experimental_v2_agent_test_logout,
        ),
      ),
    )
  catch {
    EmptyAuthMethods => ()
    _ => fail("expected EmptyAuthMethods")
  } noraise {
    _ => fail("expected EmptyAuthMethods")
  }
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
      auth_methods=Some([
        experimental_v2_agent_test_token_method(),
        experimental_v2_agent_test_token_method(),
      ]),
      auth=Some(
        experimental_v2_agent_auth_service(
          login=experimental_v2_agent_test_login,
          logout=experimental_v2_agent_test_logout,
        ),
      ),
    )
  catch {
    DuplicateAuthMethodId(method_id~) => inspect(method_id, content="token")
    _ => fail("expected DuplicateAuthMethodId")
  } noraise {
    _ => fail("expected DuplicateAuthMethodId")
  }
}

///|
test "v2 agent spec couples authMethods and the auth service both directions" {
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
      auth_methods=Some([experimental_v2_agent_test_token_method()]),
    )
  catch {
    AuthServiceMismatch(reason~) =>
      inspect(reason, content="advertised authMethods require the auth service")
    _ => fail("expected AuthServiceMismatch")
  } noraise {
    _ => fail("expected AuthServiceMismatch")
  }
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(false),
      auth=Some(
        experimental_v2_agent_auth_service(
          login=experimental_v2_agent_test_login,
          logout=experimental_v2_agent_test_logout,
        ),
      ),
    )
  catch {
    AuthServiceMismatch(reason~) =>
      inspect(
        reason,
        content="the auth service requires advertised authMethods",
      )
    _ => fail("expected AuthServiceMismatch")
  } noraise {
    _ => fail("expected AuthServiceMismatch")
  }
}

///|
test "v2 agent spec couples the session.delete marker and delete service" {
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(delete=true),
      sessions=experimental_v2_agent_test_sessions(false),
    )
  catch {
    DeleteServiceMismatch(reason~) =>
      inspect(
        reason,
        content="the session.delete marker requires the delete service",
      )
    _ => fail("expected DeleteServiceMismatch")
  } noraise {
    _ => fail("expected DeleteServiceMismatch")
  }
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(true),
    )
  catch {
    DeleteServiceMismatch(reason~) =>
      inspect(
        reason,
        content="the delete service requires the session.delete marker",
      )
    _ => fail("expected DeleteServiceMismatch")
  } noraise {
    _ => fail("expected DeleteServiceMismatch")
  }
}

///|
/// Upstream unstable (RFD session-fork, Draft): the fork marker and fork
/// service couple both directions exactly like delete.
test "v2 agent spec couples the session.fork marker and fork service" {
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(fork=true),
      sessions=experimental_v2_agent_test_sessions(false),
    )
  catch {
    ForkServiceMismatch(reason~) =>
      inspect(
        reason,
        content="the session.fork marker requires the fork service",
      )
    _ => fail("expected ForkServiceMismatch")
  } noraise {
    _ => fail("expected ForkServiceMismatch")
  }
  try
    experimental_v2_agent_spec(
      info=experimental_v2_agent_test_info("agent"),
      capabilities=experimental_v2_agent_test_capabilities(),
      sessions=experimental_v2_agent_test_sessions(
        false,
        fork_session=Some(experimental_v2_agent_test_fork),
      ),
    )
  catch {
    ForkServiceMismatch(reason~) =>
      inspect(
        reason,
        content="the fork service requires the session.fork marker",
      )
    _ => fail("expected ForkServiceMismatch")
  } noraise {
    _ => fail("expected ForkServiceMismatch")
  }
}

///|
async test "v2 agent endpoint derives the fork marker and dispatches typed" {
  let endpoint = experimental_v2_agent_test_endpoint(with_fork=true)
  match endpoint.capabilities().session {
    MarkerSupported(session) => assert_true(session.fork is MarkerSupported(_))
    MarkerUnsupported => fail("session marker must stay supported")
  }
  let forked = endpoint.fork_session(
    experimental_v2_agent_fail_fast_context(),
    {
      session_id: "created",
      cwd: "/",
      additional_directories: None,
      mcp_servers: None,
      meta: None,
    },
  )
  assert_eq(forked.session_id, "forked")
  // Without the fork service the marker is derived away and the endpoint
  // answers typed instead of guessing.
  match experimental_v2_agent_test_endpoint().capabilities().session {
    MarkerSupported(session) =>
      assert_true(session.fork is MarkerUnsupported(_))
    MarkerUnsupported => fail("session marker must stay supported")
  }
  try
    experimental_v2_agent_test_endpoint().fork_session(
      experimental_v2_agent_fail_fast_context(),
      {
        session_id: "created",
        cwd: "/",
        additional_directories: None,
        mcp_servers: None,
        meta: None,
      },
    )
  catch {
    UnavailableOperation(method_name~) =>
      inspect(method_name, content="session/fork")
    _ => fail("expected UnavailableOperation")
  } noraise {
    _ => fail("expected UnavailableOperation")
  }
}

///|
test "v2 agent endpoint derives capabilities and authMethods from services" {
  let endpoint = experimental_v2_agent_test_endpoint()
  match endpoint.capabilities().session {
    MarkerSupported(session) =>
      assert_true(session.delete is MarkerUnsupported(_))
    MarkerUnsupported => fail("session marker must stay supported")
  }
  assert_true(endpoint.auth_methods() is None)
  let deleting = experimental_v2_agent_test_endpoint(with_delete=true)
  match deleting.capabilities().session {
    MarkerSupported(session) =>
      assert_true(session.delete is MarkerSupported(_))
    MarkerUnsupported => fail("session marker must stay supported")
  }
  let authenticated = experimental_v2_agent_test_endpoint(with_auth=true)
  guard authenticated.auth_methods() is Some(methods) else {
    fail("auth endpoint must advertise methods")
  }
  assert_eq(methods.length(), 1)
  match methods[0] {
    Known(agent) => assert_eq(agent.method_id, "token")
    _ => fail("expected a known auth method")
  }
  // The derived advertisement is exactly what the reducer state constructor
  // accepts, so endpoint config and endpoint state cannot drift.
  let state = try! experimental_v2_agent_state_new(
    config=authenticated.config(),
  )
  assert_true(state.authentication is AuthNotAdvertised)
}

///|
async test "v2 agent endpoint dispatches required handlers typed" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let context = experimental_v2_agent_fail_fast_context()
  let created = endpoint.new_session(context, {
    cwd: "/",
    additional_directories: None,
    mcp_servers: None,
    meta: None,
  })
  assert_eq(created.session_id, "created")
  let listed = endpoint.list_sessions(context, {
    cwd: None,
    cursor: None,
    meta: None,
  })
  assert_eq(listed.sessions.length(), 0)
  let resumed = endpoint.resume_session(context, {
    session_id: "created",
    cwd: "/",
    additional_directories: None,
    mcp_servers: None,
    replay_from: None,
    meta: None,
  })
  assert_true(resumed.config_options is None)
  let closed = endpoint.close_session(context, {
    session_id: "created",
    meta: None,
  })
  assert_true(closed.meta is None)
  let prompted = endpoint.prompt(context, {
    session_id: "created",
    prompt: [],
    meta: None,
  })
  assert_true(prompted.meta is None)
  let configured = endpoint.set_config_option(
    context,
    Known({
      session_id: "created",
      config_id: "model",
      value: ConfigValueId("mini"),
      meta: None,
    }),
  )
  assert_eq(configured.config_options.length(), 0)
}

///|
async test "v2 agent endpoint answers an absent optional service typed" {
  let endpoint = experimental_v2_agent_test_endpoint()
  try
    endpoint.delete_session(experimental_v2_agent_fail_fast_context(), {
      session_id: "created",
      meta: None,
    })
  catch {
    UnavailableOperation(method_name~) =>
      inspect(method_name, content="session/delete")
    _ => fail("expected UnavailableOperation")
  } noraise {
    _ => fail("expected UnavailableOperation")
  }
}

///|
async test "v2 agent handler normalization prefixes and names defects" {
  let context = experimental_v2_agent_fail_fast_context()
  let failing : ExperimentalV2AgentPromptHandler = async fn(_context, _params) {
    @async.pause()
    raise ExperimentalV2AgentHandlerError::Application(message="boom")
  }
  try
    experimental_v2_agent_test_endpoint(prompt=failing).prompt(context, {
      session_id: "created",
      prompt: [],
      meta: None,
    })
  catch {
    Application(message~) => inspect(message, content="session/prompt: boom")
    _ => fail("expected Application")
  } noraise {
    _ => fail("expected Application")
  }
  let defect : ExperimentalV2AgentPromptHandler = async fn(_context, _params) {
    @async.pause()
    raise ExperimentalV2DecodeError::MissingField(path="prompt")
  }
  try
    experimental_v2_agent_test_endpoint(prompt=defect).prompt(context, {
      session_id: "created",
      prompt: [],
      meta: None,
    })
  catch {
    Application(message~) =>
      assert_true(message.has_prefix("session/prompt: agent handler failed: "))
    _ => fail("expected Application")
  } noraise {
    _ => fail("expected Application")
  }
}

///|
test "v2 prompt result codec round-trips" {
  let value : ExperimentalV2PromptResult = { meta: None, }
  let encoded = try! experimental_v2_encode_prompt_result(value)
  inspect(encoded.stringify(), content="{}")
  let decoded = try! experimental_v2_decode_prompt_result(
    encoded,
    path="session/prompt",
  )
  assert_eq(decoded, value)
}
