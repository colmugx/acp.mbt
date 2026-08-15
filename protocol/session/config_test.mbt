///|
using @protocol {
  type ProtocolNullable,
  type SessionConfigOption,
  type SessionInfo,
  type SessionUpdate,
  type ContentBlock,
  type McpServer,
  type AvailableCommandInput,
  protocol_parse_json,
  session_config_option_category_from_json,
  session_config_option_category_to_json,
  available_command_input_from_json,
  available_command_input_to_json,
  session_info_from_json,
}

///|
fn session_config_test_meta() -> ProtocolNullable[Json] {
  Omitted
}

///|
fn session_config_test_modes() -> SessionModeState {
  {
    current_mode_id: "code",
    available_modes: [
      {
        id: "ask",
        name: "Ask",
        description: Value("Answer questions"),
        meta: session_config_test_meta(),
      },
      { id: "code", name: "Code", description: Omitted, meta: Null },
    ],
    meta: Value({ "source": Json::string("test") }),
  }
}

///|
fn session_config_test_boolean_option() -> SessionConfigOption {
  {
    id: "confirm",
    name: "Confirm actions",
    description: Null,
    category: Value(ModelConfig),
    kind: Boolean({ current_value: true }),
    meta: session_config_test_meta(),
  }
}

///|
fn session_config_test_select_option() -> SessionConfigOption {
  {
    id: "model",
    name: "Model",
    description: Value("Model to use"),
    category: Value(Model),
    kind: Select({
      current_value: "fast",
      options: Ungrouped([
        {
          value: "fast",
          name: "Fast",
          description: Omitted,
          meta: session_config_test_meta(),
        },
        {
          value: "quality",
          name: "Quality",
          description: Null,
          meta: session_config_test_meta(),
        },
      ]),
    }),
    meta: session_config_test_meta(),
  }
}

///|
test "session modes and set mode data round trip" {
  let modes = session_config_test_modes()
  assert_eq(
    session_mode_state_from_json(session_mode_state_to_json(modes)),
    modes,
  )

  let params : SetSessionModeParams = {
    session_id: "s-mode",
    mode_id: "code",
    meta: Null,
  }
  assert_eq(
    set_session_mode_params_from_json(set_session_mode_params_to_json(params)),
    params,
  )
  let result : SetSessionModeResult = {
    meta: Value({ "ok": Json::boolean(true) }),
  }
  assert_eq(
    set_session_mode_result_from_json(set_session_mode_result_to_json(result)),
    result,
  )
}

///|
test "set config option preserves boolean and value id typed values" {
  let boolean : SetSessionConfigOptionParams = {
    session_id: "s-config",
    config_id: "confirm",
    value: Boolean(false),
    meta: Null,
  }
  assert_eq(
    set_session_config_option_params_from_json(
      set_session_config_option_params_to_json(boolean),
    ),
    boolean,
  )
  assert_eq(
    set_session_config_option_params_to_json(boolean),
    protocol_parse_json(
      "{\"sessionId\":\"s-config\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":false,\"_meta\":null}",
    ),
  )

  let value_id : SetSessionConfigOptionParams = {
    session_id: "s-config",
    config_id: "model",
    value: ValueId("quality"),
    meta: Omitted,
  }
  assert_eq(
    set_session_config_option_params_from_json(
      set_session_config_option_params_to_json(value_id),
    ),
    value_id,
  )
  assert_eq(
    set_session_config_option_params_to_json(value_id),
    protocol_parse_json(
      "{\"sessionId\":\"s-config\",\"configId\":\"model\",\"value\":\"quality\"}",
    ),
  )

  let result : SetSessionConfigOptionResult = {
    config_options: [
      session_config_test_boolean_option(),
      session_config_test_select_option(),
    ],
    meta: Null,
  }
  assert_eq(
    set_session_config_option_result_from_json(
      set_session_config_option_result_to_json(result),
    ),
    result,
  )
}

///|
test "config option categories and available command input retain wire shape" {
  let category = session_config_option_category_from_json(
    session_config_option_category_to_json(ThoughtLevel),
  )
  assert_eq(category, ThoughtLevel)
  assert_eq(
    session_config_option_category_from_json(protocol_parse_json("\"vendor\"")),
    Other("vendor"),
  )

  let input : AvailableCommandInput = Unstructured({
    hint: "text after command",
    meta: Null,
  })
  assert_eq(
    available_command_input_from_json(available_command_input_to_json(input)),
    input,
  )
}

///|
test "config mode and value errors are explicit" {
  try
    session_mode_state_from_json(
      protocol_parse_json(
        "{\"currentModeId\":\"ask\",\"availableModes\":[{\"id\":\"ask\",\"name\":\"Ask\",\"unknown\":true}]}",
      ),
    )
  catch {
    UnknownField(path="modes.availableModes[0].unknown") => ()
    _ => fail("expected mode unknown field rejection")
  } noraise {
    _ => fail("expected mode unknown field rejection")
  }

  try
    session_mode_state_from_json(
      protocol_parse_json("{\"currentModeId\":\"ask\"}"),
    )
  catch {
    MissingField(path="modes.availableModes") => ()
    _ => fail("expected missing modes")
  } noraise {
    _ => fail("expected missing modes")
  }

  try
    set_session_config_option_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"configId\":\"x\",\"type\":\"select\",\"value\":\"a\"}",
      ),
    )
  catch {
    InvalidDiscriminator(path="session/set_config_option.type", value="select") =>
      ()
    _ => fail("expected unknown config value discriminator")
  } noraise {
    _ => fail("expected unknown config value discriminator")
  }

  try
    set_session_config_option_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"configId\":\"x\",\"value\":true}",
      ),
    )
  catch {
    ExpectedString(path="session/set_config_option.value") => ()
    _ => fail("expected value id string rejection")
  } noraise {
    _ => fail("expected value id string rejection")
  }

  try
    set_session_config_option_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"configId\":\"x\",\"type\":\"boolean\",\"value\":\"yes\"}",
      ),
    )
  catch {
    ExpectedBoolean(path="session/set_config_option.value") => ()
    _ => fail("expected boolean value rejection")
  } noraise {
    _ => fail("expected boolean value rejection")
  }

  try
    set_session_config_option_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"configId\":\"x\",\"value\":\"a\",\"extra\":true}",
      ),
    )
  catch {
    UnknownField(path="session/set_config_option.extra") => ()
    _ => fail("expected config unknown field rejection")
  } noraise {
    _ => fail("expected config unknown field rejection")
  }
}

///|
test "mode state rejects a current mode outside available modes" {
  try
    session_mode_state_from_json(
      protocol_parse_json(
        "{\"currentModeId\":\"gone\",\"availableModes\":[{\"id\":\"ask\",\"name\":\"Ask\"},{\"id\":\"code\",\"name\":\"Code\"}]}",
      ),
    )
  catch {
    InvalidField(path="modes.currentModeId", reason=_) => ()
    _ => fail("expected unknown current mode rejection on decode")
  } noraise {
    _ => fail("expected unknown current mode rejection on decode")
  }

  let inconsistent : SessionModeState = {
    current_mode_id: "gone",
    available_modes: [
      { id: "ask", name: "Ask", description: Omitted, meta: Omitted },
    ],
    meta: Omitted,
  }
  try session_mode_state_to_json(inconsistent) catch {
    InvalidField(path="currentModeId", reason=_) => ()
    _ => fail("expected unknown current mode rejection on encode")
  } noraise {
    _ => fail("expected unknown current mode rejection on encode")
  }
}

///|
test "set config option result must carry the complete option set" {
  try
    set_session_config_option_result_from_json(protocol_parse_json("{}"))
  catch {
    MissingField(path="session/set_config_option.configOptions") => ()
    _ => fail("expected missing complete configOptions rejection")
  } noraise {
    _ => fail("expected missing complete configOptions rejection")
  }
}
