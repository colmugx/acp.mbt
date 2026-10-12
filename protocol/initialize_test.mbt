///|
fn init_test_omitted_meta() -> @protocol.ProtocolNullable[Json] {
  Omitted
}

///|
fn init_test_null_meta() -> @protocol.ProtocolNullable[Json] {
  Null
}

///|
fn init_test_marker() -> @protocol.CapabilityMarker {
  { meta: init_test_omitted_meta(), }
}

///|
test "implementation info preserves title and metadata tri-state" {
  let implementation : @protocol.Implementation = {
    name: "client",
    title: Null,
    version: "1.2.3",
    meta: Value({ "source": Json::string("test") }),
  }
  assert_eq(
    @protocol.implementation_from_json(
      @protocol.implementation_to_json(implementation),
    ),
    implementation,
  )
  let omitted : @protocol.Implementation = {
    name: "agent",
    title: Omitted,
    version: "0.1.0",
    meta: init_test_omitted_meta(),
  }
  assert_eq(
    @protocol.implementation_to_json(omitted),
    @protocol.protocol_parse_json("{\"name\":\"agent\",\"version\":\"0.1.0\"}"),
  )
}

///|
test "client capabilities keep independent gates and empty elicitation outer object" {
  let json = @protocol.protocol_parse_json(
    "{\"_meta\":{\"trace\":true},\"fs\":{\"readTextFile\":true,\"writeTextFile\":false},\"terminal\":true,\"elicitation\":{\"form\":{},\"url\":null},\"session\":{\"configOptions\":{\"boolean\":{}}}}",
  )
  let capabilities = @protocol.client_capabilities_from_json(json)
  match capabilities.fs {
    Value(fs) => {
      assert_eq(fs.read_text_file, Value(true))
      assert_eq(fs.write_text_file, Value(false))
    }
    _ => fail("expected fs capability")
  }
  assert_eq(capabilities.terminal, Value(true))
  match capabilities.elicitation {
    Value(elicitation) => {
      assert_eq(elicitation.form, Value(init_test_marker()))
      assert_eq(elicitation.url, Null)
    }
    _ => fail("expected elicitation capability")
  }
  match capabilities.session {
    Value(session) =>
      match session.config_options {
        Value(config_options) =>
          assert_eq(config_options.boolean, Value(init_test_marker()))
        _ => fail("expected config option capability")
      }
    _ => fail("expected session capability")
  }
  assert_eq(
    @protocol.client_capabilities_from_json(
      @protocol.client_capabilities_to_json(capabilities),
    ),
    capabilities,
  )
}

///|
test "omitted and null capabilities are unsupported without fallback" {
  let omitted = @protocol.client_capabilities_from_json(
    @protocol.protocol_parse_json("{}"),
  )
  assert_eq(omitted.fs, Omitted)
  assert_eq(omitted.terminal, Omitted)
  assert_eq(omitted.elicitation, Omitted)
  assert_eq(omitted.session, Omitted)
  let nulls = @protocol.client_capabilities_from_json(
    @protocol.protocol_parse_json(
      "{\"fs\":null,\"terminal\":null,\"elicitation\":null,\"session\":null}",
    ),
  )
  assert_eq(nulls.fs, Null)
  assert_eq(nulls.terminal, Null)
  assert_eq(nulls.elicitation, Null)
  assert_eq(nulls.session, Null)
  let empty_elicitation = @protocol.client_elicitation_capabilities_from_json(
    @protocol.protocol_parse_json("{}"),
  )
  assert_eq(empty_elicitation.form, Omitted)
  assert_eq(empty_elicitation.url, Omitted)
}

///|
test "agent capability gates preserve booleans and support markers" {
  let json = @protocol.protocol_parse_json(
    "{\"loadSession\":true,\"promptCapabilities\":{\"image\":true,\"audio\":null,\"embeddedContext\":false},\"mcpCapabilities\":{\"http\":true,\"sse\":false},\"auth\":{\"logout\":{}},\"sessionCapabilities\":{\"list\":{},\"delete\":null,\"resume\":{},\"close\":{},\"additionalDirectories\":{}}}",
  )
  let capabilities = @protocol.agent_capabilities_from_json(json)
  assert_eq(capabilities.load_session, Value(true))
  match capabilities.prompt_capabilities {
    Value(prompt) => {
      assert_eq(prompt.image, Value(true))
      assert_eq(prompt.audio, Null)
      assert_eq(prompt.embedded_context, Value(false))
    }
    _ => fail("expected prompt capability")
  }
  match capabilities.mcp_capabilities {
    Value(mcp) => {
      assert_eq(mcp.http, Value(true))
      assert_eq(mcp.sse, Value(false))
    }
    _ => fail("expected mcp capability")
  }
  match capabilities.auth {
    Value(auth) => assert_eq(auth.logout, Value(init_test_marker()))
    _ => fail("expected auth capability")
  }
  match capabilities.session_capabilities {
    Value(session) => {
      assert_eq(session.list, Value(init_test_marker()))
      assert_eq(session.delete, Null)
      assert_eq(session.resume_capability, Value(init_test_marker()))
      assert_eq(session.close, Value(init_test_marker()))
      assert_eq(session.additional_directories, Value(init_test_marker()))
    }
    _ => fail("expected session capability")
  }
  assert_eq(
    @protocol.agent_capabilities_from_json(
      @protocol.agent_capabilities_to_json(capabilities),
    ),
    capabilities,
  )
}

///|
test "initialize params and result round trip version negotiation data" {
  let params : @protocol.InitializeParams = {
    protocol_version: 1,
    client_capabilities: Value({
      fs: Value({
        read_text_file: Value(true),
        write_text_file: Omitted,
        meta: Omitted,
      }),
      terminal: Value(false),
      elicitation: Omitted,
      session: Omitted,
      plan: Omitted,
      auth: Omitted,
      meta: Omitted,
    }),
    client_info: Value({
      name: "client",
      title: Omitted,
      version: "1.0.0",
      meta: Omitted,
    }),
    meta: Omitted,
  }
  assert_eq(
    @protocol.initialize_params_from_json(
      @protocol.initialize_params_to_json(params),
    ),
    params,
  )
  let result : @protocol.InitializeResult = {
    protocol_version: 1,
    agent_capabilities: Null,
    auth_methods: Value([
      { id: "oauth", name: "OAuth", description: Null, meta: Omitted, },
    ]),
    agent_info: Omitted,
    meta: Omitted,
  }
  assert_eq(
    @protocol.initialize_result_from_json(
      @protocol.initialize_result_to_json(result),
    ),
    result,
  )
}

///|
test "initialize versions and required fields fail explicitly" {
  try
    @protocol.initialize_params_from_json(
      @protocol.protocol_parse_json("{\"protocolVersion\":65536}"),
    )
  catch {
    InvalidField(path="initialize.protocolVersion", reason=_) => ()
    _ => fail("expected protocol version range error")
  } noraise {
    _ => fail("expected protocol version range error")
  }
  try
    @protocol.initialize_params_from_json(@protocol.protocol_parse_json("{}"))
  catch {
    MissingField(path="initialize.protocolVersion") => ()
    _ => fail("expected missing protocol version error")
  } noraise {
    _ => fail("expected missing protocol version error")
  }
  try
    @protocol.implementation_from_json(
      @protocol.protocol_parse_json(
        "{\"name\":\"x\",\"version\":\"1\",\"extra\":true}",
      ),
    )
  catch {
    UnknownField(path="implementation.extra") => ()
    _ => fail("expected unknown implementation field")
  } noraise {
    _ => fail("expected unknown implementation field")
  }
}

///|
test "auth methods and authenticate/logout data preserve optional fields" {
  let auth_method : @protocol.AuthMethod = {
    id: "token",
    name: "Token",
    description: Omitted,
    meta: init_test_null_meta(),
  }
  assert_eq(
    @protocol.auth_method_from_json(@protocol.auth_method_to_json(auth_method)),
    auth_method,
  )
  let params : @protocol.AuthenticateParams = {
    method_id: "token",
    meta: Omitted,
  }
  assert_eq(
    @protocol.authenticate_params_from_json(
      @protocol.authenticate_params_to_json(params),
    ),
    params,
  )
  let result : @protocol.AuthenticateResult = { meta: Omitted, }
  assert_eq(
    @protocol.authenticate_result_from_json(
      @protocol.authenticate_result_to_json(result),
    ),
    result,
  )
  let logout : @protocol.LogoutResult = { meta: Null, }
  assert_eq(
    @protocol.logout_result_from_json(@protocol.logout_result_to_json(logout)),
    logout,
  )
  try
    @protocol.authenticate_params_from_json(
      @protocol.protocol_parse_json("{\"methodId\":\"\"}"),
    )
  catch {
    InvalidField(path="authenticate.methodId", reason=_) => ()
    _ => fail("expected empty method id error")
  } noraise {
    _ => fail("expected empty method id error")
  }
}

///|
test "capability and initialize unknown fields report precise paths" {
  try
    @protocol.client_capabilities_from_json(
      @protocol.protocol_parse_json(
        "{\"fs\":{\"readTextFile\":true,\"wat\":false}}",
      ),
    )
  catch {
    UnknownField(path="clientCapabilities.fs.wat") => ()
    _ => fail("expected nested unknown capability field")
  } noraise {
    _ => fail("expected nested unknown capability field")
  }
  try
    @protocol.agent_capabilities_from_json(
      @protocol.protocol_parse_json(
        "{\"promptCapabilities\":{\"image\":\"yes\"}}",
      ),
    )
  catch {
    ExpectedBoolean(path="agentCapabilities.promptCapabilities.image") => ()
    _ => fail("expected nested boolean type error")
  } noraise {
    _ => fail("expected nested boolean type error")
  }
}

///|
test "client capabilities accept upstream unstable plan and auth fields" {
  let params = @protocol.initialize_params_from_json(
    @protocol.protocol_parse_json(
      "{\"protocolVersion\":1,\"clientCapabilities\":{\"fs\":{\"readTextFile\":true,\"writeTextFile\":true},\"terminal\":true,\"plan\":{},\"auth\":{\"terminal\":true}}}",
    ),
  )
  guard params.client_capabilities
    is Value(
      {
        plan: Value({ meta: Omitted, }),
        auth: Value({ terminal: Value(true), meta: Omitted, }),
        ..
      }
    ) else {
    fail("expected plan marker and auth terminal capability")
  }
  // Null, omitted, and round-trip stay valid for both fields.
  let nulls = @protocol.client_capabilities_from_json(
    @protocol.protocol_parse_json("{\"plan\":null,\"auth\":null}"),
  )
  guard nulls is { plan: Null, auth: Null, .. } else {
    fail("expected null plan and auth")
  }
  let decoded = @protocol.client_capabilities_from_json(
    @protocol.protocol_parse_json("{\"plan\":{\"_meta\":{\"k\":1}}}"),
  )
  assert_eq(
    @protocol.client_capabilities_from_json(
      @protocol.client_capabilities_to_json(decoded),
    ),
    decoded,
  )
}

///|
test "agent session capabilities accept upstream unstable fork marker" {
  let capabilities = @protocol.agent_capabilities_from_json(
    @protocol.protocol_parse_json(
      "{\"sessionCapabilities\":{\"fork\":{},\"list\":{}}}",
    ),
  )
  guard capabilities.session_capabilities
    is Value({ fork: Value({ meta: Omitted, }), .. }) else {
    fail("expected fork capability marker")
  }
  // Omitted and null markers stay unsupported without fallback.
  let omitted = @protocol.agent_session_capabilities_from_json(
    @protocol.protocol_parse_json("{}"),
  )
  assert_eq(omitted.fork, Omitted)
  let nulls = @protocol.agent_session_capabilities_from_json(
    @protocol.protocol_parse_json("{\"fork\":null}"),
  )
  assert_eq(nulls.fork, Null)
  let decoded = @protocol.agent_session_capabilities_from_json(
    @protocol.protocol_parse_json("{\"fork\":{\"_meta\":{\"k\":1}}}"),
  )
  assert_eq(
    @protocol.agent_session_capabilities_from_json(
      @protocol.agent_session_capabilities_to_json(decoded),
    ),
    decoded,
  )
}
