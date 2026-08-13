///|
using @agent_message {
  type AgentRequest,
  type AgentNotification,
  type AgentMessageError,
  decode_agent_request,
  decode_agent_notification,
}

///|
using @protocol_data {
  type ProtocolNullable,
  type AgentCapabilities,
  type ClientCapabilities,
  type AuthMethod,
  type InitializeParams,
  type CapabilityMarker,
  protocol_parse_json,
}

///|
fn agent_state_test_config(
  capabilities : ProtocolNullable[AgentCapabilities],
  auth_methods : ProtocolNullable[Array[AuthMethod]],
) -> AgentProtocolConfig {
  { agent_capabilities: capabilities, auth_methods, agent_info: Omitted }
}

///|
fn agent_state_test_initialize(
  state : AgentProtocolState,
  protocol_version : Int,
) -> AgentProtocolStep raise AgentProtocolError {
  let params : InitializeParams = {
    protocol_version,
    client_capabilities: Omitted,
    client_info: Omitted,
    meta: Omitted,
  }
  agent_protocol_reduce(state, Request(Initialize(params)))
}

///|
fn agent_state_test_initialize_with_client_capabilities(
  state : AgentProtocolState,
  protocol_version : Int,
  client_capabilities : ProtocolNullable[ClientCapabilities],
) -> AgentProtocolStep raise AgentProtocolError {
  let params : InitializeParams = {
    protocol_version,
    client_capabilities,
    client_info: Omitted,
    meta: Omitted,
  }
  agent_protocol_reduce(state, Request(Initialize(params)))
}

///|
fn agent_state_test_request(
  method_name : String,
  source : String,
) -> AgentRequest raise AgentMessageError {
  let value = protocol_parse_json(source) catch {
    _ => abort("test fixture must be valid JSON")
  }
  decode_agent_request(method_name, Some(value))
}

///|
fn agent_state_test_notification(
  method_name : String,
  source : String,
) -> AgentNotification raise AgentMessageError {
  let value = protocol_parse_json(source) catch {
    _ => abort("test fixture must be valid JSON")
  }
  decode_agent_notification(method_name, Some(value))
}

///|
fn agent_state_test_marker() -> CapabilityMarker {
  { meta: Omitted }
}

///|
fn agent_state_test_boolean_client_capabilities() -> ClientCapabilities {
  {
    fs: Omitted,
    terminal: Omitted,
    elicitation: Omitted,
    session: Value({
      config_options: Value({
        boolean: Value(agent_state_test_marker()),
        meta: Omitted,
      }),
      meta: Omitted,
    }),
    meta: Omitted,
  }
}

///|
fn agent_state_test_all_capabilities() -> AgentCapabilities {
  {
    load_session: Value(true),
    prompt_capabilities: Value({
      image: Value(true),
      audio: Value(true),
      embedded_context: Value(true),
      meta: Omitted,
    }),
    mcp_capabilities: Value({
      http: Value(true),
      sse: Value(true),
      meta: Omitted,
    }),
    auth: Value({ logout: Value(agent_state_test_marker()), meta: Omitted }),
    session_capabilities: Value({
      list: Value(agent_state_test_marker()),
      delete: Value(agent_state_test_marker()),
      resume_capability: Value(agent_state_test_marker()),
      close: Value(agent_state_test_marker()),
      additional_directories: Value(agent_state_test_marker()),
      meta: Omitted,
    }),
    meta: Omitted,
  }
}

///|
fn agent_state_test_all_null_capabilities() -> AgentCapabilities {
  {
    load_session: Null,
    prompt_capabilities: Null,
    mcp_capabilities: Null,
    auth: Null,
    session_capabilities: Null,
    meta: Omitted,
  }
}

///|
fn agent_state_test_auth_method() -> AuthMethod {
  { id: "token", name: "Token", description: Omitted, meta: Omitted }
}

///|
test "v1 handshake accepts only version one and rejects repetition" {
  let config = agent_state_test_config(Omitted, Omitted)
  let state = agent_protocol_state_new(config~)
  let preinitialize_request = agent_state_test_request("session/list", "{}")
  try agent_protocol_reduce(state, Request(preinitialize_request)) catch {
    NotInitialized(method_name="session/list") => ()
    _ => fail("expected business request before initialize to fail")
  } noraise {
    _ => fail("expected business request before initialize to fail")
  }

  let accepted = agent_state_test_initialize(state, 1)
  assert_eq(accepted.state.phase, Initialized)
  assert_eq(accepted.state.protocol_version, Value(1))
  match accepted.commands[0] {
    SendInitialize(result~, accepted=true) =>
      assert_eq(result.protocol_version, 1)
    _ => fail("expected accepted initialize command")
  }

  try agent_state_test_initialize(accepted.state, 1) catch {
    AlreadyInitialized => ()
    _ => fail("expected duplicate initialize rejection")
  } noraise {
    _ => fail("expected duplicate initialize rejection")
  }

  let mismatch = agent_state_test_initialize(state, 2)
  assert_eq(mismatch.state.phase, AwaitingInitialize)
  match mismatch.commands[0] {
    SendInitialize(result~, accepted=false) =>
      assert_eq(result.protocol_version, 1)
    _ => fail("expected version-mismatch initialize reply")
  }
}

///|
test "authentication is advertised, sequenced, and completed by an event" {
  let config = agent_state_test_config(
    Value(agent_state_test_all_capabilities()),
    Value([agent_state_test_auth_method()]),
  )
  let initial = agent_protocol_state_new(config~)
  let initialized = agent_state_test_initialize(initial, 1).state
  let unauthenticated_new = agent_state_test_request(
    "session/new", "{\"cwd\":\"/\",\"mcpServers\":[]}",
  )

  try agent_protocol_reduce(initialized, Request(unauthenticated_new)) catch {
    AuthenticationRequired(method_name="session/new") => ()
    _ => fail("expected authentication gate")
  } noraise {
    _ => fail("expected authentication gate")
  }

  let unknown_auth = agent_state_test_request(
    "authenticate", "{\"methodId\":\"unknown\"}",
  )
  try agent_protocol_reduce(initialized, Request(unknown_auth)) catch {
    AuthenticationMethodNotAdvertised(method_id="unknown") => ()
    _ => fail("expected unknown authentication method rejection")
  } noraise {
    _ => fail("expected unknown authentication method rejection")
  }

  let auth = agent_state_test_request(
    "authenticate", "{\"methodId\":\"token\"}",
  )
  let auth_step = agent_protocol_reduce(initialized, Request(auth))
  match auth_step.commands[0] {
    Authenticate(method_id="token") => ()
    _ => fail("expected authentication command")
  }
  let authenticated = agent_protocol_reduce(
    auth_step.state,
    AuthenticationSucceeded(method_id="token"),
  )
  assert_eq(authenticated.state.authentication, Authenticated)

  try agent_protocol_reduce(authenticated.state, Request(auth)) catch {
    AlreadyAuthenticated => ()
    _ => fail("expected duplicate authentication rejection")
  } noraise {
    _ => fail("expected duplicate authentication rejection")
  }

  let logout = agent_state_test_request("logout", "{}")
  let logout_step = agent_protocol_reduce(authenticated.state, Request(logout))
  assert_true(logout_step.commands[0] is Logout)
  let logged_out = agent_protocol_reduce(logout_step.state, LoggedOut)
  assert_eq(logged_out.state.authentication, AwaitingAuthentication)
  try
    agent_protocol_reduce(logged_out.state, Request(unauthenticated_new))
  catch {
    AuthenticationRequired(method_name="session/new") => ()
    _ => fail("expected session/new to require authentication after logout")
  } noraise {
    _ => fail("expected session/new to require authentication after logout")
  }
}

///|
test "boolean config values require the negotiated client capability" {
  let config = agent_state_test_config(Omitted, Omitted)
  let request = agent_state_test_request(
    "session/set_config_option", "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
  )
  let no_session : ClientCapabilities = {
    fs: Omitted,
    terminal: Omitted,
    elicitation: Omitted,
    session: Omitted,
    meta: Omitted,
  }
  let no_config_options : ClientCapabilities = {
    fs: Omitted,
    terminal: Omitted,
    elicitation: Omitted,
    session: Value({ config_options: Omitted, meta: Omitted }),
    meta: Omitted,
  }
  let null_boolean : ClientCapabilities = {
    fs: Omitted,
    terminal: Omitted,
    elicitation: Omitted,
    session: Value({
      config_options: Value({ boolean: Null, meta: Omitted }),
      meta: Omitted,
    }),
    meta: Omitted,
  }
  let denied_capabilities : Array[ProtocolNullable[ClientCapabilities]] = [
    Omitted,
    Null,
    Value(no_session),
    Value(no_config_options),
    Value(null_boolean),
  ]
  for client_capabilities in denied_capabilities {
    let state = agent_state_test_initialize_with_client_capabilities(
        agent_protocol_state_new(config~),
        1,
        client_capabilities,
      ).state
    try agent_protocol_reduce(state, Request(request)) catch {
      CapabilityDenied(
        method_name="session/set_config_option",
        capability="session.configOptions.boolean"
      ) => ()
      _ => fail("expected boolean config capability denial")
    } noraise {
      _ => fail("expected boolean config capability denial")
    }
  }

  let enabled_state = agent_state_test_initialize_with_client_capabilities(
      agent_protocol_state_new(config~),
      1,
      Value(agent_state_test_boolean_client_capabilities()),
    ).state
  let true_step = agent_protocol_reduce(enabled_state, Request(request))
  assert_true(
    true_step.commands[0] is DispatchRequest(SessionSetConfigOption(_)),
  )
  let false_request = agent_state_test_request(
    "session/set_config_option", "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":false}",
  )
  let false_step = agent_protocol_reduce(enabled_state, Request(false_request))
  assert_true(
    false_step.commands[0] is DispatchRequest(SessionSetConfigOption(_)),
  )

  let value_id_request = agent_state_test_request(
    "session/set_config_option", "{\"sessionId\":\"s\",\"configId\":\"mode\",\"value\":\"fast\"}",
  )
  let no_boolean_state = agent_state_test_initialize(
      agent_protocol_state_new(config~),
      1,
    ).state
  let value_id_step = agent_protocol_reduce(
    no_boolean_state,
    Request(value_id_request),
  )
  assert_true(
    value_id_step.commands[0] is DispatchRequest(SessionSetConfigOption(_)),
  )
}

///|
test "omitted and null capabilities deny every optional gate" {
  let omitted_config = agent_state_test_config(Omitted, Omitted)
  let omitted = agent_protocol_state_new(config=omitted_config)
  let null_caps_config = agent_state_test_config(
    Value(agent_state_test_all_null_capabilities()),
    Omitted,
  )
  let null_caps = agent_protocol_state_new(config=null_caps_config)
  let states = [
    agent_state_test_initialize(omitted, 1).state,
    agent_state_test_initialize(null_caps, 1).state,
  ]
  for state in states {
    let load = agent_state_test_request(
      "session/load", "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
    )
    try agent_protocol_reduce(state, Request(load)) catch {
      CapabilityDenied(method_name="session/load", capability="loadSession") =>
        ()
      _ => fail("expected loadSession gate")
    } noraise {
      _ => fail("expected loadSession gate")
    }

    let list = agent_state_test_request("session/list", "{}")
    try agent_protocol_reduce(state, Request(list)) catch {
      CapabilityDenied(method_name="session/list", capability="session.list") =>
        ()
      _ => fail("expected list gate")
    } noraise {
      _ => fail("expected list gate")
    }

    let delete = agent_state_test_request(
      "session/delete", "{\"sessionId\":\"s\"}",
    )
    try agent_protocol_reduce(state, Request(delete)) catch {
      CapabilityDenied(
        method_name="session/delete",
        capability="session.delete"
      ) => ()
      _ => fail("expected delete gate")
    } noraise {
      _ => fail("expected delete gate")
    }

    let close = agent_state_test_request(
      "session/close", "{\"sessionId\":\"s\"}",
    )
    try agent_protocol_reduce(state, Request(close)) catch {
      CapabilityDenied(method_name="session/close", capability="session.close") =>
        ()
      _ => fail("expected close gate")
    } noraise {
      _ => fail("expected close gate")
    }

    let resumed_request = agent_state_test_request(
      "session/resume", "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
    )
    try agent_protocol_reduce(state, Request(resumed_request)) catch {
      CapabilityDenied(
        method_name="session/resume",
        capability="session.resume"
      ) => ()
      _ => fail("expected resume gate")
    } noraise {
      _ => fail("expected resume gate")
    }

    let new_with_roots = agent_state_test_request(
      "session/new", "{\"cwd\":\"/\",\"additionalDirectories\":[\"/tmp\"],\"mcpServers\":[]}",
    )
    try agent_protocol_reduce(state, Request(new_with_roots)) catch {
      CapabilityDenied(
        method_name="session/new",
        capability="session.additionalDirectories"
      ) => ()
      _ => fail("expected additional directories gate")
    } noraise {
      _ => fail("expected additional directories gate")
    }

    let logout = agent_state_test_request("logout", "{}")
    try agent_protocol_reduce(state, Request(logout)) catch {
      CapabilityDenied(method_name="logout", capability="auth.logout") => ()
      _ => fail("expected logout gate")
    } noraise {
      _ => fail("expected logout gate")
    }
  }
}

///|
test "transport and prompt capability gates accept only explicitly enabled values" {
  let config = agent_state_test_config(
    Value(agent_state_test_all_capabilities()),
    Omitted,
  )
  let state = agent_state_test_initialize(agent_protocol_state_new(config~), 1).state

  let http = agent_state_test_request(
    "session/new", "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]}",
  )
  let http_step = agent_protocol_reduce(state, Request(http))
  assert_true(http_step.commands[0] is DispatchRequest(SessionNew(_)))

  let sse = agent_state_test_request(
    "session/new", "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"sse\",\"name\":\"events\",\"url\":\"https://example.test/events\",\"headers\":[]}]}",
  )
  assert_true(
    agent_protocol_reduce(state, Request(sse)).commands[0]
    is DispatchRequest(SessionNew(_)),
  )

  let image = agent_state_test_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"image\",\"data\":\"aA==\",\"mimeType\":\"image/png\"}]}",
  )
  assert_true(
    agent_protocol_reduce(state, Request(image)).commands[0]
    is DispatchRequest(SessionPrompt(_)),
  )
  let audio = agent_state_test_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"audio\",\"data\":\"aA==\",\"mimeType\":\"audio/wav\"}]}",
  )
  assert_true(
    agent_protocol_reduce(state, Request(audio)).commands[0]
    is DispatchRequest(SessionPrompt(_)),
  )
  let embedded = agent_state_test_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"resource\",\"resource\":{\"uri\":\"file:///tmp/a\",\"text\":\"body\"}}]}",
  )
  assert_true(
    agent_protocol_reduce(state, Request(embedded)).commands[0]
    is DispatchRequest(SessionPrompt(_)),
  )
}

///|
test "omitted and null prompt and MCP capabilities reject each optional payload" {
  let omitted_config = agent_state_test_config(Omitted, Omitted)
  let null_caps_config = agent_state_test_config(
    Value(agent_state_test_all_null_capabilities()),
    Omitted,
  )
  let states = [
    agent_state_test_initialize(
      agent_protocol_state_new(config=omitted_config),
      1,
    ).state,
    agent_state_test_initialize(
      agent_protocol_state_new(config=null_caps_config),
      1,
    ).state,
  ]
  let image = agent_state_test_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"image\",\"data\":\"aA==\",\"mimeType\":\"image/png\"}]}",
  )
  let audio = agent_state_test_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"audio\",\"data\":\"aA==\",\"mimeType\":\"audio/wav\"}]}",
  )
  let embedded = agent_state_test_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"resource\",\"resource\":{\"uri\":\"file:///tmp/a\",\"text\":\"body\"}}]}",
  )
  let http = agent_state_test_request(
    "session/new", "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]}",
  )
  let sse = agent_state_test_request(
    "session/new", "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"sse\",\"name\":\"events\",\"url\":\"https://example.test/events\",\"headers\":[]}]}",
  )
  for state in states {
    try agent_protocol_reduce(state, Request(image)) catch {
      CapabilityDenied(method_name="session/prompt", capability="prompt.image") =>
        ()
      _ => fail("expected omitted/null image capability denial")
    } noraise {
      _ => fail("expected omitted/null image capability denial")
    }
    try agent_protocol_reduce(state, Request(audio)) catch {
      CapabilityDenied(method_name="session/prompt", capability="prompt.audio") =>
        ()
      _ => fail("expected omitted/null audio capability denial")
    } noraise {
      _ => fail("expected omitted/null audio capability denial")
    }
    try agent_protocol_reduce(state, Request(embedded)) catch {
      CapabilityDenied(
        method_name="session/prompt",
        capability="prompt.embeddedContext"
      ) => ()
      _ => fail("expected omitted/null embedded context capability denial")
    } noraise {
      _ => fail("expected omitted/null embedded context capability denial")
    }
    try agent_protocol_reduce(state, Request(http)) catch {
      CapabilityDenied(method_name="session/new", capability="mcp.http") => ()
      _ => fail("expected omitted/null HTTP MCP capability denial")
    } noraise {
      _ => fail("expected omitted/null HTTP MCP capability denial")
    }
    try agent_protocol_reduce(state, Request(sse)) catch {
      CapabilityDenied(method_name="session/new", capability="mcp.sse") => ()
      _ => fail("expected omitted/null SSE MCP capability denial")
    } noraise {
      _ => fail("expected omitted/null SSE MCP capability denial")
    }
  }
}

///|
test "notifications become cancellation commands and require initialization" {
  let config = agent_state_test_config(Omitted, Omitted)
  let initial = agent_protocol_state_new(config~)
  let cancel = agent_state_test_notification(
    "session/cancel", "{\"sessionId\":\"s\"}",
  )
  try agent_protocol_reduce(initial, Notification(cancel)) catch {
    NotInitialized(method_name="session/cancel") => ()
    _ => fail("expected pre-initialize notification rejection")
  } noraise {
    _ => fail("expected pre-initialize notification rejection")
  }

  let state = agent_state_test_initialize(initial, 1).state
  let session_step = agent_protocol_reduce(state, Notification(cancel))
  assert_true(session_step.commands[0] is CancelSession(session_id="s"))
  let request_cancel = agent_state_test_notification(
    "$/cancel_request", "{\"requestId\":7}",
  )
  let request_step = agent_protocol_reduce(state, Notification(request_cancel))
  assert_true(request_step.commands[0] is CancelRequest(request_id=Number(7)))
}
