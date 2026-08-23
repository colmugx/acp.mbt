///|
/// In-repo MoonBit v2 agent fixture for the experimental stdio interop proof.
///
/// Built by `tests/interop/v2` with `moon build` into a test-local target
/// directory and spawned as a real child process.  It serves one scripted ACP
/// v2 Draft agent over its own process stdio with
/// `experimental_v2_agent_serve_stdio_with_outbound`, so every streamed
/// `session/update`, the `session/request_permission` reverse request, and
/// each reply crosses the real v2 engine, pipes, and newline framing.
/// `batch=true` wires `experimental_v2_batch_expanding_ports` around this
/// process's stdin reader, so an inbound v2 batch frame is expanded into
/// single-object frames before the engine's object-only decode while lone
/// frames pass through byte-exact.
///
/// Modes (first CLI argument):
/// - `serve`: initialize (protocol pin 2) -> session/new -> one prompt that
///   streams a user-message upsert, two agent-message chunks sharing one
///   `messageId`, a tool-call create, `state_update running`, then one
///   two-option `session/request_permission` round-trip whose selected option
///   id is echoed both into the completing tool-call patch's `rawOutput` and
///   the final prompt result `_meta`, then `state_update idle` with
///   `stopReason end_turn`.  `session/list` answers one canned session and a
///   late `$/cancel_request` is tolerated by the engine's best-effort cancel.
/// - `die`: the identical streamed turn and permission round-trip, then the
///   process terminates itself mid-prompt through libc `exit` — unlike a
///   panic it writes nothing to stdout, so the child's stdout stays pure
///   frames up to the last complete write.
async fn main {
  let mode = interop_v2_fixture_mode()
  let endpoint = interop_v2_fixture_endpoint(mode)
  @v2.experimental_v2_agent_serve_stdio_with_outbound(
    endpoint~,
    context_factory=channel => {
      @v2.experimental_v2_agent_context_over_channel(channel~)
    },
    initial_state=interop_v2_fixture_state(endpoint),
    trace=_ => (),
    batch=true,
  )
}

///|
/// Immediate process termination without unwinding and without touching
/// stdout or stderr.  `abort` is deliberately not used: the native runtime
/// prints panic output on stdout, which would corrupt the ACP frame stream
/// the interop test is proving pure.
extern "c" fn interop_v2_fixture_exit(code : Int) = "exit"

///|
fn interop_v2_fixture_mode() -> String {
  match @env.args() {
    [_, mode] => mode
    _ =>
      abort(
        "v2 interop fixture: expected exactly one mode argument (serve|die)",
      )
  }
}

///|
fn interop_v2_fixture_capabilities() -> @v2.ExperimentalV2AgentCapabilities {
  {
    session: MarkerSupported({
      prompt: MarkerSupported({
        image: MarkerUnsupported,
        audio: MarkerUnsupported,
        embedded_context: MarkerUnsupported,
        meta: None,
      }),
      mcp: MarkerUnsupported,
      delete: MarkerUnsupported,
      additional_directories: MarkerUnsupported,
      meta: None,
    }),
    auth: MarkerUnsupported,
    meta: None,
  }
}

///|
fn interop_v2_fixture_endpoint(
  mode : String,
) -> @v2.ExperimentalV2AgentEndpoint {
  let spec = try! @v2.experimental_v2_agent_spec(
    info={
      name: "v2-interop-fixture-agent",
      title: None,
      version: "fixture",
      meta: None,
    },
    capabilities=interop_v2_fixture_capabilities(),
    sessions=@v2.experimental_v2_agent_session_service(
      new_session=interop_v2_fixture_new_session,
      list=interop_v2_fixture_list_sessions,
      resume_session=interop_v2_fixture_resume_session,
      close=interop_v2_fixture_close_session,
      prompt=interop_v2_fixture_prompt(mode),
      set_config_option=interop_v2_fixture_set_config_option,
    ),
  )
  @v2.experimental_v2_agent_endpoint_from_spec(spec)
}

///|
fn interop_v2_fixture_state(
  endpoint : @v2.ExperimentalV2AgentEndpoint,
) -> @v2.ExperimentalV2AgentAdapterState {
  @v2.experimental_v2_agent_adapter_state_new(
    protocol=try! @v2.experimental_v2_agent_state_new(config=endpoint.config()),
  )
}

///|
async fn interop_v2_fixture_new_session(
  _context : @v2.ExperimentalV2AgentContext,
  _params : @v2.ExperimentalV2NewSessionParams,
) -> @v2.ExperimentalV2NewSessionResult {
  @async.pause()
  { session_id: "interop-session", config_options: None, meta: None }
}

///|
async fn interop_v2_fixture_list_sessions(
  _context : @v2.ExperimentalV2AgentContext,
  _params : @v2.ExperimentalV2ListSessionsParams,
) -> @v2.ExperimentalV2ListSessionsResult {
  @async.pause()
  {
    sessions: [
      {
        session_id: "interop-session",
        cwd: "/",
        additional_directories: None,
        title: Some("Interop fixture session"),
        updated_at: None,
        meta: None,
      },
    ],
    next_cursor: None,
    meta: None,
  }
}

///|
async fn interop_v2_fixture_resume_session(
  _context : @v2.ExperimentalV2AgentContext,
  _params : @v2.ExperimentalV2ResumeSessionParams,
) -> @v2.ExperimentalV2ResumeSessionResult {
  @async.pause()
  { config_options: None, meta: None }
}

///|
async fn interop_v2_fixture_close_session(
  _context : @v2.ExperimentalV2AgentContext,
  _params : @v2.ExperimentalV2CloseSessionParams,
) -> @v2.ExperimentalV2CloseSessionResult {
  @async.pause()
  { meta: None }
}

///|
async fn interop_v2_fixture_set_config_option(
  _context : @v2.ExperimentalV2AgentContext,
  _params : @v2.ExperimentalV2SetConfigOptionParams,
) -> @v2.ExperimentalV2SetConfigOptionResult {
  @async.pause()
  { config_options: [], meta: None }
}

///|
/// The scripted prompt turn shared by both modes.  Wire order on the serial
/// writer: user-message upsert, agent chunk, agent chunk, tool-call create,
/// running state, permission request; after the permission reply either the
/// process dies (`die`) or the completing tool-call patch, the idle state,
/// and the prompt result follow.
fn interop_v2_fixture_prompt(
  mode : String,
) -> @v2.ExperimentalV2AgentPromptHandler {
  async fn(
    context : @v2.ExperimentalV2AgentContext,
    _params : @v2.ExperimentalV2PromptParams,
  ) -> @v2.ExperimentalV2PromptResult {
    context.session_update(interop_v2_fixture_user_message())
    context.session_update(interop_v2_fixture_agent_chunk("Inter"))
    context.session_update(interop_v2_fixture_agent_chunk("op"))
    context.session_update(interop_v2_fixture_tool_call_create())
    context.session_update(interop_v2_fixture_running())
    let permission = context.request_permission(
      interop_v2_fixture_permission_request(),
    )
    let selected = match permission.outcome {
      Known(OutcomeSelected(outcome)) => outcome.option_id
      Known(OutcomeCancelled) => "fixture-cancelled"
      Extension(..) | Future(..) => "fixture-unknown"
    }
    if mode == "die" {
      interop_v2_fixture_exit(70)
      abort("v2 interop fixture: libc exit must not return")
    }
    context.session_update(interop_v2_fixture_tool_call_patch(selected))
    context.session_update(interop_v2_fixture_idle())
    { meta: Some(interop_v2_fixture_selected_meta(selected)) }
  }
}

///|
/// The observed permission selection echoed inside the prompt result `_meta`
/// object, proving the client handler's choice crossed the real wire back to
/// this handler.
fn interop_v2_fixture_selected_meta(option_id : String) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["selectedOptionId"] = Json::string(option_id)
  Json::object(fields)
}

///|
fn interop_v2_fixture_user_message() -> @v2.ExperimentalV2UpdateSessionNotification {
  {
    session_id: "interop-session",
    update: Known(
      UpdateUserMessage({
        message_id: "fixture-user-message",
        content: PatchValue([
          Known(
            BlockText({
              text: "Find the matches",
              annotations: None,
              meta: None,
            }),
          ),
        ]),
        meta: PatchOmitted,
      }),
    ),
    meta: None,
  }
}

///|
/// One agent message chunk; both chunks share the `messageId`, so a consumer
/// folding with `experimental_v2_session_fold_apply` must aggregate them into
/// one two-block message.
fn interop_v2_fixture_agent_chunk(
  text : String,
) -> @v2.ExperimentalV2UpdateSessionNotification {
  {
    session_id: "interop-session",
    update: Known(
      UpdateAgentMessageChunk({
        message_id: "fixture-agent-message",
        content: Known(BlockText({ text, annotations: None, meta: None })),
        meta: None,
      }),
    ),
    meta: None,
  }
}

///|
fn interop_v2_fixture_tool_call_create() -> @v2.ExperimentalV2UpdateSessionNotification {
  {
    session_id: "interop-session",
    update: Known(
      UpdateToolCall({
        tool_call_id: "fixture-tool",
        title: PatchValue("Search repository"),
        kind: PatchValue(ToolKindRead),
        status: PatchValue(ToolCallStatusPending),
        content: PatchOmitted,
        locations: PatchOmitted,
        raw_input: PatchOmitted,
        raw_output: PatchOmitted,
        meta: PatchOmitted,
      }),
    ),
    meta: None,
  }
}

///|
/// The completing patch whose `rawOutput` carries the permission-selected
/// option id: the per-turn evidence that the round-trip reached this handler.
fn interop_v2_fixture_tool_call_patch(
  selected : String,
) -> @v2.ExperimentalV2UpdateSessionNotification {
  {
    session_id: "interop-session",
    update: Known(
      UpdateToolCall({
        tool_call_id: "fixture-tool",
        title: PatchOmitted,
        kind: PatchOmitted,
        status: PatchValue(ToolCallStatusCompleted),
        content: PatchOmitted,
        locations: PatchOmitted,
        raw_input: PatchOmitted,
        raw_output: PatchValue(Json::string(selected)),
        meta: PatchOmitted,
      }),
    ),
    meta: None,
  }
}

///|
fn interop_v2_fixture_running() -> @v2.ExperimentalV2UpdateSessionNotification {
  {
    session_id: "interop-session",
    update: Known(UpdateState(Known(StateRunning({ meta: None })))),
    meta: None,
  }
}

///|
fn interop_v2_fixture_idle() -> @v2.ExperimentalV2UpdateSessionNotification {
  {
    session_id: "interop-session",
    update: Known(
      UpdateState(
        Known(StateIdle({ stop_reason: Some(StopReasonEndTurn), meta: None })),
      ),
    ),
    meta: None,
  }
}

///|
fn interop_v2_fixture_permission_request() -> @v2.ExperimentalV2RequestPermissionRequest {
  {
    session_id: "interop-session",
    title: "Allow the repository search?",
    description: None,
    subject: None,
    options: [
      {
        option_id: "allow-once",
        name: "Allow once",
        kind: OptionKindAllowOnce,
        meta: None,
      },
      {
        option_id: "reject-once",
        name: "Reject once",
        kind: OptionKindRejectOnce,
        meta: None,
      },
    ],
    meta: None,
  }
}
