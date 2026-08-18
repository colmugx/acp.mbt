///|
fn agent_state_test_info(name : String) -> ExperimentalV2Implementation {
  { name, title: None, version: "1.0.0", meta: None }
}

///|
fn agent_state_test_marker() -> ExperimentalV2MarkerPayload {
  { meta: None }
}

///|
fn agent_state_test_config(
  capabilities : ExperimentalV2AgentCapabilities,
  auth_methods : Array[ExperimentalV2AuthMethod]?,
) -> ExperimentalV2AgentEndpointConfig {
  { info: agent_state_test_info("agent"), capabilities, auth_methods }
}

///|
fn agent_state_test_no_capabilities() -> ExperimentalV2AgentCapabilities {
  { session: MarkerUnsupported, auth: MarkerUnsupported, meta: None }
}

///|
fn agent_state_test_session_capabilities(
  prompt : ExperimentalV2Marker[ExperimentalV2PromptCapabilities],
  mcp : ExperimentalV2Marker[ExperimentalV2McpCapabilities],
  delete : ExperimentalV2Marker[ExperimentalV2MarkerPayload],
  additional_directories : ExperimentalV2Marker[ExperimentalV2MarkerPayload],
) -> ExperimentalV2AgentCapabilities {
  {
    session: MarkerSupported({
      prompt,
      mcp,
      delete,
      additional_directories,
      meta: None,
    }),
    auth: MarkerUnsupported,
    meta: None,
  }
}

///|
fn agent_state_test_all_capabilities() -> ExperimentalV2AgentCapabilities {
  agent_state_test_session_capabilities(
    MarkerSupported({
      image: MarkerSupported(agent_state_test_marker()),
      audio: MarkerSupported(agent_state_test_marker()),
      embedded_context: MarkerSupported(agent_state_test_marker()),
      meta: None,
    }),
    MarkerSupported({
      stdio: MarkerSupported(agent_state_test_marker()),
      http: MarkerSupported(agent_state_test_marker()),
      meta: None,
    }),
    MarkerSupported(agent_state_test_marker()),
    MarkerSupported(agent_state_test_marker()),
  )
}

///|
fn agent_state_test_gate_capabilities(
  image : Bool,
  audio : Bool,
  embedded_context : Bool,
  delete : Bool,
  additional_directories : Bool,
  mcp_stdio : Bool,
  mcp_http : Bool,
) -> ExperimentalV2AgentCapabilities {
  fn marker(
    supported : Bool,
  ) -> ExperimentalV2Marker[ExperimentalV2MarkerPayload] {
    if supported {
      MarkerSupported(agent_state_test_marker())
    } else {
      MarkerUnsupported
    }
  }
  agent_state_test_session_capabilities(
    MarkerSupported({
      image: marker(image),
      audio: marker(audio),
      embedded_context: marker(embedded_context),
      meta: None,
    }),
    MarkerSupported({
      stdio: marker(mcp_stdio),
      http: marker(mcp_http),
      meta: None,
    }),
    marker(delete),
    marker(additional_directories),
  )
}

///|
fn agent_state_test_state(
  capabilities : ExperimentalV2AgentCapabilities,
  auth_methods : Array[ExperimentalV2AuthMethod]?,
) -> ExperimentalV2AgentState raise ExperimentalV2AgentStateError {
  experimental_v2_agent_state_new(
    config=agent_state_test_config(capabilities, auth_methods),
  )
}

///|
fn agent_state_test_initialize(
  state : ExperimentalV2AgentState,
  protocol_version : Int,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  let params : ExperimentalV2InitializeParams = {
    protocol_version,
    info: agent_state_test_info("client"),
    capabilities: { elicitation: MarkerUnsupported, meta: None },
    meta: None,
  }
  experimental_v2_agent_reduce(state, ClientRequest(Initialize(params)))
}

///|
fn agent_state_test_initialized(
  capabilities : ExperimentalV2AgentCapabilities,
  auth_methods : Array[ExperimentalV2AuthMethod]?,
) -> ExperimentalV2AgentState raise {
  agent_state_test_initialize(
    agent_state_test_state(capabilities, auth_methods),
    2,
  ).state
}

///|
fn agent_state_test_auth_method(method_id : String) -> ExperimentalV2AuthMethod {
  Known({ method_id, name: "Token", description: None, meta: None })
}

///|
fn agent_state_test_login(
  method_id : String,
) -> ExperimentalV2AgentRequest raise {
  AuthLogin(
    experimental_v2_decode_login_params(
      experimental_v2_parse_json("{\"methodId\":\"\{method_id}\"}"),
    ),
  )
}

///|
fn agent_state_test_logout() -> ExperimentalV2AgentRequest raise {
  AuthLogout(
    experimental_v2_decode_logout_params(experimental_v2_parse_json("{}")),
  )
}

///|
fn agent_state_test_delete() -> ExperimentalV2AgentRequest raise {
  SessionDelete(
    experimental_v2_decode_delete_session_params(
      experimental_v2_parse_json("{\"sessionId\":\"s\"}"),
    ),
  )
}

///|
fn agent_state_test_cancel() -> ExperimentalV2AgentNotification raise {
  SessionCancel(
    experimental_v2_decode_cancel_session_params(
      experimental_v2_parse_json("{\"sessionId\":\"s\"}"),
    ),
  )
}

///|
fn agent_state_test_new_request(
  source : String,
) -> ExperimentalV2AgentRequest raise {
  SessionNew(
    experimental_v2_decode_new_session_params(
      experimental_v2_parse_json(source),
    ),
  )
}

///|
fn agent_state_test_resume_request(
  source : String,
) -> ExperimentalV2AgentRequest raise {
  SessionResume(
    experimental_v2_decode_resume_session_params(
      experimental_v2_parse_json(source),
    ),
  )
}

///|
fn agent_state_test_prompt_request(
  source : String,
) -> ExperimentalV2AgentRequest raise {
  SessionPrompt(
    experimental_v2_decode_prompt_params(experimental_v2_parse_json(source)),
  )
}

///|
/// Build one `session/new` or `session/resume` request with the given servers
/// JSON and optional additional directories; the two methods carry the same
/// gated payload fields but stay distinct requests.
fn agent_state_test_gated_request(
  method_name : String,
  servers : String,
  with_additional_directories : Bool,
) -> ExperimentalV2AgentRequest raise {
  let roots = if with_additional_directories {
    ",\"additionalDirectories\":[\"/tmp\"]"
  } else {
    ""
  }
  match method_name {
    "session/new" =>
      agent_state_test_new_request(
        "{\"cwd\":\"/\"" + roots + ",\"mcpServers\":" + servers + "}",
      )
    "session/resume" =>
      agent_state_test_resume_request(
        "{\"sessionId\":\"s\",\"cwd\":\"/\"" +
        roots +
        ",\"mcpServers\":" +
        servers +
        "}",
      )
    _ => abort("unknown gated session method fixture")
  }
}

///|
fn agent_state_test_dispatched(
  state : ExperimentalV2AgentState,
  request : ExperimentalV2AgentRequest,
) -> Unit raise {
  let step = experimental_v2_agent_reduce(state, ClientRequest(request))
  assert_eq(step.commands.length(), 1)
  match step.commands[0] {
    DispatchRequest(_) => ()
    _ => fail("expected the request to dispatch")
  }
}

///|
fn agent_state_test_denied(
  state : ExperimentalV2AgentState,
  request : ExperimentalV2AgentRequest,
  method_name : String,
  capability : String,
) -> Unit raise {
  let before = state
  try experimental_v2_agent_reduce(state, ClientRequest(request)) catch {
    CapabilityDenied(method_name=actual_method, capability=actual_capability) => {
      assert_eq(actual_method, method_name)
      assert_eq(actual_capability, capability)
    }
    _ => fail("expected " + method_name + " to deny " + capability)
  } noraise {
    _ => fail("expected " + method_name + " to deny " + capability)
  }
  assert_eq(state, before)
}

///|
fn agent_state_test_error(
  state : ExperimentalV2AgentState,
  event : ExperimentalV2AgentEvent,
  expected : ExperimentalV2AgentProtocolError,
) -> Unit raise {
  let before = state
  try experimental_v2_agent_reduce(state, event) catch {
    error => assert_eq(error, expected)
  } noraise {
    _ => fail("expected a typed rejection")
  }
  assert_eq(state, before)
}

///|
fn agent_state_test_mcp_servers(transport : String) -> String {
  match transport {
    "none" => "[]"
    "stdio" =>
      "[{\"type\":\"stdio\",\"name\":\"local\",\"command\":\"/bin/echo\",\"args\":[],\"env\":[]}]"
    "http" =>
      "[{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]"
    "sse" =>
      "[{\"type\":\"sse\",\"name\":\"events\",\"url\":\"https://example.test/events\",\"headers\":[]}]"
    "mixed" =>
      "[{\"type\":\"stdio\",\"name\":\"local\",\"command\":\"/bin/echo\",\"args\":[],\"env\":[]},{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]"
    _ => abort("unknown MCP transport fixture")
  }
}

///|
test "v2 agent negotiation accepts only version two and rejects repetition" {
  let initial = agent_state_test_state(agent_state_test_no_capabilities(), None)
  let preinitialize = agent_state_test_new_request(
    "{\"cwd\":\"/\",\"mcpServers\":[]}",
  )
  agent_state_test_error(
    initial,
    ClientRequest(preinitialize),
    NotInitialized(method_name="session/new"),
  )

  let accepted = agent_state_test_initialize(initial, 2)
  assert_eq(accepted.state.phase, AgentInitialized)
  assert_eq(accepted.state.authentication, AuthNotAdvertised)
  match accepted.commands[0] {
    SendInitialize(result~, accepted=true) =>
      assert_eq(result.protocol_version, 2)
    _ => fail("expected an accepted initialize command")
  }

  try agent_state_test_initialize(accepted.state, 2) catch {
    AlreadyInitialized => ()
    _ => fail("expected duplicate initialize rejection")
  } noraise {
    _ => fail("expected duplicate initialize rejection")
  }

  // A v1 offer is answered with the endpoint's own version 2, the state stays
  // awaiting, and a later v2 initialize still succeeds.
  let mismatch = agent_state_test_initialize(initial, 1)
  assert_eq(mismatch.state, initial)
  match mismatch.commands[0] {
    SendInitialize(result~, accepted=false) =>
      assert_eq(result.protocol_version, 2)
    _ => fail("expected a version-mismatch initialize reply")
  }
  let recovered = agent_state_test_initialize(mismatch.state, 2)
  assert_eq(recovered.state.phase, AgentInitialized)
}

///|
test "v2 agent advertisement construction fails fast on ambiguous auth sets" {
  try
    experimental_v2_agent_state_new(
      config=agent_state_test_config(
        agent_state_test_no_capabilities(),
        Some([]),
      ),
    )
  catch {
    EmptyAuthMethods => ()
    _ => fail("expected an empty authMethods advertisement to fail")
  } noraise {
    _ => fail("expected an empty authMethods advertisement to fail")
  }
  try
    experimental_v2_agent_state_new(
      config=agent_state_test_config(
        agent_state_test_no_capabilities(),
        Some([
          agent_state_test_auth_method("token"),
          agent_state_test_auth_method("token"),
        ]),
      ),
    )
  catch {
    DuplicateAuthMethodId(method_id="token") => ()
    _ => fail("expected a duplicate auth method id to fail")
  } noraise {
    _ => fail("expected a duplicate auth method id to fail")
  }
}

///|
test "v2 auth coupling gates login and logout on the advertised method set" {
  let unadvertised = agent_state_test_initialized(
    agent_state_test_no_capabilities(),
    None,
  )
  let login = agent_state_test_login("token")
  agent_state_test_error(
    unadvertised,
    ClientRequest(login),
    AuthNotAdvertised(method_name="auth/login"),
  )
  agent_state_test_error(
    unadvertised,
    ClientRequest(agent_state_test_logout()),
    AuthNotAdvertised(method_name="auth/logout"),
  )

  let advertised = agent_state_test_initialized(
    agent_state_test_no_capabilities(),
    Some([agent_state_test_auth_method("token")]),
  )
  assert_eq(advertised.authentication, AuthPending)
  agent_state_test_error(
    advertised,
    ClientRequest(agent_state_test_login("unknown")),
    AuthMethodNotAdvertised(method_id="unknown"),
  )
  let login_step = experimental_v2_agent_reduce(
    advertised,
    ClientRequest(login),
  )
  match login_step.commands[0] {
    Login(method_id="token") => ()
    _ => fail("expected a login command")
  }
  let authenticated = experimental_v2_agent_reduce(
    login_step.state,
    LoginSucceeded(method_id="token"),
  )
  assert_eq(authenticated.state.authentication, AuthLoggedIn)
  agent_state_test_error(
    authenticated.state,
    ClientRequest(login),
    AlreadyLoggedIn,
  )
  agent_state_test_error(
    authenticated.state,
    LoginSucceeded(method_id="token"),
    AlreadyLoggedIn,
  )

  let logout_step = experimental_v2_agent_reduce(
    authenticated.state,
    ClientRequest(agent_state_test_logout()),
  )
  assert_true(logout_step.commands[0] is Logout)
  let logged_out = experimental_v2_agent_reduce(logout_step.state, LoggedOut)
  assert_eq(logged_out.state.authentication, AuthPending)
  agent_state_test_error(
    logged_out.state,
    ClientRequest(agent_state_test_logout()),
    NotLoggedIn,
  )
}

///|
test "v2 baseline session methods need no capability markers" {
  let state = agent_state_test_initialized(
    agent_state_test_no_capabilities(),
    None,
  )
  agent_state_test_dispatched(
    state,
    agent_state_test_gated_request("session/new", "[]", false),
  )
  agent_state_test_dispatched(
    state,
    SessionList(
      experimental_v2_decode_list_sessions_params(
        experimental_v2_parse_json("{}"),
      ),
    ),
  )
  agent_state_test_dispatched(
    state,
    agent_state_test_gated_request("session/resume", "[]", false),
  )
  agent_state_test_dispatched(
    state,
    SessionClose(
      experimental_v2_decode_close_session_params(
        experimental_v2_parse_json("{\"sessionId\":\"s\"}"),
      ),
    ),
  )
  agent_state_test_dispatched(
    state,
    agent_state_test_prompt_request(
      "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"text\",\"text\":\"hi\"},{\"type\":\"resource_link\",\"name\":\"a\",\"uri\":\"file:///tmp/a\"}]}",
    ),
  )
  agent_state_test_dispatched(
    state,
    SessionSetConfigOption(
      experimental_v2_decode_set_config_option(
        experimental_v2_parse_json(
          "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
        ),
      ),
    ),
  )
}

///|
test "v2 session delete requires the session delete marker" {
  let denied = agent_state_test_initialized(
    agent_state_test_no_capabilities(),
    None,
  )
  let delete = agent_state_test_delete()
  agent_state_test_denied(denied, delete, "session/delete", "session.delete")

  let outer_only = agent_state_test_initialized(
    agent_state_test_session_capabilities(
      MarkerSupported({
        image: MarkerUnsupported,
        audio: MarkerUnsupported,
        embedded_context: MarkerUnsupported,
        meta: None,
      }),
      MarkerSupported({
        stdio: MarkerUnsupported,
        http: MarkerUnsupported,
        meta: None,
      }),
      MarkerUnsupported,
      MarkerUnsupported,
    ),
    None,
  )
  agent_state_test_denied(
    outer_only, delete, "session/delete", "session.delete",
  )

  let allowed = agent_state_test_initialized(
    agent_state_test_all_capabilities(),
    None,
  )
  agent_state_test_dispatched(allowed, delete)
}

///|
test "v2 prompt content gates match the prompt capability markers" {
  let denied = agent_state_test_initialized(
    agent_state_test_no_capabilities(),
    None,
  )
  let image = agent_state_test_prompt_request(
    "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"image\",\"data\":\"aA==\",\"mimeType\":\"image/png\"}]}",
  )
  let audio = agent_state_test_prompt_request(
    "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"audio\",\"data\":\"aA==\",\"mimeType\":\"audio/wav\"}]}",
  )
  let embedded = agent_state_test_prompt_request(
    "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"resource\",\"resource\":{\"uri\":\"file:///tmp/a\",\"text\":\"body\"}}]}",
  )
  agent_state_test_denied(denied, image, "session/prompt", "prompt.image")
  agent_state_test_denied(denied, audio, "session/prompt", "prompt.audio")
  agent_state_test_denied(
    denied, embedded, "session/prompt", "prompt.embeddedContext",
  )

  let partial = agent_state_test_initialized(
    agent_state_test_gate_capabilities(
      true, false, false, false, false, false, false,
    ),
    None,
  )
  agent_state_test_dispatched(partial, image)
  agent_state_test_denied(partial, audio, "session/prompt", "prompt.audio")
  agent_state_test_denied(
    partial, embedded, "session/prompt", "prompt.embeddedContext",
  )

  let allowed = agent_state_test_initialized(
    agent_state_test_all_capabilities(),
    None,
  )
  agent_state_test_dispatched(allowed, image)
  agent_state_test_dispatched(allowed, audio)
  agent_state_test_dispatched(allowed, embedded)
}

///|
test "v2 prompt extension and future block kinds have no opening marker" {
  let allowed = agent_state_test_initialized(
    agent_state_test_all_capabilities(),
    None,
  )
  let extension = agent_state_test_prompt_request(
    "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"_custom\",\"data\":\"aA==\"}]}",
  )
  agent_state_test_denied(
    allowed, extension, "session/prompt", "prompt._custom",
  )
  let future = agent_state_test_prompt_request(
    "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"video\",\"data\":\"aA==\"}]}",
  )
  agent_state_test_denied(allowed, future, "session/prompt", "prompt.video")
}

///|
test "v2 mcp transports gate independently for new and resume" {
  for method_name in ["session/new", "session/resume"] {
    let no_markers = agent_state_test_initialized(
      agent_state_test_no_capabilities(),
      None,
    )
    agent_state_test_dispatched(
      no_markers,
      agent_state_test_gated_request(method_name, "[]", false),
    )
    agent_state_test_denied(
      no_markers,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("stdio"),
        false,
      ),
      method_name,
      "session.mcp.stdio",
    )
    agent_state_test_denied(
      no_markers,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("http"),
        false,
      ),
      method_name,
      "session.mcp.http",
    )
    agent_state_test_denied(
      no_markers,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("sse"),
        false,
      ),
      method_name,
      "session.mcp.sse",
    )

    let stdio_only = agent_state_test_initialized(
      agent_state_test_gate_capabilities(
        false, false, false, false, false, true, false,
      ),
      None,
    )
    agent_state_test_dispatched(
      stdio_only,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("stdio"),
        false,
      ),
    )
    agent_state_test_denied(
      stdio_only,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("http"),
        false,
      ),
      method_name,
      "session.mcp.http",
    )
    agent_state_test_denied(
      stdio_only,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("mixed"),
        false,
      ),
      method_name,
      "session.mcp.http",
    )

    let all = agent_state_test_initialized(
      agent_state_test_all_capabilities(),
      None,
    )
    agent_state_test_dispatched(
      all,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("stdio"),
        false,
      ),
    )
    agent_state_test_dispatched(
      all,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("http"),
        false,
      ),
    )
    agent_state_test_dispatched(
      all,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("mixed"),
        false,
      ),
    )
    agent_state_test_denied(
      all,
      agent_state_test_gated_request(
        method_name,
        agent_state_test_mcp_servers("sse"),
        false,
      ),
      method_name,
      "session.mcp.sse",
    )
  }
}

///|
test "v2 additional directories require their marker and omission is allowed" {
  for method_name in ["session/new", "session/resume"] {
    let no_marker = agent_state_test_initialized(
      agent_state_test_no_capabilities(),
      None,
    )
    agent_state_test_dispatched(
      no_marker,
      agent_state_test_gated_request(method_name, "[]", false),
    )
    agent_state_test_denied(
      no_marker,
      agent_state_test_gated_request(method_name, "[]", true),
      method_name,
      "session.additionalDirectories",
    )
    let allowed = agent_state_test_initialized(
      agent_state_test_all_capabilities(),
      None,
    )
    agent_state_test_dispatched(
      allowed,
      agent_state_test_gated_request(method_name, "[]", false),
    )
    agent_state_test_dispatched(
      allowed,
      agent_state_test_gated_request(method_name, "[]", true),
    )
  }
}

///|
test "v2 unknown and v1-only method names are typed rejections" {
  let state = agent_state_test_initialized(
    agent_state_test_no_capabilities(),
    None,
  )
  agent_state_test_error(
    state,
    UnknownClientMethod(method_name="session/load"),
    UnknownMethod(method_name="session/load"),
  )
  agent_state_test_error(
    state,
    UnknownClientMethod(method_name="authenticate"),
    UnknownMethod(method_name="authenticate"),
  )
  agent_state_test_error(
    state,
    UnknownClientMethod(method_name="fs/read_text_file"),
    UnknownMethod(method_name="fs/read_text_file"),
  )
}

///|
test "v2 notifications require initialization and become cancellations" {
  let initial = agent_state_test_state(agent_state_test_no_capabilities(), None)
  let cancel = agent_state_test_cancel()
  agent_state_test_error(
    initial,
    ClientNotification(cancel),
    NotInitialized(method_name="session/cancel"),
  )

  let state = agent_state_test_initialize(initial, 2).state
  let session_step = experimental_v2_agent_reduce(
    state,
    ClientNotification(cancel),
  )
  assert_true(session_step.commands[0] is CancelSession(session_id="s"))
  let request_cancel : ExperimentalV2AgentNotification = CancelRequest(
    RequestIdNumber(7L),
  )
  let request_step = experimental_v2_agent_reduce(
    state,
    ClientNotification(request_cancel),
  )
  assert_true(
    request_step.commands[0] is CancelRequest(request_id=RequestIdNumber(7L)),
  )
}
