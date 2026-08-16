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

///|
fn update_test_chunk(
  text : String,
  message_id? : ProtocolNullable[MessageId] = Value("message-1"),
) -> ContentChunk {
  {
    content: Text({
      annotations: Omitted,
      text,
      meta: update_test_omitted_json(),
    }),
    message_id,
    meta: update_test_omitted_json(),
  }
}

///|
fn update_test_fold() -> SessionUpdateFold {
  session_update_fold(known_modes=["default", "extended"])
}

///|
fn update_test_chunk_text(
  blocks : Array[ContentBlock],
  index : Int,
) -> String raise Failure {
  match blocks[index] {
    Text(content) => content.text
    _ => fail("expected text content block")
  }
}

///|
test "e01 fold user message chunks aggregate by message id" {
  let first = session_update_apply(
    update_test_fold(),
    UserMessageChunk(update_test_chunk("Hello")),
  )
  let state = match first {
    Ok(state) => state
    Err(_) => fail("expected user message chunk to apply")
  }
  let second = session_update_apply(
    state,
    UserMessageChunk(update_test_chunk(" world")),
  )
  let state = match second {
    Ok(state) => state
    Err(_) => fail("expected second user message chunk to apply")
  }
  let third = session_update_apply(
    state,
    UserMessageChunk(update_test_chunk("!", message_id=Omitted)),
  )
  let state = match third {
    Ok(state) => state
    Err(_) => fail("expected unidentified user message chunk to apply")
  }
  assert_eq(state.user_messages.length(), 2)
  assert_eq(state.user_messages[0].message_id, Value("message-1"))
  assert_eq(state.user_messages[0].blocks.length(), 2)
  assert_eq(update_test_chunk_text(state.user_messages[0].blocks, 0), "Hello")
  assert_eq(update_test_chunk_text(state.user_messages[0].blocks, 1), " world")
  assert_eq(state.user_messages[1].message_id, Omitted)
  assert_eq(state.user_messages[1].blocks.length(), 1)
  assert_eq(update_test_chunk_text(state.user_messages[1].blocks, 0), "!")
  assert_eq(state.agent_messages.length(), 0)
  assert_eq(state.agent_thoughts.length(), 0)
}

///|
test "e01 user message chunk missing content and wrong block rejected" {
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"user_message_chunk\",\"messageId\":\"m1\"}",
      ),
    )
  catch {
    MissingField(path="sessionUpdate.content") => ()
    _ => fail("expected missing chunk content error")
  } noraise {
    _ => fail("expected missing chunk content to fail")
  }
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"user_message_chunk\",\"content\":{\"type\":\"text\",\"text\":7}}",
      ),
    )
  catch {
    ExpectedString(path="sessionUpdate.content.text") => ()
    _ => fail("expected malformed text block error")
  } noraise {
    _ => fail("expected malformed text block to fail")
  }
}

///|
test "e02 fold agent message id change starts a new message" {
  let first = session_update_apply(
    update_test_fold(),
    AgentMessageChunk(update_test_chunk("first", message_id=Value("a"))),
  )
  let state = match first {
    Ok(state) => state
    Err(_) => fail("expected agent message chunk to apply")
  }
  let second = session_update_apply(
    state,
    AgentMessageChunk(update_test_chunk(" more", message_id=Value("a"))),
  )
  let state = match second {
    Ok(state) => state
    Err(_) => fail("expected second agent message chunk to apply")
  }
  let third = session_update_apply(
    state,
    AgentMessageChunk(update_test_chunk("second", message_id=Value("b"))),
  )
  let state = match third {
    Ok(state) => state
    Err(_) => fail("expected id-changing agent message chunk to apply")
  }
  assert_eq(state.agent_messages.length(), 2)
  assert_eq(state.agent_messages[0].message_id, Value("a"))
  assert_eq(state.agent_messages[0].blocks.length(), 2)
  assert_eq(update_test_chunk_text(state.agent_messages[0].blocks, 0), "first")
  assert_eq(update_test_chunk_text(state.agent_messages[0].blocks, 1), " more")
  assert_eq(state.agent_messages[1].message_id, Value("b"))
  assert_eq(state.agent_messages[1].blocks.length(), 1)
  assert_eq(update_test_chunk_text(state.agent_messages[1].blocks, 0), "second")
  assert_eq(state.user_messages.length(), 0)
}

///|
test "e03 fold agent thought chunks never merge into agent messages" {
  let first = session_update_apply(
    update_test_fold(),
    AgentMessageChunk(update_test_chunk("answer", message_id=Value("shared"))),
  )
  let state = match first {
    Ok(state) => state
    Err(_) => fail("expected agent message chunk to apply")
  }
  let second = session_update_apply(
    state,
    AgentThoughtChunk(
      update_test_chunk("reasoning", message_id=Value("shared")),
    ),
  )
  let state = match second {
    Ok(state) => state
    Err(_) => fail("expected agent thought chunk to apply")
  }
  assert_eq(state.agent_messages.length(), 1)
  assert_eq(state.agent_messages[0].blocks.length(), 1)
  assert_eq(update_test_chunk_text(state.agent_messages[0].blocks, 0), "answer")
  assert_eq(state.agent_thoughts.length(), 1)
  assert_eq(state.agent_thoughts[0].message_id, Value("shared"))
  assert_eq(state.agent_thoughts[0].blocks.length(), 1)
  assert_eq(
    update_test_chunk_text(state.agent_thoughts[0].blocks, 0),
    "reasoning",
  )
}

///|
test "e04 fold tool call creates once and rejects duplicate id" {
  let created = session_update_apply(
    update_test_fold(),
    ToolCall(update_test_tool_call()),
  )
  let state = match created {
    Ok(state) => state
    Err(_) => fail("expected initial tool call to apply")
  }
  assert_eq(state.tool_calls.length(), 1)
  assert_eq(state.tool_calls[0].tool_call_id, "call-1")
  assert_eq(state.tool_calls[0].title, "Run command")
  let duplicate : ToolCall = {
    ..update_test_tool_call(),
    title: "Run command again",
  }
  match session_update_apply(state, ToolCall(duplicate)) {
    Err(DuplicateToolCall(tool_call_id="call-1")) => ()
    _ => fail("expected duplicate tool call id to be rejected")
  }
  assert_eq(state.tool_calls.length(), 1)
  assert_eq(state.tool_calls[0].title, "Run command")
}

///|
test "e05 fold tool call update patches known call and rejects unknown id" {
  let existing : ToolCall = {
    ..update_test_tool_call(),
    content: Value([
      Content({
        content: Text({
          annotations: Omitted,
          text: "partial output",
          meta: update_test_omitted_json(),
        }),
        meta: update_test_omitted_json(),
      }),
    ]),
  }
  let created = session_update_apply(update_test_fold(), ToolCall(existing))
  let state = match created {
    Ok(state) => state
    Err(_) => fail("expected initial tool call to apply")
  }
  let patch : ToolCallUpdate = {
    tool_call_id: "call-1",
    kind: Null,
    status: Value(Completed),
    title: Null,
    content: Null,
    locations: Value([
      {
        path: "/tmp/acp/out.txt",
        line: Omitted,
        meta: update_test_omitted_json(),
      },
    ]),
    raw_input: Omitted,
    raw_output: Value(Json::string("ok")),
    meta: update_test_omitted_json(),
  }
  let updated = session_update_apply(state, ToolCallUpdate(patch))
  let state = match updated {
    Ok(state) => state
    Err(_) => fail("expected tool call update to apply")
  }
  assert_eq(state.tool_calls.length(), 1)
  let call = state.tool_calls[0]
  assert_eq(call.tool_call_id, "call-1")
  assert_eq(call.kind, Omitted)
  assert_eq(call.status, Value(Completed))
  assert_eq(call.title, "Run command")
  assert_eq(call.content, Omitted)
  match call.locations {
    Value(locations) => {
      assert_eq(locations.length(), 1)
      assert_eq(locations[0].path, "/tmp/acp/out.txt")
    }
    _ => fail("expected replaced locations to be recorded")
  }
  assert_eq(call.raw_input, existing.raw_input)
  assert_eq(call.raw_output, Value(Json::string("ok")))
  let unknown : ToolCallUpdate = {
    ..update_test_tool_call_update(),
    tool_call_id: "call-missing",
  }
  match session_update_apply(state, ToolCallUpdate(unknown)) {
    Err(UnknownToolCall(tool_call_id="call-missing")) => ()
    _ => fail("expected unknown tool call id to be rejected")
  }
  assert_eq(state.tool_calls.length(), 1)
}

///|
test "e06 fold plan update replaces the entire plan" {
  let initial = session_update_apply(
    update_test_fold(),
    Plan(update_test_plan()),
  )
  let state = match initial {
    Ok(state) => state
    Err(_) => fail("expected initial plan to apply")
  }
  match state.plan {
    Some(plan) => assert_eq(plan, update_test_plan())
    None => fail("expected plan to be recorded")
  }
  let replacement : Plan = {
    entries: [
      {
        content: "Only remaining task",
        priority: High,
        status: InProgress,
        meta: update_test_omitted_json(),
      },
    ],
    meta: update_test_omitted_json(),
  }
  let replaced = session_update_apply(state, Plan(replacement))
  let state = match replaced {
    Ok(state) => state
    Err(_) => fail("expected replacement plan to apply")
  }
  match state.plan {
    Some(plan) => {
      assert_eq(plan.entries.length(), 1)
      assert_eq(plan.entries[0].content, "Only remaining task")
    }
    None => fail("expected replacement plan to be recorded")
  }
}

///|
test "e07 fold available commands update replaces the whole list" {
  let stale : AvailableCommandsUpdate = {
    available_commands: [
      {
        name: "help",
        description: "Show help",
        input: Omitted,
        meta: update_test_omitted_json(),
      },
      {
        name: "run",
        description: "Run a task",
        input: Omitted,
        meta: update_test_omitted_json(),
      },
    ],
    meta: update_test_omitted_json(),
  }
  let initial = session_update_apply(
    update_test_fold(),
    AvailableCommandsUpdate(stale),
  )
  let state = match initial {
    Ok(state) => state
    Err(_) => fail("expected initial commands update to apply")
  }
  assert_eq(state.available_commands.length(), 2)
  let replacement = update_test_commands()
  let replaced = session_update_apply(
    state,
    AvailableCommandsUpdate(replacement),
  )
  let state = match replaced {
    Ok(state) => state
    Err(_) => fail("expected replacement commands update to apply")
  }
  assert_eq(state.available_commands, replacement.available_commands)
  assert_eq(state.available_commands.length(), 1)
  assert_eq(state.available_commands[0].name, "help")
  assert_eq(state.available_commands[0].description, "Show help")
  match state.available_commands[0].input {
    Value(Unstructured(input)) => assert_eq(input.hint, "optional topic")
    _ => fail("expected command input definition to be preserved")
  }
}

///|
test "e08 fold current mode update validates against known modes" {
  let switched = session_update_apply(
    update_test_fold(),
    CurrentModeUpdate({
      current_mode_id: "extended",
      meta: update_test_omitted_json(),
    }),
  )
  let state = match switched {
    Ok(state) => state
    Err(_) => fail("expected known current mode update to apply")
  }
  match state.current_mode_id {
    Some(mode_id) => assert_eq(mode_id, "extended")
    None => fail("expected current mode id to be recorded")
  }
  let bogus = session_update_apply(
    state,
    CurrentModeUpdate({
      current_mode_id: "bogus",
      meta: update_test_omitted_json(),
    }),
  )
  match bogus {
    Err(UnknownMode(mode_id="bogus")) => ()
    _ => fail("expected unknown mode id to be rejected")
  }
  match state.current_mode_id {
    Some(mode_id) => assert_eq(mode_id, "extended")
    None => fail("expected rejected mode update to leave state unchanged")
  }
  let unaware = session_update_fold(known_modes=[])
  let defaulted = session_update_apply(
    unaware,
    CurrentModeUpdate({
      current_mode_id: "default",
      meta: update_test_omitted_json(),
    }),
  )
  match defaulted {
    Err(UnknownMode(mode_id="default")) => ()
    _ => fail("expected empty known mode set to reject every mode update")
  }
}

///|
test "e09 fold config option update replaces the complete set" {
  let initial = session_update_apply(
    update_test_fold(),
    ConfigOptionUpdate(update_test_config()),
  )
  let state = match initial {
    Ok(state) => state
    Err(_) => fail("expected initial config update to apply")
  }
  assert_eq(state.config_options.length(), 3)
  let replacement : ConfigOptionUpdate = {
    config_options: [
      {
        id: "thinking",
        name: "Thinking",
        description: Omitted,
        category: Value(ThoughtLevel),
        kind: Boolean({ current_value: false }),
        meta: update_test_omitted_json(),
      },
    ],
    meta: update_test_omitted_json(),
  }
  let replaced = session_update_apply(state, ConfigOptionUpdate(replacement))
  let state = match replaced {
    Ok(state) => state
    Err(_) => fail("expected replacement config update to apply")
  }
  assert_eq(state.config_options, replacement.config_options)
  assert_eq(state.config_options.length(), 1)
  assert_eq(state.config_options[0].id, "thinking")
  match state.config_options[0].kind {
    Boolean(kind) => assert_eq(kind.current_value, false)
    _ => fail("expected boolean config option kind")
  }
}

///|
test "e10 fold session info update tri-state and timestamp validation" {
  let titled = session_update_apply(
    update_test_fold(),
    SessionInfoUpdate({
      title: Value("ACP session"),
      updated_at: Value("2026-08-11T00:00:00Z"),
      meta: update_test_omitted_json(),
    }),
  )
  let state = match titled {
    Ok(state) => state
    Err(_) => fail("expected session info update to apply")
  }
  assert_eq(state.session_title, Value("ACP session"))
  assert_eq(state.session_updated_at, Value("2026-08-11T00:00:00Z"))
  let cleared = session_update_apply(
    state,
    SessionInfoUpdate({
      title: Null,
      updated_at: Omitted,
      meta: update_test_omitted_json(),
    }),
  )
  let state = match cleared {
    Ok(state) => state
    Err(_) => fail("expected title clearing update to apply")
  }
  assert_eq(state.session_title, Null)
  assert_eq(state.session_updated_at, Value("2026-08-11T00:00:00Z"))
  let reset = session_update_apply(
    state,
    SessionInfoUpdate({
      title: Value("Renamed"),
      updated_at: Value("2026-08-11t12:34:56.789+05:30"),
      meta: update_test_omitted_json(),
    }),
  )
  let state = match reset {
    Ok(state) => state
    Err(_) => fail("expected re-set session info update to apply")
  }
  assert_eq(state.session_title, Value("Renamed"))
  assert_eq(state.session_updated_at, Value("2026-08-11t12:34:56.789+05:30"))
  for
    timestamp in [
      "not-a-timestamp", "2026-13-01T00:00:00Z", "2026-02-30T00:00:00Z", "2026-08-11 00:00:00Z",
      "2026-08-11T00:00:00", "2026-8-11T00:00:00Z", "2026-08-11T24:00:00Z", "2026-08-11T00:00:00.",
    ] {
    let rejected = session_update_apply(
      state,
      SessionInfoUpdate({
        title: Omitted,
        updated_at: Value(timestamp),
        meta: update_test_omitted_json(),
      }),
    )
    match rejected {
      Err(InvalidTimestamp(field="updatedAt", value=invalid)) =>
        assert_eq(invalid, timestamp)
      _ => fail("expected invalid timestamp to be rejected: " + timestamp)
    }
  }
  assert_eq(state.session_title, Value("Renamed"))
  assert_eq(state.session_updated_at, Value("2026-08-11t12:34:56.789+05:30"))
  let leap = session_update_apply(
    state,
    SessionInfoUpdate({
      title: Omitted,
      updated_at: Value("2028-02-29T23:59:60Z"),
      meta: update_test_omitted_json(),
    }),
  )
  match leap {
    Ok(state) =>
      assert_eq(state.session_updated_at, Value("2028-02-29T23:59:60Z"))
    Err(_) => fail("expected leap-day leap-second timestamp to apply")
  }
  let other = update_test_fold()
  let isolated = session_update_apply(
    other,
    SessionInfoUpdate({
      title: Value("Other session"),
      updated_at: Omitted,
      meta: update_test_omitted_json(),
    }),
  )
  match isolated {
    Ok(isolated) => {
      assert_eq(isolated.session_title, Value("Other session"))
      assert_eq(state.session_title, Value("Renamed"))
    }
    Err(_) => fail("expected independent session fold to apply")
  }
}

///|
test "e11 fold usage update replaces prior usage" {
  let first = session_update_apply(
    update_test_fold(),
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
  )
  let state = match first {
    Ok(state) => state
    Err(_) => fail("expected usage update to apply")
  }
  match state.usage {
    Some(usage) => {
      assert_eq(usage.used, 128UL)
      assert_eq(usage.size, 4096UL)
      assert_true(usage.cost is Value(_))
    }
    None => fail("expected usage to be recorded")
  }
  let replacement : UsageUpdate = {
    used: 256,
    size: 8192,
    cost: Omitted,
    meta: update_test_omitted_json(),
  }
  let replaced = session_update_apply(state, UsageUpdate(replacement))
  match replaced {
    Ok(state) =>
      match state.usage {
        Some(usage) => assert_eq(usage, replacement)
        None => fail("expected replacement usage to be recorded")
      }
    Err(_) => fail("expected replacement usage update to apply")
  }
}

///|
test "fold session update apply is pure and deterministic" {
  let initial = update_test_fold()
  let first = session_update_apply(
    initial,
    UserMessageChunk(update_test_chunk("Hello")),
  )
  let state = match first {
    Ok(state) => state
    Err(_) => fail("expected user message chunk to apply")
  }
  let again_a = session_update_apply(
    state,
    UserMessageChunk(update_test_chunk(" again")),
  )
  let again_b = session_update_apply(
    state,
    UserMessageChunk(update_test_chunk(" again")),
  )
  match (again_a, again_b) {
    (Ok(a), Ok(b)) => {
      assert_eq(a, b)
      assert_eq(state.user_messages.length(), 1)
      assert_eq(state.user_messages[0].blocks.length(), 1)
      assert_eq(a.user_messages.length(), 1)
      assert_eq(a.user_messages[0].blocks.length(), 2)
    }
    _ => fail("expected deterministic chunk application")
  }
  let mode = session_update_apply(
    state,
    CurrentModeUpdate({
      current_mode_id: "default",
      meta: update_test_omitted_json(),
    }),
  )
  match mode {
    Ok(state) => {
      assert_eq(state.known_modes, ["default", "extended"])
      assert_eq(state.user_messages.length(), 1)
    }
    Err(_) => fail("expected known mode update to apply")
  }
}
