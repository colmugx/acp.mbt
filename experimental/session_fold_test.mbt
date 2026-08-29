///|
fn session_fold_test_text_block(text : String) -> ExperimentalV2ContentBlock {
  Known(BlockText({ text, annotations: None, meta: None, }))
}

///|
fn session_fold_test_chunk(
  message_id : String,
  text : String,
) -> ExperimentalV2ContentChunk {
  { message_id, content: session_fold_test_text_block(text), meta: None, }
}

///|
fn session_fold_test_upsert(
  message_id : String,
  content : ExperimentalV2Patch[Array[ExperimentalV2ContentBlock]],
) -> ExperimentalV2MessageUpsert {
  { message_id, content, meta: PatchOmitted, }
}

///|
fn session_fold_test_tool_call_update(
  tool_call_id : String,
) -> ExperimentalV2ToolCallUpdate {
  {
    tool_call_id,
    title: PatchOmitted,
    kind: PatchOmitted,
    status: PatchOmitted,
    content: PatchOmitted,
    locations: PatchOmitted,
    raw_input: PatchOmitted,
    raw_output: PatchOmitted,
    meta: PatchOmitted,
  }
}

///|
fn session_fold_test_tool_content(
  text : String,
) -> ExperimentalV2ToolCallContent {
  Known(
    ToolCallContentBlock({
      content: session_fold_test_text_block(text),
      meta: None,
    }),
  )
}

///|
fn session_fold_test_location(path : String) -> ExperimentalV2ToolCallLocation {
  { path, line: None, meta: None, }
}

///|
fn session_fold_test_plan_entry(
  content : String,
  status : ExperimentalV2PlanEntryStatus,
) -> ExperimentalV2PlanEntry {
  { content, priority: PlanPriorityHigh, status, meta: None, }
}

///|
fn session_fold_test_config_option(
  config_id : String,
  flag : Bool,
) -> ExperimentalV2SessionConfigOption {
  Known({
    config_id,
    name: "Option \{config_id}",
    description: None,
    category: None,
    payload: PayloadBoolean({ current_value: flag, }),
    meta: None,
  })
}

///|
fn session_fold_test_apply(
  state : ExperimentalV2SessionFold,
  update : ExperimentalV2SessionUpdate,
) -> ExperimentalV2SessionFold raise {
  match experimental_v2_session_fold_apply(state, update) {
    Ok(state) => state
    Err(_) => fail("expected update to apply")
  }
}

///|
fn session_fold_test_apply_all(
  state : ExperimentalV2SessionFold,
  updates : Array[ExperimentalV2SessionUpdate],
) -> ExperimentalV2SessionFold raise {
  let mut current = state
  for update in updates {
    current = session_fold_test_apply(current, update)
  }
  current
}

///|
test "v2 fold chunks aggregate per kind and message id without cross-kind merge" {
  let state = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    Known(UpdateUserMessageChunk(session_fold_test_chunk("m1", "Hello"))),
  )
  let state = session_fold_test_apply(
    state,
    Known(UpdateUserMessageChunk(session_fold_test_chunk("m1", " world"))),
  )
  let state = session_fold_test_apply(
    state,
    Known(UpdateUserMessageChunk(session_fold_test_chunk("m2", "next"))),
  )
  let state = session_fold_test_apply(
    state,
    Known(UpdateAgentMessageChunk(session_fold_test_chunk("m1", "answer"))),
  )
  let state = session_fold_test_apply(
    state,
    Known(UpdateAgentThoughtChunk(session_fold_test_chunk("m1", "reasoning"))),
  )
  assert_eq(state.user_messages, [
    {
      message_id: "m1",
      blocks: [
        session_fold_test_text_block("Hello"),
        session_fold_test_text_block(" world"),
      ],
      meta: None,
    },
    {
      message_id: "m2",
      blocks: [session_fold_test_text_block("next")],
      meta: None,
    },
  ])
  assert_eq(state.agent_messages, [
    {
      message_id: "m1",
      blocks: [session_fold_test_text_block("answer")],
      meta: None,
    },
  ])
  assert_eq(state.agent_thoughts, [
    {
      message_id: "m1",
      blocks: [session_fold_test_text_block("reasoning")],
      meta: None,
    },
  ])
}

///|
test "v2 fold message upsert applies exact tri-state content over chunks" {
  let chunked = session_fold_test_apply_all(
    experimental_v2_session_fold_new(),
    [
      Known(UpdateAgentMessageChunk(session_fold_test_chunk("a", "one"))),
      Known(UpdateAgentMessageChunk(session_fold_test_chunk("a", "two"))),
    ],
  )
  // Omitted keeps the chunk-accumulated blocks and patches only _meta.
  let omitted = session_fold_test_apply(
    chunked,
    Known(
      UpdateAgentMessage({
        message_id: "a",
        content: PatchOmitted,
        meta: PatchValue({ "k": Json::number(1.0) }),
      }),
    ),
  )
  assert_eq(omitted.agent_messages, [
    {
      message_id: "a",
      blocks: [
        session_fold_test_text_block("one"),
        session_fold_test_text_block("two"),
      ],
      meta: Some({ "k": Json::number(1.0) }),
    },
  ])
  // An array replaces the accumulated content wholesale, chunks included.
  let replaced = session_fold_test_apply(
    omitted,
    Known(
      UpdateAgentMessage(
        session_fold_test_upsert(
          "a",
          PatchValue([session_fold_test_text_block("whole")]),
        ),
      ),
    ),
  )
  assert_eq(replaced.agent_messages[0].blocks, [
    session_fold_test_text_block("whole"),
  ])
  // Later chunks append to the replacement content.
  let rechunkened = session_fold_test_apply(
    replaced,
    Known(UpdateAgentMessageChunk(session_fold_test_chunk("a", "tail"))),
  )
  assert_eq(rechunkened.agent_messages[0].blocks, [
    session_fold_test_text_block("whole"),
    session_fold_test_text_block("tail"),
  ])
  // Null clears; [] clears; both leave later chunks a fresh base.
  let nulled = session_fold_test_apply(
    rechunkened,
    Known(UpdateAgentMessage(session_fold_test_upsert("a", PatchNull))),
  )
  assert_eq(nulled.agent_messages[0].blocks, [])
  let emptied = session_fold_test_apply(
    rechunkened,
    Known(UpdateAgentMessage(session_fold_test_upsert("a", PatchValue([])))),
  )
  assert_eq(emptied.agent_messages[0].blocks, [])
  let restarted = session_fold_test_apply(
    nulled,
    Known(UpdateAgentMessageChunk(session_fold_test_chunk("a", "fresh"))),
  )
  assert_eq(restarted.agent_messages[0].blocks, [
    session_fold_test_text_block("fresh"),
  ])
  // A new messageId creates a message with omitted content as client default.
  let created = session_fold_test_apply(
    restarted,
    Known(
      UpdateUserMessage({
        message_id: "u1",
        content: PatchOmitted,
        meta: PatchNull,
      }),
    ),
  )
  assert_eq(created.user_messages, [
    { message_id: "u1", blocks: [], meta: None, },
  ])
  // A null _meta clears the slot back to None.
  let meta_cleared = session_fold_test_apply(
    omitted,
    Known(
      UpdateAgentMessage({
        message_id: "a",
        content: PatchOmitted,
        meta: PatchNull,
      }),
    ),
  )
  assert_eq(meta_cleared.agent_messages[0].meta, None)
}

///|
test "v2 fold tool call first update creates with defaults then patches" {
  let created = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        title: PatchValue("Run tests"),
      }),
    ),
  )
  assert_eq(created.tool_calls, [
    {
      tool_call_id: "call-1",
      title: PatchValue("Run tests"),
      kind: PatchOmitted,
      status: PatchOmitted,
      content: PatchOmitted,
      locations: PatchOmitted,
      raw_input: PatchOmitted,
      raw_output: PatchOmitted,
      meta: PatchOmitted,
    },
  ])
  let patched = session_fold_test_apply(
    created,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        kind: PatchValue(ToolKindExecute),
        status: PatchValue(ToolCallStatusInProgress),
        content: PatchValue([session_fold_test_tool_content("partial")]),
        locations: PatchValue([session_fold_test_location("/tmp/a.txt")]),
        raw_input: PatchValue({ "argv": Json::string("ls") }),
        raw_output: PatchValue(Json::null()),
        meta: PatchValue({ "k": Json::number(2.0) }),
      }),
    ),
  )
  assert_eq(patched.tool_calls[0], {
    tool_call_id: "call-1",
    title: PatchValue("Run tests"),
    kind: PatchValue(ToolKindExecute),
    status: PatchValue(ToolCallStatusInProgress),
    content: PatchValue([session_fold_test_tool_content("partial")]),
    locations: PatchValue([session_fold_test_location("/tmp/a.txt")]),
    raw_input: PatchValue({ "argv": Json::string("ls") }),
    raw_output: PatchValue(Json::null()),
    meta: PatchValue({ "k": Json::number(2.0) }),
  })
  // Omitted keeps every field; null clears title back to omitted; null and
  // [] both clear the content collection.
  let nulled = session_fold_test_apply(
    patched,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        title: PatchNull,
        content: PatchNull,
      }),
    ),
  )
  assert_eq(nulled.tool_calls[0].title, PatchOmitted)
  assert_eq(nulled.tool_calls[0].kind, PatchValue(ToolKindExecute))
  assert_eq(nulled.tool_calls[0].content, PatchOmitted)
  let emptied = session_fold_test_apply(
    patched,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        content: PatchValue([]),
      }),
    ),
  )
  assert_eq(emptied.tool_calls[0].content, PatchValue([]))
  // Chunks append single content items in received order, including after
  // a clear.
  let chunked = session_fold_test_apply_all(nulled, [
    Known(
      UpdateToolCallContentChunk({
        tool_call_id: "call-1",
        content: session_fold_test_tool_content("c1"),
        meta: None,
      }),
    ),
    Known(
      UpdateToolCallContentChunk({
        tool_call_id: "call-1",
        content: session_fold_test_tool_content("c2"),
        meta: None,
      }),
    ),
  ])
  assert_eq(
    chunked.tool_calls[0].content,
    PatchValue([
      session_fold_test_tool_content("c1"),
      session_fold_test_tool_content("c2"),
    ]),
  )
  // A whole-array update replaces chunk-accumulated content.
  let replaced = session_fold_test_apply(
    chunked,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        content: PatchValue([session_fold_test_tool_content("final")]),
      }),
    ),
  )
  assert_eq(
    replaced.tool_calls[0].content,
    PatchValue([session_fold_test_tool_content("final")]),
  )
  // A second tool call id stays independent.
  let second = session_fold_test_apply(
    replaced,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-2"),
        status: PatchValue(ToolCallStatusPending),
      }),
    ),
  )
  assert_eq(second.tool_calls.length(), 2)
  assert_eq(second.tool_calls[1].tool_call_id, "call-2")
  assert_eq(second.tool_calls[1].status, PatchValue(ToolCallStatusPending))
}

///|
test "v2 fold tool call content chunk before any update fails typed" {
  let state = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  let before = state
  match
    experimental_v2_session_fold_apply(
      state,
      Known(
        UpdateToolCallContentChunk({
          tool_call_id: "ghost",
          content: session_fold_test_tool_content("orphan"),
          meta: None,
        }),
      ),
    ) {
    Err(ChunkForUnknownToolCall(tool_call_id="ghost")) => ()
    Err(_) => fail("expected the unknown tool call chunk error")
    Ok(_) => fail("expected chunk before update to fail")
  }
  // The rejection leaves the input state untouched.
  assert_eq(state, before)
}

///|
test "v2 fold plan updates replace entries per plan id" {
  let first = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    Known(
      UpdatePlan({
        plan: Known(
          PlanItemsContent({
            plan_id: "p1",
            entries: [session_fold_test_plan_entry("a", PlanStatusPending)],
            meta: None,
          }),
        ),
        meta: None,
      }),
    ),
  )
  assert_eq(first.plans.length(), 1)
  assert_eq(first.plans[0].plan_id, "p1")
  assert_eq(first.plans[0].meta, None)
  assert_true(
    first.plans[0].content
    is Known(PlanItemsContent({ entries: [{ content: "a", .. }], .. })),
  )
  // The same planId replaces the whole entry list.
  let replaced = session_fold_test_apply(
    first,
    Known(
      UpdatePlan({
        plan: Known(
          PlanItemsContent({
            plan_id: "p1",
            entries: [
              session_fold_test_plan_entry("a", PlanStatusCompleted),
              session_fold_test_plan_entry("b", PlanStatusInProgress),
            ],
            meta: None,
          }),
        ),
        meta: None,
      }),
    ),
  )
  assert_eq(replaced.plans.length(), 1)
  assert_true(
    replaced.plans[0].content
    is Known(
      PlanItemsContent(
        {
          entries: [{ status: PlanStatusCompleted, .. }, { content: "b", .. }],
          ..
        }
      )
    ),
  )
  // A different planId tracks an independent plan; an empty entries list
  // replaces that plan with an empty one.
  let second = session_fold_test_apply(
    replaced,
    Known(
      UpdatePlan({
        plan: Known(
          PlanItemsContent({ plan_id: "p2", entries: [], meta: None, }),
        ),
        meta: None,
      }),
    ),
  )
  assert_eq(second.plans.length(), 2)
  assert_eq(second.plans[1].plan_id, "p2")
  assert_true(
    second.plans[1].content is Known(PlanItemsContent({ entries: [], .. })),
  )
  assert_true(
    second.plans[0].content
    is Known(PlanItemsContent({ entries: [{ content: "a", .. }, ..], .. })),
  )
}

///|
test "v2 fold unknown plan variant keys by raw planId and preserves bytes" {
  let update = experimental_v2_decode_session_update(
    experimental_v2_parse_json(
      "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"_kanban\",\"planId\":\"p3\",\"lanes\":[1]}}",
    ),
  )
  let state = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    update,
  )
  assert_eq(state.plans.length(), 1)
  assert_eq(state.plans[0].plan_id, "p3")
  assert_true(state.plans[0].content is Extension(tag="_kanban", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_plan_update_content(state.plans[0].content),
    ),
    "{\"type\":\"_kanban\",\"planId\":\"p3\",\"lanes\":[1]}",
  )
  // A later items update for the same id replaces the preserved variant.
  let replaced = session_fold_test_apply(
    state,
    Known(
      UpdatePlan({
        plan: Known(
          PlanItemsContent({
            plan_id: "p3",
            entries: [session_fold_test_plan_entry("x", PlanStatusPending)],
            meta: None,
          }),
        ),
        meta: None,
      }),
    ),
  )
  assert_true(
    replaced.plans[0].content
    is Known(PlanItemsContent({ entries: [{ content: "x", .. }], .. })),
  )
  // A raw variant without a planId violates the spec's MUST and fails
  // typed, for both a missing key and a non-string value.
  match
    experimental_v2_session_fold_apply(
      experimental_v2_session_fold_new(),
      experimental_v2_decode_session_update(
        experimental_v2_parse_json(
          "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"_gantt\",\"tasks\":[]}}",
        ),
      ),
    ) {
    Err(PlanVariantMissingPlanId) => ()
    Err(_) => fail("expected the plan variant error")
    Ok(_) => fail("expected raw plan without planId to fail")
  }
  match
    experimental_v2_session_fold_apply(
      experimental_v2_session_fold_new(),
      experimental_v2_decode_session_update(
        experimental_v2_parse_json(
          "{\"sessionUpdate\":\"plan_update\",\"plan\":{\"type\":\"future_board\",\"planId\":7}}",
        ),
      ),
    ) {
    Err(PlanVariantMissingPlanId) => ()
    Err(_) => fail("expected the plan variant error")
    Ok(_) => fail("expected non-string planId to fail")
  }
}

///|
test "v2 fold terminal upsert patches and output chunks store raw bytes" {
  let created = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    Known(
      UpdateTerminal({
        terminal_id: "t1",
        command: PatchValue("cargo test"),
        cwd: PatchValue("/home/user/project"),
        output: PatchOmitted,
        exit_status: PatchOmitted,
        meta: PatchOmitted,
      }),
    ),
  )
  assert_eq(created.terminals, [
    {
      terminal_id: "t1",
      command: PatchValue("cargo test"),
      cwd: PatchValue("/home/user/project"),
      output: PatchOmitted,
      exit_status: PatchOmitted,
      meta: PatchOmitted,
      output_chunks: [],
    },
  ])
  // Chunks append raw base64 data in received order.
  let chunked = session_fold_test_apply_all(created, [
    Known(
      UpdateTerminalOutputChunk({ terminal_id: "t1", data: "aGk=", meta: None, }),
    ),
    Known(
      UpdateTerminalOutputChunk({ terminal_id: "t1", data: "d29y", meta: None, }),
    ),
  ])
  assert_eq(chunked.terminals[0].output_chunks, ["aGk=", "d29y"])
  // A snapshot replaces the output slot without touching the chunk log.
  let snapshotted = session_fold_test_apply(
    chunked,
    Known(
      UpdateTerminal({
        terminal_id: "t1",
        command: PatchOmitted,
        cwd: PatchOmitted,
        output: PatchValue({ data: "aGk=", meta: None, }),
        exit_status: PatchValue({
          exit_code: Some(0),
          signal: None,
          meta: None,
        }),
        meta: PatchOmitted,
      }),
    ),
  )
  assert_eq(
    snapshotted.terminals[0].output,
    PatchValue({ data: "aGk=", meta: None, }),
  )
  assert_eq(snapshotted.terminals[0].output_chunks, ["aGk=", "d29y"])
  assert_eq(
    snapshotted.terminals[0].exit_status,
    PatchValue({ exit_code: Some(0), signal: None, meta: None, }),
  )
  // A null output clears the snapshot slot; the chunk log survives.
  let cleared = session_fold_test_apply(
    snapshotted,
    Known(
      UpdateTerminal({
        terminal_id: "t1",
        command: PatchNull,
        cwd: PatchOmitted,
        output: PatchNull,
        exit_status: PatchOmitted,
        meta: PatchOmitted,
      }),
    ),
  )
  assert_eq(cleared.terminals[0].output, PatchOmitted)
  assert_eq(cleared.terminals[0].command, PatchOmitted)
  assert_eq(cleared.terminals[0].output_chunks, ["aGk=", "d29y"])
  // A chunk for a first-seen terminalId creates it: the spec's terminals
  // rule retains state for ids whose updates arrive in any order.
  let first_seen = session_fold_test_apply(
    experimental_v2_session_fold_new(),
    Known(
      UpdateTerminalOutputChunk({
        terminal_id: "t2",
        data: "cGFzc2VkDQo=",
        meta: None,
      }),
    ),
  )
  assert_eq(first_seen.terminals, [
    {
      terminal_id: "t2",
      command: PatchOmitted,
      cwd: PatchOmitted,
      output: PatchOmitted,
      exit_status: PatchOmitted,
      meta: PatchOmitted,
      output_chunks: ["cGFzc2VkDQo="],
    },
  ])
}

///|
test "v2 fold lifecycle matrix records stop reason on idle only" {
  let fresh = experimental_v2_session_fold_new()
  assert_eq(fresh.phase, TurnIdle)
  assert_eq(fresh.stop_reason, None)
  // A turn starts on running and clears any previous stop reason.
  let running = session_fold_test_apply(
    fresh,
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  assert_eq(running.phase, TurnRunning)
  let blocked = session_fold_test_apply(
    running,
    Known(UpdateState(Known(StateRequiresAction({ meta: None, })))),
  )
  assert_eq(blocked.phase, TurnRequiresAction)
  let resumed = session_fold_test_apply(
    blocked,
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  assert_eq(resumed.phase, TurnRunning)
  let ended = session_fold_test_apply(
    resumed,
    Known(
      UpdateState(
        Known(StateIdle({ stop_reason: Some(StopReasonEndTurn), meta: None, })),
      ),
    ),
  )
  assert_eq(ended.phase, TurnIdle)
  assert_eq(ended.stop_reason, Some(StopReasonEndTurn))
  // A requires_action -> idle edge is the cancel-while-blocked path.
  let blocked_again = session_fold_test_apply(
    ended,
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  let cancelled_while_blocked = session_fold_test_apply(
    session_fold_test_apply(
      blocked_again,
      Known(UpdateState(Known(StateRequiresAction({ meta: None, })))),
    ),
    Known(
      UpdateState(
        Known(
          StateIdle({ stop_reason: Some(StopReasonCancelled), meta: None, }),
        ),
      ),
    ),
  )
  assert_eq(cancelled_while_blocked.phase, TurnIdle)
  assert_eq(cancelled_while_blocked.stop_reason, Some(StopReasonCancelled))
  // A new running turn clears the recorded stop reason; a later idle
  // without one overwrites it with None.
  let next_turn = session_fold_test_apply(
    cancelled_while_blocked,
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  assert_eq(next_turn.stop_reason, None)
  let idle_again = session_fold_test_apply(
    next_turn,
    Known(UpdateState(Known(StateIdle({ stop_reason: None, meta: None, })))),
  )
  assert_eq(idle_again.stop_reason, None)
  // Re-reporting the current phase stays legal; the idle -> requires_action
  // edge is the single typed rejection.
  let rerunning = session_fold_test_apply(
    idle_again,
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  let rerun = session_fold_test_apply(
    rerunning,
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
  )
  assert_eq(rerun.phase, TurnRunning)
  match
    experimental_v2_session_fold_apply(
      experimental_v2_session_fold_new(),
      Known(UpdateState(Known(StateRequiresAction({ meta: None, })))),
    ) {
    Err(IllegalStateTransition(from=TurnIdle, to=TurnRequiresAction)) => ()
    Err(_) => fail("expected the illegal transition error")
    Ok(_) => fail("expected idle -> requires_action to fail")
  }
}

///|
test "v2 fold cancel path keeps accepting updates until idle cancelled" {
  let state = session_fold_test_apply_all(experimental_v2_session_fold_new(), [
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        title: PatchValue("Long task"),
      }),
    ),
  ])
  // Updates after a cancel notification still fold; the fold learns about
  // the cancel only from the idle state update.
  let state = session_fold_test_apply(
    state,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        status: PatchValue(ToolCallStatusCancelled),
      }),
    ),
  )
  let state = session_fold_test_apply(
    state,
    Known(
      UpdateState(
        Known(
          StateIdle({ stop_reason: Some(StopReasonCancelled), meta: None, }),
        ),
      ),
    ),
  )
  assert_eq(state.phase, TurnIdle)
  assert_eq(state.stop_reason, Some(StopReasonCancelled))
  assert_eq(state.tool_calls.length(), 1)
  assert_eq(state.tool_calls[0].status, PatchValue(ToolCallStatusCancelled))
  // Background updates continue while idle and leave the phase alone.
  let state = session_fold_test_apply(
    state,
    Known(UpdateUsage({ used: 10UL, size: 100UL, cost: None, meta: None, })),
  )
  assert_eq(state.phase, TurnIdle)
  assert_eq(state.stop_reason, Some(StopReasonCancelled))
  assert_eq(
    state.usage,
    Some({ used: 10UL, size: 100UL, cost: None, meta: None, }),
  )
}

///|
test "v2 fold replacement sets and session info tri-state" {
  let fresh = experimental_v2_session_fold_new()
  assert_eq(fresh.config_options, None)
  assert_eq(fresh.available_commands, None)
  assert_eq(fresh.usage, None)
  assert_eq(fresh.session_title, None)
  assert_eq(fresh.session_updated_at, None)
  assert_eq(fresh.session_meta, None)
  let configured = session_fold_test_apply(
    fresh,
    Known(
      UpdateConfigOptions({
        config_options: [
          session_fold_test_config_option("model", true),
          session_fold_test_config_option("verbose", false),
        ],
        meta: None,
      }),
    ),
  )
  assert_eq(
    configured.config_options,
    Some([
      session_fold_test_config_option("model", true),
      session_fold_test_config_option("verbose", false),
    ]),
  )
  // A later update replaces the complete set.
  let reconfigured = session_fold_test_apply(
    configured,
    Known(
      UpdateConfigOptions({
        config_options: [session_fold_test_config_option("verbose", true)],
        meta: None,
      }),
    ),
  )
  assert_eq(
    reconfigured.config_options,
    Some([session_fold_test_config_option("verbose", true)]),
  )
  let commanded = session_fold_test_apply(
    reconfigured,
    Known(
      UpdateAvailableCommands({
        available_commands: [
          {
            name: "compact",
            description: "Compact history",
            input: None,
            meta: None,
          },
        ],
        meta: None,
      }),
    ),
  )
  assert_eq(
    commanded.available_commands,
    Some([
      {
        name: "compact",
        description: "Compact history",
        input: None,
        meta: None,
      },
    ]),
  )
  let recomanded = session_fold_test_apply(
    commanded,
    Known(UpdateAvailableCommands({ available_commands: [], meta: None, })),
  )
  assert_eq(recomanded.available_commands, Some([]))
  let used = session_fold_test_apply(
    recomanded,
    Known(
      UpdateUsage({
        used: 1024UL,
        size: 200000UL,
        cost: Some({ amount: 0.5, currency: "USD", meta: None, }),
        meta: None,
      }),
    ),
  )
  assert_eq(
    used.usage,
    Some({
      used: 1024UL,
      size: 200000UL,
      cost: Some({ amount: 0.5, currency: "USD", meta: None, }),
      meta: None,
    }),
  )
  let reused = session_fold_test_apply(
    used,
    Known(UpdateUsage({ used: 1UL, size: 2UL, cost: None, meta: None, })),
  )
  assert_eq(
    reused.usage,
    Some({ used: 1UL, size: 2UL, cost: None, meta: None, }),
  )
  // Session info patches each slot tri-state, independently.
  let titled = session_fold_test_apply(
    reused,
    Known(
      UpdateSessionInfo({
        title: PatchValue("Refactor"),
        updated_at: PatchValue("2026-08-18T10:00:00Z"),
        meta: PatchValue({ "rev": Json::number(3.0) }),
      }),
    ),
  )
  assert_eq(titled.session_title, Some("Refactor"))
  assert_eq(titled.session_updated_at, Some("2026-08-18T10:00:00Z"))
  assert_eq(titled.session_meta, Some({ "rev": Json::number(3.0) }))
  let retitled = session_fold_test_apply(
    titled,
    Known(
      UpdateSessionInfo({
        title: PatchValue("Refactor more"),
        updated_at: PatchOmitted,
        meta: PatchOmitted,
      }),
    ),
  )
  assert_eq(retitled.session_title, Some("Refactor more"))
  assert_eq(retitled.session_updated_at, Some("2026-08-18T10:00:00Z"))
  let cleared = session_fold_test_apply(
    retitled,
    Known(
      UpdateSessionInfo({
        title: PatchNull,
        updated_at: PatchNull,
        meta: PatchNull,
      }),
    ),
  )
  assert_eq(cleared.session_title, None)
  assert_eq(cleared.session_updated_at, None)
  assert_eq(cleared.session_meta, None)
}

///|
test "v2 fold unknown session updates are preserved raw and re-emittable" {
  let extension = experimental_v2_decode_session_update(
    experimental_v2_parse_json(
      "{\"sessionUpdate\":\"_custom\",\"payload\":true}",
    ),
  )
  let future = experimental_v2_decode_session_update(
    experimental_v2_parse_json("{\"sessionUpdate\":\"hologram\",\"x\":1}"),
  )
  let state = session_fold_test_apply_all(
    session_fold_test_apply(
      experimental_v2_session_fold_new(),
      Known(UpdateState(Known(StateRunning({ meta: None, })))),
    ),
    [extension, future],
  )
  assert_eq(state.preserved.length(), 2)
  assert_true(state.preserved[0] is Extension(tag="_custom", ..))
  assert_true(state.preserved[1] is Future(tag="hologram", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_session_update(state.preserved[0]),
    ),
    "{\"sessionUpdate\":\"_custom\",\"payload\":true}",
  )
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_session_update(state.preserved[1]),
    ),
    "{\"sessionUpdate\":\"hologram\",\"x\":1}",
  )
  assert_eq(state.phase, TurnRunning)
  assert_eq(state.user_messages.length(), 0)
}

///|
test "v2 fold unknown state update is preserved without moving the phase" {
  let update = experimental_v2_decode_session_update(
    experimental_v2_parse_json(
      "{\"sessionUpdate\":\"state_update\",\"state\":\"_paused\"}",
    ),
  )
  let state = session_fold_test_apply(
    session_fold_test_apply(
      experimental_v2_session_fold_new(),
      Known(UpdateState(Known(StateRunning({ meta: None, })))),
    ),
    update,
  )
  assert_eq(state.phase, TurnRunning)
  assert_eq(state.preserved.length(), 1)
  // The codec stores the nested unknown state without the outer tag and
  // re-stamps it on encode, so the preserved value re-emits with the same
  // fields in the codec's canonical order.
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_session_update(state.preserved[0]),
    ),
    "{\"state\":\"_paused\",\"sessionUpdate\":\"state_update\"}",
  )
}

///|
test "v2 fold apply is pure, deterministic, and leaves inputs untouched" {
  let update : ExperimentalV2SessionUpdate = Known(
    UpdateAgentMessageChunk(session_fold_test_chunk("m1", "hello")),
  )
  let fresh = experimental_v2_session_fold_new()
  let first = experimental_v2_session_fold_apply(fresh, update)
  let second = experimental_v2_session_fold_apply(fresh, update)
  assert_eq(first, second)
  assert_eq(fresh, experimental_v2_session_fold_new())
  let grown = session_fold_test_apply_all(fresh, [
    update,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        title: PatchValue("T"),
      }),
    ),
  ])
  // Re-applying the same updates on the original state reproduces the same
  // result without the earlier results interfering.
  let regrown = session_fold_test_apply_all(fresh, [
    update,
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        title: PatchValue("T"),
      }),
    ),
  ])
  assert_eq(grown, regrown)
  assert_eq(grown.agent_messages[0].blocks.length(), 1)
  // The input state of a successful step is unchanged after the step.
  let snapshot = grown
  let _ = session_fold_test_apply(
    grown,
    Known(
      UpdateToolCallContentChunk({
        tool_call_id: "call-1",
        content: session_fold_test_tool_content("more"),
        meta: None,
      }),
    ),
  )
  assert_eq(grown, snapshot)
  // A failing step leaves the input state untouched as well.
  match
    experimental_v2_session_fold_apply(
      grown,
      Known(
        UpdateToolCallContentChunk({
          tool_call_id: "ghost",
          content: session_fold_test_tool_content("x"),
          meta: None,
        }),
      ),
    ) {
    Err(ChunkForUnknownToolCall(tool_call_id="ghost")) => ()
    Err(_) => fail("expected the unknown tool call chunk error")
    Ok(_) => fail("expected unknown tool call chunk to fail")
  }
  assert_eq(grown, snapshot)
}

///|
test "v2 fold replay from start reproduces the live folded state" {
  let live_sequence : Array[ExperimentalV2SessionUpdate] = [
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
    Known(UpdateUserMessageChunk(session_fold_test_chunk("u1", "question"))),
    Known(
      UpdateAgentMessageChunk(session_fold_test_chunk("a1", "partial answer")),
    ),
    Known(
      UpdateToolCall({
        ..session_fold_test_tool_call_update("call-1"),
        title: PatchValue("Search"),
        status: PatchValue(ToolCallStatusInProgress),
      }),
    ),
    Known(UpdateState(Known(StateRequiresAction({ meta: None, })))),
    Known(UpdateState(Known(StateRunning({ meta: None, })))),
    Known(
      UpdatePlan({
        plan: Known(
          PlanItemsContent({
            plan_id: "p1",
            entries: [session_fold_test_plan_entry("step", PlanStatusCompleted)],
            meta: None,
          }),
        ),
        meta: None,
      }),
    ),
    Known(
      UpdateState(
        Known(StateIdle({ stop_reason: Some(StopReasonEndTurn), meta: None, })),
      ),
    ),
    Known(
      UpdateSessionInfo({
        title: PatchValue("Replayed"),
        updated_at: PatchOmitted,
        meta: PatchOmitted,
      }),
    ),
  ]
  let live = session_fold_test_apply_all(
    experimental_v2_session_fold_new(),
    live_sequence,
  )
  // Replay has no fold-specific mode: the same update sequence applied to a
  // fresh fold reproduces the live state exactly.
  let replayed = session_fold_test_apply_all(
    experimental_v2_session_fold_new(),
    live_sequence,
  )
  assert_eq(replayed, live)
  assert_eq(replayed.phase, TurnIdle)
  assert_eq(replayed.stop_reason, Some(StopReasonEndTurn))
  assert_eq(replayed.session_title, Some("Replayed"))
}
