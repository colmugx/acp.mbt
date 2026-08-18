///|
/// Phase of one session's foreground-work lifecycle as reported by
/// `state_update` notifications.  `TurnIdle` is the initial phase: a fresh
/// session has no foreground work, and the first `running` report starts a
/// turn without the fold needing the prompt request that caused it.
pub(all) enum ExperimentalV2TurnPhase {
  TurnIdle
  TurnRunning
  TurnRequiresAction
} derive(Eq, Debug)

///|
/// Structured failures raised while folding typed v2 session updates into
/// consumer state.  These are consumer-side aggregation failures, not wire
/// decode failures: a typed update that reaches the fold already decoded
/// cleanly.
pub(all) suberror ExperimentalV2SessionFoldError {
  ChunkForUnknownToolCall(tool_call_id~ : String)
  IllegalStateTransition(
    from~ : ExperimentalV2TurnPhase,
    to~ : ExperimentalV2TurnPhase
  )
  PlanVariantMissingPlanId
} derive(Eq, Debug)

///|
/// One message aggregated from content chunks and whole-message upserts.
/// Chunk `_meta` is chunk-scoped and never folded; only upsert `_meta`
/// patches the `meta` slot.
pub(all) struct ExperimentalV2FoldedMessage {
  message_id : String
  blocks : Array[ExperimentalV2ContentBlock]
  meta : Json?
} derive(Eq, Debug)

///|
/// One tool call aggregated from `tool_call_update` upserts and
/// `tool_call_content_chunk` appends.  Every field keeps the applied result
/// of the tri-state patches: `PatchOmitted` is both the first-update client
/// default and the state a `null` clear returns to, so an unset or cleared
/// field is never fabricated into a placeholder value.
pub(all) struct ExperimentalV2FoldedToolCall {
  tool_call_id : String
  title : ExperimentalV2Patch[String]
  kind : ExperimentalV2Patch[ExperimentalV2ToolKind]
  status : ExperimentalV2Patch[ExperimentalV2ToolCallStatus]
  content : ExperimentalV2Patch[Array[ExperimentalV2ToolCallContent]]
  locations : ExperimentalV2Patch[Array[ExperimentalV2ToolCallLocation]]
  raw_input : ExperimentalV2Patch[Json]
  raw_output : ExperimentalV2Patch[Json]
  meta : ExperimentalV2Patch[Json]
} derive(Eq, Debug)

///|
/// One agent-owned terminal aggregated from `terminal_update` upserts and
/// `terminal_output_chunk` appends.  `output_chunks` stores the raw base64
/// `data` strings in arrival order: each chunk is independently encoded and
/// may split UTF-8 code points or ANSI sequences, so the fold never
/// concatenates or decodes them.  `output` is the upsert snapshot slot — the
/// agent's authoritative byte replacement — and is kept separate from the
/// chunk log; a consumer renders the latest snapshot when present and
/// otherwise decodes each chunk separately.
pub(all) struct ExperimentalV2FoldedTerminal {
  terminal_id : String
  command : ExperimentalV2Patch[String]
  cwd : ExperimentalV2Patch[String]
  output : ExperimentalV2Patch[ExperimentalV2TerminalOutput]
  exit_status : ExperimentalV2Patch[ExperimentalV2TerminalExitStatus]
  meta : ExperimentalV2Patch[Json]
  output_chunks : Array[String]
} derive(Eq, Debug)

///|
/// One plan keyed by its `planId`.  Each `plan_update` replaces the whole
/// folded plan for that id; the spec mandates every plan content variant,
/// including custom or future ones, carries a `planId`, so even preserved
/// raw variants are keyed and replace by id.
pub(all) struct ExperimentalV2FoldedPlan {
  plan_id : String
  content : ExperimentalV2PlanUpdateContent
  meta : Json?
} derive(Eq, Debug)

///|
/// Pure per-session consumer state for a stream of typed v2 session
/// updates.  Same discipline as the v1 consumer fold: a pure function of
/// `(state, update)` that allocates the next state without mutating the
/// input, with no registry and no global state.  One session owns one fold
/// value; the fold consumes typed `session/update` payloads only — prompt
/// request/response acceptance is outside it, and a caller that wants a
/// running baseline simply applies the `state_update`s as they arrive.
///
/// Replay needs no special mode: the pinned schema's `replayFrom` carries
/// only a `start` cursor with no fold-relevant boundary information, so
/// replaying a resumed session is applying the replayed update sequence
/// from a fresh fold value.
///
/// Lifecycle: `stop_reason` is carried only by the `idle` state update (the
/// running and requires-action payloads have no such field, so a stop
/// reason on a non-idle state is structurally unreceivable).  Recording an
/// idle transition overwrites the previous stop reason; a new `running`
/// turn clears it, since the reason describes the foreground work that just
/// ended.  Background updates MAY continue while idle and are accepted
/// without moving the phase.  `session/cancel` itself is transport-level;
/// the fold observes cancellation only when the `idle` state update with
/// the `cancelled` stop reason arrives, and keeps accepting tool call and
/// other updates until then, as the spec's cancel sequence requires.
pub(all) struct ExperimentalV2SessionFold {
  phase : ExperimentalV2TurnPhase
  stop_reason : ExperimentalV2StopReason?
  user_messages : Array[ExperimentalV2FoldedMessage]
  agent_messages : Array[ExperimentalV2FoldedMessage]
  agent_thoughts : Array[ExperimentalV2FoldedMessage]
  tool_calls : Array[ExperimentalV2FoldedToolCall]
  terminals : Array[ExperimentalV2FoldedTerminal]
  plans : Array[ExperimentalV2FoldedPlan]
  config_options : Array[ExperimentalV2SessionConfigOption]?
  available_commands : Array[ExperimentalV2AvailableCommand]?
  session_title : String?
  session_updated_at : String?
  session_meta : Json?
  usage : ExperimentalV2UsageUpdate?
  preserved : Array[ExperimentalV2SessionUpdate]
} derive(Eq, Debug)

///|
/// The initial consumer state for one session: idle, nothing reported yet.
pub fn experimental_v2_session_fold_new() -> ExperimentalV2SessionFold {
  {
    phase: TurnIdle,
    stop_reason: None,
    user_messages: [],
    agent_messages: [],
    agent_thoughts: [],
    tool_calls: [],
    terminals: [],
    plans: [],
    config_options: None,
    available_commands: None,
    session_title: None,
    session_updated_at: None,
    session_meta: None,
    usage: None,
    preserved: [],
  }
}

///|
/// Apply one patch tri-state to a patch slot: omitted keeps, null clears
/// back to omitted, a value replaces.
fn[T] experimental_v2_fold_patch(
  current : ExperimentalV2Patch[T],
  patch : ExperimentalV2Patch[T],
) -> ExperimentalV2Patch[T] {
  match patch {
    PatchOmitted => current
    PatchNull => PatchOmitted
    PatchValue(_) => patch
  }
}

///|
/// Patch application for collection slots: like
/// `experimental_v2_fold_patch` but a replaced array is copied so the fold
/// never aliases an array the update value still holds.
fn[T] experimental_v2_fold_patch_collection(
  current : ExperimentalV2Patch[Array[T]],
  patch : ExperimentalV2Patch[Array[T]],
) -> ExperimentalV2Patch[Array[T]] {
  match patch {
    PatchOmitted => current
    PatchNull => PatchOmitted
    PatchValue(values) => PatchValue(values.copy())
  }
}

///|
/// Patch application for optional slots (message `meta`, session
/// `title`/`updatedAt`/`_meta`): omitted keeps, null clears to `None`, a
/// value sets.
fn[T] experimental_v2_fold_patch_slot(
  current : T?,
  patch : ExperimentalV2Patch[T],
) -> T? {
  match patch {
    PatchOmitted => current
    PatchNull => None
    PatchValue(value) => Some(value)
  }
}

///|
/// Locate a folded message by id within one kind bucket.
fn experimental_v2_fold_message_index(
  messages : Array[ExperimentalV2FoldedMessage],
  message_id : String,
) -> Int? {
  for index, message in messages {
    if message.message_id == message_id {
      return Some(index)
    }
  }
  None
}

///|
/// Append one content chunk: chunks with the same `messageId` append in
/// arrival order, and a new `messageId` starts a new message.
fn experimental_v2_fold_message_chunk(
  messages : Array[ExperimentalV2FoldedMessage],
  chunk : ExperimentalV2ContentChunk,
) -> Array[ExperimentalV2FoldedMessage] {
  let next = messages.copy()
  match experimental_v2_fold_message_index(next, chunk.message_id) {
    Some(index) => {
      let message = next[index]
      let blocks = message.blocks.copy()
      blocks.push(chunk.content)
      next[index] = { ..message, blocks, }
    }
    None =>
      next.push({
        message_id: chunk.message_id,
        blocks: [chunk.content],
        meta: None,
      })
  }
  next
}

///|
/// Apply one whole-message upsert: a new `messageId` creates the message
/// with omitted fields as client defaults; an existing id patches it, where
/// `content` omitted keeps the accumulated blocks and `null` or an array
/// replaces them wholesale, including content accumulated from earlier
/// chunks.
fn experimental_v2_fold_message_upsert(
  messages : Array[ExperimentalV2FoldedMessage],
  upsert : ExperimentalV2MessageUpsert,
) -> Array[ExperimentalV2FoldedMessage] {
  let next = messages.copy()
  match experimental_v2_fold_message_index(next, upsert.message_id) {
    Some(index) => {
      let message = next[index]
      let blocks = match upsert.content {
        PatchOmitted => message.blocks
        PatchNull => []
        PatchValue(values) => values.copy()
      }
      next[index] = {
        ..message,
        blocks,
        meta: experimental_v2_fold_patch_slot(message.meta, upsert.meta),
      }
    }
    None => {
      let blocks = match upsert.content {
        PatchValue(values) => values.copy()
        PatchOmitted | PatchNull => []
      }
      next.push({
        message_id: upsert.message_id,
        blocks,
        meta: experimental_v2_fold_patch_slot(None, upsert.meta),
      })
    }
  }
  next
}

///|
/// Locate a folded tool call by id.
fn experimental_v2_fold_tool_call_index(
  calls : Array[ExperimentalV2FoldedToolCall],
  tool_call_id : String,
) -> Int? {
  for index, call in calls {
    if call.tool_call_id == tool_call_id {
      return Some(index)
    }
  }
  None
}

///|
/// First-update defaults for a tool call: every patchable field starts
/// omitted, the spec's "client defaults" for unseen fields.
fn experimental_v2_fold_tool_call_defaults(
  tool_call_id : String,
) -> ExperimentalV2FoldedToolCall {
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
/// Apply one tool call upsert's patches field by field.
fn experimental_v2_fold_tool_call_patch(
  call : ExperimentalV2FoldedToolCall,
  update : ExperimentalV2ToolCallUpdate,
) -> ExperimentalV2FoldedToolCall {
  {
    tool_call_id: call.tool_call_id,
    title: experimental_v2_fold_patch(call.title, update.title),
    kind: experimental_v2_fold_patch(call.kind, update.kind),
    status: experimental_v2_fold_patch(call.status, update.status),
    content: experimental_v2_fold_patch_collection(call.content, update.content),
    locations: experimental_v2_fold_patch_collection(
      call.locations,
      update.locations,
    ),
    raw_input: experimental_v2_fold_patch(call.raw_input, update.raw_input),
    raw_output: experimental_v2_fold_patch(call.raw_output, update.raw_output),
    meta: experimental_v2_fold_patch(call.meta, update.meta),
  }
}

///|
/// Apply one tool call upsert: the first update for an id creates the call
/// with defaults, later updates patch it — the spec's upsert rule, so no
/// duplicate-id rejection exists in v2.
fn experimental_v2_fold_tool_call_upsert(
  calls : Array[ExperimentalV2FoldedToolCall],
  update : ExperimentalV2ToolCallUpdate,
) -> Array[ExperimentalV2FoldedToolCall] {
  let next = calls.copy()
  match experimental_v2_fold_tool_call_index(next, update.tool_call_id) {
    Some(index) =>
      next[index] = experimental_v2_fold_tool_call_patch(next[index], update)
    None =>
      next.push(
        experimental_v2_fold_tool_call_patch(
          experimental_v2_fold_tool_call_defaults(update.tool_call_id),
          update,
        ),
      )
  }
  next
}

///|
/// Append one tool call content chunk.  The spec grants first-seen creation
/// only to `tool_call_update` ("for a new `toolCallId`, omitted fields use
/// client defaults") and, for terminals, to any first-seen id; a chunk for
/// a tool call no update ever created has no creation rule, so it is a
/// typed failure instead of an implicit fabrication.
fn experimental_v2_fold_tool_call_chunk(
  state : ExperimentalV2SessionFold,
  chunk : ExperimentalV2ToolCallContentChunk,
) -> Result[ExperimentalV2SessionFold, ExperimentalV2SessionFoldError] {
  match
    experimental_v2_fold_tool_call_index(state.tool_calls, chunk.tool_call_id) {
    Some(index) => {
      let calls = state.tool_calls.copy()
      let call = calls[index]
      let content = match call.content {
        PatchValue(items) => {
          let appended = items.copy()
          appended.push(chunk.content)
          PatchValue(appended)
        }
        PatchOmitted | PatchNull => PatchValue([chunk.content])
      }
      calls[index] = { ..call, content, }
      Ok({ ..state, tool_calls: calls })
    }
    None => Err(ChunkForUnknownToolCall(tool_call_id=chunk.tool_call_id))
  }
}

///|
/// Locate a folded terminal by id.
fn experimental_v2_fold_terminal_index(
  terminals : Array[ExperimentalV2FoldedTerminal],
  terminal_id : String,
) -> Int? {
  for index, terminal in terminals {
    if terminal.terminal_id == terminal_id {
      return Some(index)
    }
  }
  None
}

///|
/// First-seen defaults for a terminal: patchable fields start unknown and
/// the output chunk log starts empty.
fn experimental_v2_fold_terminal_defaults(
  terminal_id : String,
) -> ExperimentalV2FoldedTerminal {
  {
    terminal_id,
    command: PatchOmitted,
    cwd: PatchOmitted,
    output: PatchOmitted,
    exit_status: PatchOmitted,
    meta: PatchOmitted,
    output_chunks: [],
  }
}

///|
/// Apply one terminal upsert's patches field by field; the chunk log is
/// untouched by upserts.
fn experimental_v2_fold_terminal_patch(
  terminal : ExperimentalV2FoldedTerminal,
  update : ExperimentalV2TerminalUpdate,
) -> ExperimentalV2FoldedTerminal {
  {
    ..terminal,
    command: experimental_v2_fold_patch(terminal.command, update.command),
    cwd: experimental_v2_fold_patch(terminal.cwd, update.cwd),
    output: experimental_v2_fold_patch(terminal.output, update.output),
    exit_status: experimental_v2_fold_patch(
      terminal.exit_status,
      update.exit_status,
    ),
    meta: experimental_v2_fold_patch(terminal.meta, update.meta),
  }
}

///|
/// Apply one terminal upsert: a new id creates the terminal with unknown
/// fields, an existing id patches it.
fn experimental_v2_fold_terminal_upsert(
  terminals : Array[ExperimentalV2FoldedTerminal],
  update : ExperimentalV2TerminalUpdate,
) -> Array[ExperimentalV2FoldedTerminal] {
  let next = terminals.copy()
  match experimental_v2_fold_terminal_index(next, update.terminal_id) {
    Some(index) =>
      next[index] = experimental_v2_fold_terminal_patch(next[index], update)
    None =>
      next.push(
        experimental_v2_fold_terminal_patch(
          experimental_v2_fold_terminal_defaults(update.terminal_id),
          update,
        ),
      )
  }
  next
}

///|
/// Append one terminal output chunk, storing the raw base64 `data` string
/// in arrival order.  Unlike tool calls, the spec's terminal rule — clients
/// retain state for a first-seen `terminalId` because references and
/// session updates may arrive in either order — lets a chunk create the
/// terminal.
fn experimental_v2_fold_terminal_chunk(
  state : ExperimentalV2SessionFold,
  chunk : ExperimentalV2TerminalOutputChunk,
) -> Result[ExperimentalV2SessionFold, ExperimentalV2SessionFoldError] {
  let terminals = state.terminals.copy()
  match experimental_v2_fold_terminal_index(terminals, chunk.terminal_id) {
    Some(index) => {
      let terminal = terminals[index]
      let output_chunks = terminal.output_chunks.copy()
      output_chunks.push(chunk.data)
      terminals[index] = { ..terminal, output_chunks, }
      Ok({ ..state, terminals, })
    }
    None => {
      let terminal = experimental_v2_fold_terminal_defaults(chunk.terminal_id)
      terminals.push({ ..terminal, output_chunks: [chunk.data] })
      Ok({ ..state, terminals, })
    }
  }
}

///|
/// Locate a folded plan by id.
fn experimental_v2_fold_plan_index(
  plans : Array[ExperimentalV2FoldedPlan],
  plan_id : String,
) -> Int? {
  for index, plan in plans {
    if plan.plan_id == plan_id {
      return Some(index)
    }
  }
  None
}

///|
/// Read the spec-mandated `planId` out of a preserved raw plan variant.
/// Every plan content variant MUST carry a `planId`; a raw payload without
/// a non-empty string one violates that rule and fails typed.
fn experimental_v2_fold_raw_plan_id(
  raw : Json,
) -> Result[String, ExperimentalV2SessionFoldError] {
  match raw {
    Object(fields) =>
      match fields.get("planId") {
        Some(String(plan_id)) =>
          if plan_id == "" {
            Err(PlanVariantMissingPlanId)
          } else {
            Ok(plan_id)
          }
        _ => Err(PlanVariantMissingPlanId)
      }
    _ => Err(PlanVariantMissingPlanId)
  }
}

///|
/// Apply one plan update: replace the whole folded plan for its id, keeping
/// known `items` and preserved raw variants in the same id-keyed store.
fn experimental_v2_fold_plan_update(
  state : ExperimentalV2SessionFold,
  update : ExperimentalV2PlanUpdate,
) -> Result[ExperimentalV2SessionFold, ExperimentalV2SessionFoldError] {
  let keyed = match update.plan {
    Known(PlanItemsContent(items)) => Ok(items.plan_id)
    Extension(tag~, raw~) | Future(tag~, raw~) => {
      ignore(tag)
      experimental_v2_fold_raw_plan_id(raw)
    }
  }
  match keyed {
    Err(error) => Err(error)
    Ok(plan_id) => {
      let plans = state.plans.copy()
      let folded : ExperimentalV2FoldedPlan = {
        plan_id,
        content: update.plan,
        meta: update.meta,
      }
      match experimental_v2_fold_plan_index(plans, plan_id) {
        Some(index) => plans[index] = folded
        None => plans.push(folded)
      }
      Ok({ ..state, plans, })
    }
  }
}

///|
/// Apply one state update to the lifecycle.  The single rejected edge is
/// `idle` → `requires_action`: the spec situates every blocked report
/// between running reports, so a blocked state without foreground work is
/// groundless.  Re-reporting the current phase stays legal because the
/// spec's MUST/SHOULD wording never forbids it, and rejecting it would
/// break replay of agents that re-send a state.
fn experimental_v2_fold_state_update(
  state : ExperimentalV2SessionFold,
  state_update : ExperimentalV2StateUpdate,
) -> Result[ExperimentalV2SessionFold, ExperimentalV2SessionFoldError] {
  match state_update {
    Known(StateRunning(_)) =>
      Ok({ ..state, phase: TurnRunning, stop_reason: None })
    Known(StateRequiresAction(_)) =>
      if state.phase is TurnIdle {
        Err(IllegalStateTransition(from=state.phase, to=TurnRequiresAction))
      } else {
        Ok({ ..state, phase: TurnRequiresAction })
      }
    Known(StateIdle(idle)) =>
      Ok({ ..state, phase: TurnIdle, stop_reason: idle.stop_reason })
    Extension(..) | Future(..) => {
      // An unknown state cannot move the lifecycle; preserve the whole
      // update for replay and proxying.
      let preserved = state.preserved.copy()
      preserved.push(Known(UpdateState(state_update)))
      Ok({ ..state, preserved, })
    }
  }
}

///|
/// Apply one typed session update to consumer state, returning either the
/// next state or a typed rejection.  The input state is never mutated, so a
/// caller that keeps the previous value still observes it unchanged after a
/// rejection.  Unknown `sessionUpdate` arms are never errors: the spec's
/// preserve rule keeps them raw in `preserved` for replay and proxying.
pub fn experimental_v2_session_fold_apply(
  state : ExperimentalV2SessionFold,
  update : ExperimentalV2SessionUpdate,
) -> Result[ExperimentalV2SessionFold, ExperimentalV2SessionFoldError] {
  match update {
    Known(UpdateUserMessageChunk(chunk)) =>
      Ok({
        ..state,
        user_messages: experimental_v2_fold_message_chunk(
          state.user_messages,
          chunk,
        ),
      })
    Known(UpdateUserMessage(upsert)) =>
      Ok({
        ..state,
        user_messages: experimental_v2_fold_message_upsert(
          state.user_messages,
          upsert,
        ),
      })
    Known(UpdateAgentMessageChunk(chunk)) =>
      Ok({
        ..state,
        agent_messages: experimental_v2_fold_message_chunk(
          state.agent_messages,
          chunk,
        ),
      })
    Known(UpdateAgentMessage(upsert)) =>
      Ok({
        ..state,
        agent_messages: experimental_v2_fold_message_upsert(
          state.agent_messages,
          upsert,
        ),
      })
    Known(UpdateAgentThoughtChunk(chunk)) =>
      Ok({
        ..state,
        agent_thoughts: experimental_v2_fold_message_chunk(
          state.agent_thoughts,
          chunk,
        ),
      })
    Known(UpdateAgentThought(upsert)) =>
      Ok({
        ..state,
        agent_thoughts: experimental_v2_fold_message_upsert(
          state.agent_thoughts,
          upsert,
        ),
      })
    Known(UpdateState(state_update)) =>
      experimental_v2_fold_state_update(state, state_update)
    Known(UpdateToolCallContentChunk(chunk)) =>
      experimental_v2_fold_tool_call_chunk(state, chunk)
    Known(UpdateToolCall(update)) =>
      Ok({
        ..state,
        tool_calls: experimental_v2_fold_tool_call_upsert(
          state.tool_calls,
          update,
        ),
      })
    Known(UpdateTerminal(update)) =>
      Ok({
        ..state,
        terminals: experimental_v2_fold_terminal_upsert(state.terminals, update),
      })
    Known(UpdateTerminalOutputChunk(chunk)) =>
      experimental_v2_fold_terminal_chunk(state, chunk)
    Known(UpdatePlan(update)) => experimental_v2_fold_plan_update(state, update)
    Known(UpdateAvailableCommands(update)) =>
      Ok({ ..state, available_commands: Some(update.available_commands.copy()) })
    Known(UpdateConfigOptions(update)) =>
      Ok({ ..state, config_options: Some(update.config_options.copy()) })
    Known(UpdateSessionInfo(update)) =>
      Ok({
        ..state,
        session_title: experimental_v2_fold_patch_slot(
          state.session_title,
          update.title,
        ),
        session_updated_at: experimental_v2_fold_patch_slot(
          state.session_updated_at,
          update.updated_at,
        ),
        session_meta: experimental_v2_fold_patch_slot(
          state.session_meta,
          update.meta,
        ),
      })
    Known(UpdateUsage(update)) => Ok({ ..state, usage: Some(update) })
    Extension(..) | Future(..) => {
      let preserved = state.preserved.copy()
      preserved.push(update)
      Ok({ ..state, preserved, })
    }
  }
}
