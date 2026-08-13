///|
fn update_test_omitted_json() -> ProtocolNullable[Json] {
  Omitted
}

///|
fn update_test_content_chunk() -> ContentChunk {
  {
    content: Text({
      annotations: Omitted,
      text: "streamed text",
      meta: update_test_omitted_json(),
    }),
    message_id: Value("message-1"),
    meta: update_test_omitted_json(),
  }
}

///|
fn update_test_tool_call() -> ToolCall {
  {
    tool_call_id: "call-1",
    title: "Run command",
    kind: Value(Execute),
    status: Value(InProgress),
    content: Omitted,
    locations: Omitted,
    raw_input: Value({ "command": Json::string("echo ok") }),
    raw_output: Omitted,
    meta: update_test_omitted_json(),
  }
}

///|
fn update_test_tool_call_update() -> ToolCallUpdate {
  {
    tool_call_id: "call-1",
    kind: Omitted,
    status: Value(Completed),
    title: Omitted,
    content: Null,
    locations: Omitted,
    raw_input: Omitted,
    raw_output: Value(Json::string("ok")),
    meta: update_test_omitted_json(),
  }
}

///|
fn update_test_plan() -> Plan {
  {
    entries: [
      {
        content: "Inspect the repository",
        priority: High,
        status: Completed,
        meta: update_test_omitted_json(),
      },
      {
        content: "Apply the change",
        priority: Medium,
        status: InProgress,
        meta: update_test_omitted_json(),
      },
      {
        content: "Run verification",
        priority: Low,
        status: Pending,
        meta: update_test_omitted_json(),
      },
    ],
    meta: update_test_omitted_json(),
  }
}

///|
fn update_test_commands() -> AvailableCommandsUpdate {
  {
    available_commands: [
      {
        name: "help",
        description: "Show help",
        input: Value(
          Unstructured({
            hint: "optional topic",
            meta: update_test_omitted_json(),
          }),
        ),
        meta: update_test_omitted_json(),
      },
    ],
    meta: update_test_omitted_json(),
  }
}

///|
fn update_test_config() -> ConfigOptionUpdate {
  {
    config_options: [
      {
        id: "model",
        name: "Model",
        description: Value("Model selection"),
        category: Value(Model),
        kind: Select({
          current_value: "fast",
          options: Ungrouped([
            {
              value: "fast",
              name: "Fast",
              description: Null,
              meta: update_test_omitted_json(),
            },
          ]),
        }),
        meta: update_test_omitted_json(),
      },
      {
        id: "thinking",
        name: "Thinking",
        description: Omitted,
        category: Value(ThoughtLevel),
        kind: Boolean({ current_value: true }),
        meta: update_test_omitted_json(),
      },
      {
        id: "safety",
        name: "Safety",
        description: Null,
        category: Null,
        kind: Select({
          current_value: "strict",
          options: Grouped([
            {
              group: "safety",
              name: "Safety",
              options: [
                {
                  value: "strict",
                  name: "Strict",
                  description: Omitted,
                  meta: update_test_omitted_json(),
                },
              ],
              meta: update_test_omitted_json(),
            },
          ]),
        }),
        meta: update_test_omitted_json(),
      },
    ],
    meta: update_test_omitted_json(),
  }
}

///|
test "all stable session update variants round trip" {
  let chunk = update_test_content_chunk()
  let updates : Array[SessionUpdate] = [
    UserMessageChunk(chunk),
    AgentMessageChunk(chunk),
    AgentThoughtChunk(chunk),
    ToolCall(update_test_tool_call()),
    ToolCallUpdate(update_test_tool_call_update()),
    Plan(update_test_plan()),
    AvailableCommandsUpdate(update_test_commands()),
    CurrentModeUpdate({
      current_mode_id: "default",
      meta: update_test_omitted_json(),
    }),
    ConfigOptionUpdate(update_test_config()),
    SessionInfoUpdate({
      title: Null,
      updated_at: Value("2026-08-11T00:00:00Z"),
      meta: update_test_omitted_json(),
    }),
    UsageUpdate({
      used: 128,
      size: 4096,
      cost: Value({
        amount: 0.25,
        currency: "USD",
        meta: update_test_omitted_json(),
      }),
      meta: update_test_omitted_json(),
    }),
  ]
  for update in updates {
    assert_eq(session_update_from_json(session_update_to_json(update)), update)
  }
}

///|
test "session update patch omission and null remain distinct" {
  let omitted : SessionUpdate = ToolCallUpdate({
    tool_call_id: "call-1",
    kind: Omitted,
    status: Omitted,
    title: Omitted,
    content: Omitted,
    locations: Omitted,
    raw_input: Omitted,
    raw_output: Omitted,
    meta: Omitted,
  })
  let cleared : SessionUpdate = ToolCallUpdate({
    tool_call_id: "call-1",
    kind: Null,
    status: Null,
    title: Null,
    content: Null,
    locations: Null,
    raw_input: Null,
    raw_output: Null,
    meta: Null,
  })
  assert_eq(session_update_from_json(session_update_to_json(omitted)), omitted)
  assert_eq(session_update_from_json(session_update_to_json(cleared)), cleared)
}

///|
test "session info validates and round trips absolute directories" {
  let info : SessionInfo = {
    session_id: "session-1",
    cwd: "/tmp/acp",
    additional_directories: Value(["/tmp/acp/src"]),
    title: Value("ACP session"),
    updated_at: Null,
    meta: update_test_omitted_json(),
  }
  assert_eq(session_info_from_json(session_info_to_json(info)), info)
}

///|
test "session update discriminator and required fields fail explicitly" {
  try session_update_from_json(protocol_parse_json("{}")) catch {
    MissingField(path="sessionUpdate.sessionUpdate") => ()
    _ => fail("expected missing session update discriminator")
  } noraise {
    _ => fail("expected missing discriminator to fail")
  }
  try
    session_update_from_json(
      protocol_parse_json("{\"sessionUpdate\":\"unknown\"}"),
    )
  catch {
    InvalidDiscriminator(path="sessionUpdate.sessionUpdate", value="unknown") =>
      ()
    _ => fail("expected unknown session update discriminator")
  } noraise {
    _ => fail("expected unknown discriminator to fail")
  }
  try
    session_update_from_json(protocol_parse_json("{\"sessionUpdate\":7}"))
  catch {
    ExpectedString(path="sessionUpdate.sessionUpdate") => ()
    _ => fail("expected non-string discriminator error")
  } noraise {
    _ => fail("expected non-string discriminator to fail")
  }
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"plan\",\"entries\":[{\"content\":\"x\",\"priority\":\"high\",\"status\":\"pending\",\"extra\":true}]}",
      ),
    )
  catch {
    UnknownField(path="sessionUpdate.entries[0].extra") => ()
    _ => fail("expected unknown payload field error")
  } noraise {
    _ => fail("expected unknown payload field to fail")
  }
}

///|
test "session update nested values validate types and paths" {
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"usage_update\",\"used\":-1,\"size\":1}",
      ),
    )
  catch {
    InvalidField(path="sessionUpdate.used", reason=_) => ()
    _ => fail("expected unsigned usage validation error")
  } noraise {
    _ => fail("expected negative usage to fail")
  }
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"x\",\"name\":\"X\",\"type\":\"unknown\"}]}",
      ),
    )
  catch {
    InvalidDiscriminator(
      path="sessionUpdate.configOptions[0].type",
      value="unknown"
    ) => ()
    _ => fail("expected unknown config option discriminator")
  } noraise {
    _ => fail("expected unknown config option type to fail")
  }
  try
    session_info_from_json(
      protocol_parse_json("{\"sessionId\":\"s\",\"cwd\":\"relative\"}"),
    )
  catch {
    InvalidPath(path="sessionInfo.cwd", value="relative") => ()
    _ => fail("expected session cwd path validation error")
  } noraise {
    _ => fail("expected relative session cwd to fail")
  }
}

///|
test "usage update preserves exact uint64 numbers and round trips" {
  let source = "{\"sessionUpdate\":\"usage_update\",\"used\":9007199254740993,\"size\":18446744073709551615}"
  let update = session_update_from_json(protocol_parse_json(source))
  match update {
    UsageUpdate(value) => {
      assert_eq(value.used, 9007199254740993UL)
      assert_eq(value.size, 18446744073709551615UL)
      assert_eq(
        session_update_from_json(session_update_to_json(update)),
        update,
      )
    }
    _ => fail("expected usage update")
  }
}

///|
test "uint64 numbers accept exact integral exponents and reject invalid values" {
  let exponent = protocol_parse_json(
    "{\"sessionUpdate\":\"usage_update\",\"used\":1e+3,\"size\":1000e-3}",
  )
  let decoded = session_update_from_json(exponent)
  match decoded {
    UsageUpdate(value) => {
      assert_eq(value.used, 1000UL)
      assert_eq(value.size, 1UL)
    }
    _ => fail("expected usage update")
  }
  for
    source in [
      "{\"sessionUpdate\":\"usage_update\",\"used\":18446744073709551616,\"size\":1}",
      "{\"sessionUpdate\":\"usage_update\",\"used\":-1,\"size\":1}", "{\"sessionUpdate\":\"usage_update\",\"used\":1.5,\"size\":1}",
      "{\"sessionUpdate\":\"usage_update\",\"used\":1e-3,\"size\":1}",
    ] {
    try session_update_from_json(protocol_parse_json(source)) catch {
      InvalidField(path="sessionUpdate.used", reason=_) => ()
      _ => fail("expected invalid uint64 usage value")
    } noraise {
      _ => fail("expected invalid uint64 usage value to fail")
    }
  }
}
