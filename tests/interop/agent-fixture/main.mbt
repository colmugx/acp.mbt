///|
/// In-repo MoonBit agent fixture for the full-stack stdio interop proof.
///
/// This executable is built by the client-side interop tests (`tests/interop`)
/// with `moon build` into a test-local target directory and spawned as a real
/// child process.  It serves one scripted ACP Agent over its own process
/// stdio with `agent_serve_stdio_with_outbound`, so every reverse request and
/// streamed notification travels the real engine, pipes, and framing — the
/// strongest in-repo stand-in for the deferred TS/Rust four-way interop.
///
/// Modes (first CLI argument):
/// - `serve`: initialize -> session/new -> one session/prompt that streams
///   two agent message chunks sharing one `messageId`, one tool call, and one
///   tool call update, issues one `session/request_permission`, and answers
///   the prompt with `stopReason: end_turn` plus the observed selected
///   permission option id encoded in the result `_meta` object (so the client
///   can prove the permission round-trip reached this handler through the
///   real wire).
/// - `die`: identical streaming and permission round-trip, then the process
///   terminates itself mid-prompt by design through libc `exit` — unlike a
///   panic it writes nothing to stdout, so the child's stdout stays pure
///   frames up to the last complete write.  The permission reply strictly
///   orders after every streamed frame on the serial writer, so the client
///   can assert deterministically which updates it observed before the
///   death.
async fn main {
  let mode = interop_fixture_mode()
  let endpoint = interop_fixture_endpoint(mode)
  @agent.agent_serve_stdio_with_outbound(
    endpoint~,
    context_factory=channel => @broker.agent_context_over_channel(channel~),
    initial_state=interop_fixture_state(endpoint),
    // The child's stderr is inherited by the spawning test, so per-frame
    // diagnostics would interleave with the test runner's own output.  The
    // stderr trace structure is proven elsewhere (agent G07); this fixture
    // keeps stdout pure frames and silences the trace explicitly.
    trace=_ => (),
  )
}

///|
/// Immediate process termination without unwinding and without touching
/// stdout or stderr.  `abort` is deliberately not used: the native runtime
/// prints panic output on stdout, which would corrupt the ACP frame stream
/// the interop test is proving pure.
extern "c" fn interop_fixture_exit(code : Int) = "exit"

///|
/// Read the single mode argument, failing fast on any other shape.
fn interop_fixture_mode() -> String {
  match @env.args() {
    [_, mode] => mode
    _ =>
      abort("interop fixture: expected exactly one mode argument (serve|die)")
  }
}

///|
/// The scripted agent endpoint.  Composition mirrors the agent package's own
/// test fixtures: immutable typed service values, capabilities derived from
/// service presence, one fail-fast endpoint construction.
fn interop_fixture_endpoint(mode : String) -> @agent.AgentEndpoint {
  let spec = @agent.agent_spec(
    info={
      name: "interop-fixture-agent",
      title: Omitted,
      version: "fixture",
      meta: Omitted,
    },
    sessions=@agent.agent_session_service(
      new_session=interop_fixture_new_session,
      prompt=interop_fixture_prompt(mode),
      cancel=interop_fixture_cancel,
      fork_session=interop_fixture_fork_session,
    ),
    support=@agent.agent_support(),
  ).unwrap()
  @agent.agent_endpoint_from_spec(spec)
}

///|
/// Adapter state seeded from the endpoint, identical to the agent package's
/// own test-fixture derivation: capabilities and auth methods come from the
/// endpoint value itself so admission can never disagree with the served
/// endpoint.
fn interop_fixture_state(
  endpoint : @agent.AgentEndpoint,
) -> @agent.AgentAdapterState {
  let config : @agent_protocol.AgentProtocolConfig = {
    agent_capabilities: Value(endpoint.capabilities()),
    auth_methods: endpoint.auth_methods(),
    agent_info: Omitted,
  }
  @agent.agent_adapter_state_new(
    protocol=@agent_protocol.agent_protocol_state_new(config~),
  )
}

///|
/// One deterministic session id the client asserts exactly.
async fn interop_fixture_new_session(
  _context : @agent.AgentContext,
  _params : @session_protocol.NewSessionParams,
) -> @session_protocol.NewSessionResult {
  @async.pause()
  {
    session_id: "interop-session",
    modes: Omitted,
    config_options: Omitted,
    meta: Omitted,
  }
}

///|
async fn interop_fixture_cancel(
  _context : @agent.AgentContext,
  _params : @session_protocol.CancelParams,
) -> Unit {
  @async.pause()
}

///|
/// The deterministic `session/fork` answer: the forked session id is the
/// requested id prefixed with `forked-`, everything else omitted, so the e2e
/// client can assert the round-trip reached this handler through the real
/// wire.  Upstream unstable (RFD session-fork, Draft).
async fn interop_fixture_fork_session(
  _context : @agent.AgentContext,
  params : @session_protocol.ForkSessionParams,
) -> @session_protocol.ForkSessionResult {
  @async.pause()
  {
    session_id: "forked-" + params.session_id,
    modes: Omitted,
    config_options: Omitted,
    meta: Omitted,
  }
}

///|
/// The scripted prompt turn shared by both modes.  Every outbound item goes
/// through the real engine channel, so ordering on the wire is the engine's
/// serial writer order: update, update, tool call, tool call update, then the
/// permission request.
fn interop_fixture_prompt(mode : String) -> @agent.AgentPromptHandler {
  async fn(
    context : @agent.AgentContext,
    _params : @session_protocol.PromptParams,
  ) -> @session_protocol.PromptResult {
    context.session_update(interop_fixture_agent_chunk("Inter"))
    context.session_update(interop_fixture_agent_chunk("op"))
    context.session_update(interop_fixture_tool_call())
    context.session_update(interop_fixture_tool_call_update())
    let permission = context.request_permission(
      interop_fixture_permission_request(),
    )
    let selected = match permission.outcome {
      Selected(outcome) => outcome.option_id
      Cancelled => "fixture-cancelled"
    }
    if mode == "die" {
      interop_fixture_exit(70)
      abort("interop fixture: libc exit must not return")
    }
    {
      stop_reason: EndTurn,
      meta: Value(interop_fixture_selected_meta(selected)),
    }
  }
}

///|
/// The observed permission selection echoed inside the prompt result `_meta`
/// object.  The pinned codec rejects non-object `_meta` values, and an object
/// is also the honest shape for an extension payload.
fn interop_fixture_selected_meta(option_id : String) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["selectedOptionId"] = Json::string(option_id)
  Json::object(fields)
}

///|
/// One agent message chunk.  Both chunks share the `messageId`, so a
/// consumer folding with `session_update_fold` must aggregate them into one
/// two-block message instead of two messages.
fn interop_fixture_agent_chunk(
  text : String,
) -> @session_protocol.SessionUpdateParams {
  {
    session_id: "interop-session",
    update: AgentMessageChunk({
      content: Text({ annotations: Omitted, text, meta: Omitted, }),
      message_id: Value("fixture-message"),
      meta: Omitted,
    }),
    meta: Omitted,
  }
}

///|
/// The tracked tool call created mid-turn.
fn interop_fixture_tool_call() -> @session_protocol.SessionUpdateParams {
  {
    session_id: "interop-session",
    update: ToolCall({
      tool_call_id: "fixture-tool",
      title: "Search repository",
      kind: Value(Read),
      status: Value(Pending),
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Omitted,
      meta: Omitted,
    }),
    meta: Omitted,
  }
}

///|
/// The partial replacement patch completing the tracked tool call.
fn interop_fixture_tool_call_update() -> @session_protocol.SessionUpdateParams {
  {
    session_id: "interop-session",
    update: ToolCallUpdate({
      tool_call_id: "fixture-tool",
      kind: Omitted,
      status: Value(Completed),
      title: Omitted,
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Value(Json::string("3 matches")),
      meta: Omitted,
    }),
    meta: Omitted,
  }
}

///|
/// One permission request carrying two options; the client fixture
/// auto-selects the first, and the observed selection is echoed back inside
/// the final prompt result `_meta`.
fn interop_fixture_permission_request() -> @protocol_data.RequestPermissionRequest {
  {
    session_id: "interop-session",
    tool_call: {
      tool_call_id: "fixture-tool",
      kind: Omitted,
      status: Omitted,
      title: Omitted,
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Omitted,
      meta: Omitted,
    },
    options: [
      {
        option_id: "allow-once",
        name: "Allow once",
        kind: AllowOnce,
        meta: Omitted,
      },
      {
        option_id: "reject-once",
        name: "Reject once",
        kind: RejectOnce,
        meta: Omitted,
      },
    ],
    meta: Omitted,
  }
}
