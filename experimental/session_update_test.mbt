///|
test "v2 message upsert arms round-trip tri-state content" {
  for tag in ["user_message", "agent_message", "agent_thought"] {
    let omitted = model_test_round_trip(
      "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\"}",
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_true(
      omitted
      is Known(
        UpdateUserMessage({ content: PatchOmitted, .. })
        | UpdateAgentMessage({ content: PatchOmitted, .. })
        | UpdateAgentThought({ content: PatchOmitted, .. })
      ),
    )
    let nulled = model_test_round_trip(
      "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\",\"content\":null}",
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_true(
      nulled
      is Known(
        UpdateUserMessage({ content: PatchNull, .. })
        | UpdateAgentMessage({ content: PatchNull, .. })
        | UpdateAgentThought({ content: PatchNull, .. })
      ),
    )
    let emptied = model_test_round_trip(
      "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\",\"content\":[]}",
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_true(
      emptied
      is Known(
        UpdateUserMessage({ content: PatchValue([]), .. })
        | UpdateAgentMessage({ content: PatchValue([]), .. })
        | UpdateAgentThought({ content: PatchValue([]), .. })
      ),
    )
    let replaced = model_test_round_trip(
      "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"_meta\":{\"k\":1}}",
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_true(
      replaced
      is Known(
        UpdateUserMessage(
          {
            content: PatchValue([Known(BlockText({ text: "hi", .. }))]),
            meta: PatchValue(Object(_)),
            ..
          }
        )
        | UpdateAgentMessage(
          {
            content: PatchValue([Known(BlockText({ text: "hi", .. }))]),
            meta: PatchValue(Object(_)),
            ..
          }
        )
        | UpdateAgentThought(
          {
            content: PatchValue([Known(BlockText({ text: "hi", .. }))]),
            meta: PatchValue(Object(_)),
            ..
          }
        )
      ),
    )
    // The spec clears content for both null and []; the wire keeps the exact
    // spelling so a proxy can replay the author's choice byte-faithfully.
    let null_encoded = experimental_v2_encode_session_update(
      experimental_v2_decode_session_update(
        experimental_v2_parse_json(
          "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\",\"content\":null}",
        ),
      ),
    )
    assert_eq(
      experimental_v2_stringify_json(null_encoded),
      "{\"messageId\":\"m1\",\"content\":null,\"sessionUpdate\":\"\{tag}\"}",
    )
    let empty_encoded = experimental_v2_encode_session_update(
      experimental_v2_decode_session_update(
        experimental_v2_parse_json(
          "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\",\"content\":[]}",
        ),
      ),
    )
    assert_eq(
      experimental_v2_stringify_json(empty_encoded),
      "{\"messageId\":\"m1\",\"content\":[],\"sessionUpdate\":\"\{tag}\"}",
    )
  }
  try
    experimental_v2_decode_session_update(
      experimental_v2_parse_json("{\"sessionUpdate\":\"user_message\"}"),
    )
  catch {
    MissingField(path="update.messageId") => ()
    _ => fail("expected MissingField for an absent messageId")
  } noraise {
    _ => fail("expected MissingField for an absent messageId")
  }
  try
    experimental_v2_decode_session_update(
      experimental_v2_parse_json(
        "{\"sessionUpdate\":\"agent_thought\",\"messageId\":\"m1\",\"extra\":1}",
      ),
    )
  catch {
    UnknownField(path="update.extra") => ()
    _ => fail("expected UnknownField inside a message upsert")
  } noraise {
    _ => fail("expected UnknownField inside a message upsert")
  }
}

///|
test "v2 content chunks require messageId and content" {
  for
    tag in ["user_message_chunk", "agent_message_chunk", "agent_thought_chunk"] {
    let chunk = model_test_round_trip(
      "{\"sessionUpdate\":\"\{tag}\",\"messageId\":\"m1\",\"content\":{\"type\":\"text\",\"text\":\"par\"},\"_meta\":{\"c\":1}}",
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_true(
      chunk
      is Known(
        UpdateUserMessageChunk(
          {
            message_id: "m1",
            content: Known(BlockText({ text: "par", .. })),
            ..
          }
        )
        | UpdateAgentMessageChunk(
          {
            message_id: "m1",
            content: Known(BlockText({ text: "par", .. })),
            ..
          }
        )
        | UpdateAgentThoughtChunk(
          {
            message_id: "m1",
            content: Known(BlockText({ text: "par", .. })),
            ..
          }
        )
      ),
    )
  }
  // v2 tightened chunks over v1: the message id and a content item are both
  // required, never defaulted.
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"sessionUpdate\":\"user_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"x\"}}",
      MissingField(path="update.messageId"),
    ),
    (
      "{\"sessionUpdate\":\"agent_message_chunk\",\"messageId\":\"m1\"}",
      MissingField(path="update.content"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_session_update(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed chunk")
    }
  }
}

///|
test "v2 state update matrix per schema optionality" {
  let running = model_test_round_trip(
    "{\"state\":\"running\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_state_update(value),
    experimental_v2_encode_state_update,
  )
  assert_true(
    running
    is Known(StateRunning({ meta: Some(Object({ "k": Number(1, ..), .. })), })),
  )
  let requires_action = model_test_round_trip(
    "{\"state\":\"requires_action\"}",
    value => experimental_v2_decode_state_update(value),
    experimental_v2_encode_state_update,
  )
  assert_true(requires_action is Known(StateRequiresAction({ meta: None, })))
  let reasons : Array[(String, ExperimentalV2StopReason)] = [
    ("end_turn", StopReasonEndTurn),
    ("max_tokens", StopReasonMaxTokens),
    ("max_turn_requests", StopReasonMaxTurnRequests),
    ("refusal", StopReasonRefusal),
    ("cancelled", StopReasonCancelled),
    ("_custom", StopReasonExtension(tag="_custom")),
    ("paused", StopReasonFuture(raw="paused")),
  ]
  for reason in reasons {
    let (wire, expected) = reason
    let idle = model_test_round_trip(
      "{\"state\":\"idle\",\"stopReason\":\"\{wire}\"}",
      value => experimental_v2_decode_state_update(value),
      experimental_v2_encode_state_update,
    )
    guard idle is Known(StateIdle({ stop_reason: Some(idle_reason), .. })) else {
      fail("expected a decoded idle state with a stop reason")
    }
    assert_eq(idle_reason, expected)
    // Omitted and null stop reasons are equivalent.
    for
      source in [
        "{\"state\":\"idle\"}", "{\"state\":\"idle\",\"stopReason\":null}",
      ] {
      let idle = model_test_round_trip(
        source,
        value => experimental_v2_decode_state_update(value),
        experimental_v2_encode_state_update,
      )
      assert_true(idle is Known(StateIdle({ stop_reason: None, .. })))
    }
  }
  // stopReason exists only on idle; the other known states reject it.
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"state\":\"running\",\"stopReason\":\"end_turn\"}",
      UnknownField(path="state_update.stopReason"),
    ),
    (
      "{\"state\":\"requires_action\",\"stopReason\":\"cancelled\"}",
      UnknownField(path="state_update.stopReason"),
    ),
    (
      "{\"state\":\"idle\",\"stopReason\":5}",
      ExpectedString(path="state_update.stopReason"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_state_update(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for an illegal state payload")
    }
  }
}

///|
test "v2 state update keeps unknown states as raw payloads" {
  for
    source in [
      "{\"state\":\"_thinking\",\"payload\":{\"a\":1}}", "{\"state\":\"deferred\",\"payload\":{\"b\":2}}",
    ] {
    let state = model_test_round_trip(
      source,
      value => experimental_v2_decode_state_update(value),
      experimental_v2_encode_state_update,
    )
    assert_eq(
      experimental_v2_encode_state_update(state),
      experimental_v2_parse_json(source),
    )
  }
  let extension = experimental_v2_decode_state_update(
    experimental_v2_parse_json("{\"state\":\"_thinking\",\"x\":1}"),
  )
  assert_true(extension is Extension(tag="_thinking", ..))
  let future = experimental_v2_decode_state_update(
    experimental_v2_parse_json("{\"state\":\"deferred\",\"x\":1}"),
  )
  assert_true(future is Future(tag="deferred", ..))
}

///|
test "v2 plan update replaces entries wholesale incl cancelled" {
  let plan = model_test_round_trip(
    "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"items\",\"planId\":\"p1\",\"entries\":[{\"content\":\"a\",\"priority\":\"high\",\"status\":\"cancelled\"},{\"content\":\"b\",\"priority\":\"_prio\",\"status\":\"_hold\"},{\"content\":\"c\",\"priority\":\"low\",\"status\":\"later\"}],\"_meta\":{\"k\":1}}}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  guard plan
    is Known(
      UpdatePlan(
        {
          plan: Known(
            PlanItemsContent(
              {
                plan_id: "p1",
                entries: [
                  {
                    content: "a",
                    priority: PlanPriorityHigh,
                    status: PlanStatusCancelled,
                    ..
                  },
                  {
                    content: "b",
                    priority: PlanPriorityExtension(tag="_prio"),
                    status: PlanStatusExtension(tag="_hold"),
                    ..
                  },
                  {
                    content: "c",
                    priority: PlanPriorityLow,
                    status: PlanStatusFuture(raw="later"),
                    ..
                  },
                ],
                ..
              }
            )
          ),
          ..
        }
      )
    ) else {
    fail("expected a decoded items plan with cancelled and open statuses")
  }
  // An empty entries list is a legal whole-plan replacement.
  let emptied = model_test_round_trip(
    "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"items\",\"planId\":\"p1\",\"entries\":[]}}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    emptied
    is Known(
      UpdatePlan({ plan: Known(PlanItemsContent({ entries: [], .. })), .. })
    ),
  )
  // Unknown plan content kinds keep their raw payload for replay.
  for
    source in [
      "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"file\",\"planId\":\"p1\",\"path\":\"/p\"}}",
      "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"_canvas\",\"planId\":\"p1\",\"nodes\":[]}}",
    ] {
    let update = model_test_round_trip(
      source,
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_eq(
      experimental_v2_encode_session_update(update),
      experimental_v2_parse_json(source),
    )
  }
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    ("{\"sessionUpdate\":\"plan_update\"}", MissingField(path="update.plan")),
    (
      "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"items\",\"planId\":\"p1\"}}",
      MissingField(path="update.plan.entries"),
    ),
    (
      "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"items\",\"planId\":\"p1\",\"entries\":[{\"content\":\"a\",\"priority\":\"high\"}]}}",
      MissingField(path="update.plan.entries[0].status"),
    ),
    (
      "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"items\",\"planId\":\"\",\"entries\":[]}}",
      InvalidField(path="update.plan.planId", reason="id must not be empty"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_session_update(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed plan update")
    }
  }
}

///|
test "v2 tool call and terminal arms round-trip through session update" {
  let tool_call = model_test_round_trip(
    "{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"tc1\",\"title\":\"Run tests\",\"kind\":\"execute\",\"status\":\"in_progress\"}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    tool_call
    is Known(
      UpdateToolCall(
        {
          tool_call_id: "tc1",
          title: PatchValue("Run tests"),
          kind: PatchValue(ToolKindExecute),
          status: PatchValue(ToolCallStatusInProgress),
          ..
        }
      )
    ),
  )
  let tool_chunk = model_test_round_trip(
    "{\"sessionUpdate\":\"tool_call_content_chunk\",\"toolCallId\":\"tc1\",\"content\":{\"type\":\"terminal\",\"terminalId\":\"t1\"}}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    tool_chunk
    is Known(
      UpdateToolCallContentChunk(
        {
          content: Known(ToolCallContentTerminal({ terminal_id: "t1", .. })),
          ..
        }
      )
    ),
  )
  let terminal = model_test_round_trip(
    "{\"sessionUpdate\":\"terminal_update\",\"terminalId\":\"t1\",\"command\":\"cargo test\",\"exitStatus\":{\"exitCode\":0}}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    terminal
    is Known(
      UpdateTerminal(
        {
          command: PatchValue("cargo test"),
          exit_status: PatchValue({ exit_code: Some(0), .. }),
          ..
        }
      )
    ),
  )
  let output_chunk = model_test_round_trip(
    "{\"sessionUpdate\":\"terminal_output_chunk\",\"terminalId\":\"t1\",\"data\":\"aGVsbG8=\"}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    output_chunk is Known(UpdateTerminalOutputChunk({ data: "aGVsbG8=", .. })),
  )
}

///|
test "v2 available commands update round-trips the input union" {
  let commands = model_test_round_trip(
    "{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"create_plan\",\"description\":\"Plan work\",\"input\":{\"type\":\"text\",\"hint\":\"What to plan?\"}},{\"name\":\"status\",\"description\":\"Report status\",\"input\":null}]}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  guard commands
    is Known(
      UpdateAvailableCommands(
        {
          available_commands: [
            {
              name: "create_plan",
              input: Some(
                Known(CommandInputText({ hint: "What to plan?", .. }))
              ),
              ..
            },
            { name: "status", input: None, .. },
          ],
          ..
        }
      )
    ) else {
    fail("expected decoded commands with a text input and a null input")
  }
  // Unknown input kinds stay as raw payloads inside the command.
  let update = model_test_round_trip(
    "{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"draw\",\"description\":\"Draw\",\"input\":{\"type\":\"_ink\",\"strokes\":3}}]}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    update
    is Known(
      UpdateAvailableCommands(
        {
          available_commands: [{ input: Some(Extension(tag="_ink", ..)), .. }],
          ..
        }
      )
    ),
  )
  let future = experimental_v2_decode_session_update(
    experimental_v2_parse_json(
      "{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"speak\",\"description\":\"Speak\",\"input\":{\"type\":\"voice\",\"seconds\":5}}]}",
    ),
  )
  assert_true(
    future
    is Known(
      UpdateAvailableCommands(
        {
          available_commands: [{ input: Some(Future(tag="voice", ..)), .. }],
          ..
        }
      )
    ),
  )
  // The schema types command names as plain strings; the empty name stays
  // decodable instead of being treated as an identifier.
  let empty_name = model_test_round_trip(
    "{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"\",\"description\":\"anonymous\"}]}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    empty_name
    is Known(
      UpdateAvailableCommands({ available_commands: [{ name: "", .. }], .. })
    ),
  )
  try
    experimental_v2_decode_session_update(
      experimental_v2_parse_json(
        "{\"sessionUpdate\":\"available_commands_update\"}",
      ),
    )
  catch {
    MissingField(path="update.availableCommands") => ()
    _ => fail("expected MissingField for an absent command list")
  } noraise {
    _ => fail("expected MissingField for an absent command list")
  }
}

///|
test "v2 config option update round-trips the full option set" {
  let config = model_test_round_trip(
    "{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"type\":\"boolean\",\"configId\":\"verbose\",\"name\":\"Verbose\",\"currentValue\":true},{\"type\":\"select\",\"configId\":\"model\",\"name\":\"Model\",\"currentValue\":\"m1\",\"options\":[{\"value\":\"m1\",\"name\":\"M1\"}]}]}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    config
    is Known(
      UpdateConfigOptions(
        {
          config_options: [
            Known({ payload: PayloadBoolean({ current_value: true, }), .. }),
            Known({ payload: PayloadSelect(_), .. }),
          ],
          ..
        }
      )
    ),
  )
  // The schema puts no minItems on the option list; an empty replacement set
  // is a legal update.
  let emptied = model_test_round_trip(
    "{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[]}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(emptied is Known(UpdateConfigOptions({ config_options: [], .. })))
  try
    experimental_v2_decode_session_update(
      experimental_v2_parse_json("{\"sessionUpdate\":\"config_option_update\"}"),
    )
  catch {
    MissingField(path="update.configOptions") => ()
    _ => fail("expected MissingField for an absent config option list")
  } noraise {
    _ => fail("expected MissingField for an absent config option list")
  }
}

///|
test "v2 session info update applies field-level tri-state" {
  let partial = model_test_round_trip(
    "{\"sessionUpdate\":\"session_info_update\",\"title\":\"New title\"}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    partial
    is Known(
      UpdateSessionInfo(
        {
          title: PatchValue("New title"),
          updated_at: PatchOmitted,
          meta: PatchOmitted,
        }
      )
    ),
  )
  let cleared = model_test_round_trip(
    "{\"sessionUpdate\":\"session_info_update\",\"title\":null,\"updatedAt\":null,\"_meta\":null}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(
    cleared
    is Known(
      UpdateSessionInfo(
        { title: PatchNull, updated_at: PatchNull, meta: PatchNull, }
      )
    ),
  )
  try
    experimental_v2_decode_session_update(
      experimental_v2_parse_json(
        "{\"sessionUpdate\":\"session_info_update\",\"title\":5}",
      ),
    )
  catch {
    ExpectedString(path="update.title") => ()
    _ => fail("expected ExpectedString for a non-string title")
  } noraise {
    _ => fail("expected ExpectedString for a non-string title")
  }
}

///|
test "v2 usage update round-trips uint64 bounds and cost" {
  let usage = model_test_round_trip(
    "{\"sessionUpdate\":\"usage_update\",\"used\":18446744073709551615,\"size\":0,\"cost\":{\"amount\":1.5,\"currency\":\"USD\"}}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  guard usage is Known(UpdateUsage(update_value)) else {
    fail("expected a decoded usage update")
  }
  let max : UInt64 = 18446744073709551615UL
  assert_eq(update_value.used, max)
  assert_eq(update_value.size, 0UL)
  guard update_value.cost is Some(cost) else { fail("expected a decoded cost") }
  assert_eq(cost.amount, 1.5)
  assert_eq(cost.currency, "USD")
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_usage_update(update_value),
    ),
    "{\"used\":18446744073709551615,\"size\":0,\"cost\":{\"amount\":1.5,\"currency\":\"USD\"}}",
  )
  let bare = model_test_round_trip(
    "{\"sessionUpdate\":\"usage_update\",\"used\":12,\"size\":34}",
    value => experimental_v2_decode_session_update(value),
    experimental_v2_encode_session_update,
  )
  assert_true(bare is Known(UpdateUsage({ cost: None, .. })))
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"sessionUpdate\":\"usage_update\",\"used\":-1,\"size\":3}",
      InvalidField(
        path="update.used",
        reason="expected an unsigned 64-bit integer",
      ),
    ),
    (
      "{\"sessionUpdate\":\"usage_update\",\"used\":1.5,\"size\":3}",
      InvalidField(
        path="update.used",
        reason="expected an unsigned 64-bit integer",
      ),
    ),
    (
      "{\"sessionUpdate\":\"usage_update\",\"used\":1,\"size\":18446744073709551616}",
      InvalidField(
        path="update.size",
        reason="unsigned 64-bit integer out of range",
      ),
    ),
    (
      "{\"sessionUpdate\":\"usage_update\",\"used\":1,\"size\":2,\"cost\":{\"amount\":1.0,\"currency\":\"usd\"}}",
      InvalidField(
        path="update.cost.currency",
        reason="currency must be a 3-letter ISO 4217 code",
      ),
    ),
    (
      "{\"sessionUpdate\":\"usage_update\",\"used\":1}",
      MissingField(path="update.size"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_session_update(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed usage update")
    }
  }
}

///|
test "v2 unknown session update discriminator preserved raw" {
  for
    source in [
      "{\"sessionUpdate\":\"_agent_mood\",\"mood\":\"great\"}", "{\"sessionUpdate\":\"telemetry\",\"samples\":[]}",
    ] {
    let update = model_test_round_trip(
      source,
      value => experimental_v2_decode_session_update(value),
      experimental_v2_encode_session_update,
    )
    assert_eq(
      experimental_v2_encode_session_update(update),
      experimental_v2_parse_json(source),
    )
  }
  let extension = experimental_v2_decode_session_update(
    experimental_v2_parse_json(
      "{\"sessionUpdate\":\"_agent_mood\",\"mood\":\"great\"}",
    ),
  )
  assert_true(extension is Extension(tag="_agent_mood", ..))
  let future = experimental_v2_decode_session_update(
    experimental_v2_parse_json(
      "{\"sessionUpdate\":\"telemetry\",\"samples\":[]}",
    ),
  )
  assert_true(future is Future(tag="telemetry", ..))
  try
    experimental_v2_decode_session_update(
      experimental_v2_parse_json("{\"x\":1}"),
    )
  catch {
    MissingField(path="update.sessionUpdate") => ()
    _ => fail("expected MissingField for an absent discriminator")
  } noraise {
    _ => fail("expected MissingField for an absent discriminator")
  }
}

///|
test "v2 session update envelope requires sessionId and rejects unknowns" {
  let notification = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\",\"stopReason\":\"end_turn\"},\"_meta\":{\"n\":1}}",
    value => experimental_v2_decode_update_session_notification(value),
    experimental_v2_encode_update_session_notification,
  )
  assert_true(
    notification
    is {
      session_id: "s1",
      update: Known(
        UpdateState(
          Known(StateIdle({ stop_reason: Some(StopReasonEndTurn), .. }))
        )
      ),
      meta: Some(Object(_)),
    },
  )
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\"}}",
      MissingField(path="session/update.sessionId"),
    ),
    ("{\"sessionId\":\"s1\"}", MissingField(path="session/update.update")),
    (
      "{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\"},\"extra\":true}",
      UnknownField(path="session/update.extra"),
    ),
    (
      "{\"sessionId\":\"\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\"}}",
      InvalidField(
        path="session/update.sessionId",
        reason="id must not be empty",
      ),
    ),
    (
      "{\"sessionId\":\"s1\",\"update\":5}",
      ExpectedObject(path="session/update.update"),
    ),
    (
      "{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\"},\"_meta\":7}",
      InvalidField(
        path="session/update._meta",
        reason="_meta must be an object or null",
      ),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_update_session_notification(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ =>
        fail("expected a typed failure for a malformed session/update envelope")
    }
  }
  // Envelope _meta treats omission and null alike.
  for
    source in [
      "{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\"}}",
      "{\"sessionId\":\"s1\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"idle\"},\"_meta\":null}",
    ] {
    let notification = model_test_round_trip(
      source,
      value => experimental_v2_decode_update_session_notification(value),
      experimental_v2_encode_update_session_notification,
    )
    assert_true(notification.meta is None)
  }
}
