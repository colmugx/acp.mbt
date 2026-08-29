///|
/// Full-stack MoonBit-to-MoonBit stdio interop proof for the ACP v2 Draft
/// baseline.  A real MoonBit v2 CLIENT runtime (`experimental_v2_client_connect_process`
/// on the single connection engine) drives a real MoonBit v2 AGENT runtime
/// (`experimental_v2_agent_serve_stdio_with_outbound` inside the
/// `tests/interop/v2/agent-fixture` executable) in a separate OS process over
/// real pipes: the child's stdin is the engine's writer, the child's stdout is
/// the engine's reader, and every frame — requests, streamed `session/update`
/// notifications, the `session/request_permission` reverse request, and each
/// reply — crosses the real newline framing and both engines.
///
/// Determinism discipline: every assertion is gated on fully round-tripped
/// frames or EOF, never on sleeps or timing.  The fixture build uses a
/// test-local target directory so it cannot contend with the ambient
/// `moon test` build, mirroring the v1 interop harness pattern.
let interop_v2_fixture_program : @async.Lazy[String] = Lazy(() => {
  let code = @process.run("moon", [
    "build", "tests/interop/v2/agent-fixture", "--target", "native", "--target-dir",
    "_build/interop-v2",
  ])
  if code != 0 {
    abort("v2 interop test: agent fixture build failed with exit code \{code}")
  }
  "_build/interop-v2/native/debug/build/tests/interop/v2/agent-fixture/agent-fixture.exe"
})

///|
/// The client-side observation seams shared by the engine-driven tests: typed
/// session updates recorded in wire order, permission requests recorded with
/// the auto-selected reply, settled outbound reply ids in settle order, and
/// typed outbound failures for exactly-once settle proofs.
struct InteropV2ClientRecordings {
  updates : Array[@experimental.ExperimentalV2UpdateSessionNotification]
  permissions : Array[@experimental.ExperimentalV2RequestPermissionRequest]
  responses : Array[String]
  failures : Array[(@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind)]
}

///|
fn interop_v2_client_recordings() -> InteropV2ClientRecordings {
  { updates: [], permissions: [], responses: [], failures: [] }
}

///|
/// The raw engine handler port for the interop client.  Real inbound agent
/// traffic (updates, permission) is owned by the v2 client owner port and its
/// endpoint services; this port records the client-side observable wire
/// transcript — each settled outbound reply id, in order — and every typed
/// outbound failure.
fn interop_v2_client_handlers(
  recordings : InteropV2ClientRecordings,
) -> @runtime.RuntimeHandlerPort {
  {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => (),
    response: response => {
      recordings.responses.push(
        match response {
          Success(success) => @runtime.runtime_request_id_text(success.id)
          Error(failure) =>
            match failure.id {
              String(value) => value
              Number(value) => value.to_string()
              Null => "null"
            }
        },
      )
    },
    outbound_failure: Some((id, failure) => {
      recordings.failures.push((id, failure.reason))
    }),
  }
}

///|
fn interop_v2_client_info() -> @experimental.ExperimentalV2Implementation {
  { name: "v2-interop-client", title: None, version: "test", meta: None }
}

///|
/// The interop client endpoint: real services whose handlers record typed
/// values.  The session-update sink records each typed notification in
/// arrival order; the permission handler auto-selects the first offered
/// option, the policy a headless client would use.
fn interop_v2_client_endpoint(
  recordings : InteropV2ClientRecordings,
) -> @experimental.ExperimentalV2ClientEndpoint {
  let spec = try! @experimental.experimental_v2_client_spec(
    info=interop_v2_client_info(),
    session=@experimental.experimental_v2_client_session_service(
      session_update=async fn(notification) {
        @async.pause()
        recordings.updates.push(notification)
        ()
      },
      request_permission=async fn(
        request : @experimental.ExperimentalV2RequestPermissionRequest,
      ) -> @experimental.ExperimentalV2RequestPermissionResponse {
        @async.pause()
        recordings.permissions.push(request)
        {
          outcome: Known(
            OutcomeSelected({
              option_id: request.options[0].option_id,
              meta: None,
            }),
          ),
          meta: None,
        }
      },
    ),
  )
  @experimental.experimental_v2_client_endpoint_from_spec(spec)
}

///|
/// Client adapter state seeded ready from the endpoint's own derived
/// capabilities, mirroring the experimental package's test-fixture derivation:
/// the engine owns correlation, so the protocol snapshot is committed from the
/// pinned version-2 initialize result the real exchange will carry.
fn interop_v2_client_state(
  endpoint : @experimental.ExperimentalV2ClientEndpoint,
) -> @experimental.ExperimentalV2ClientAdapterState {
  let ready = try! @experimental.experimental_v2_client_reduce(
    @experimental.experimental_v2_client_state_new(
      capabilities=endpoint.capabilities(),
    ),
    InitializeResult(interop_v2_agent_advertisement()),
  )
  @experimental.experimental_v2_client_adapter_state_new(protocol=ready.state)
}

///|
/// The fixture agent's initialize advertisement, mirrored exactly so the
/// seeded client state and the assertions describe the real peer.
fn interop_v2_agent_advertisement() -> @experimental.ExperimentalV2InitializeResult {
  {
    protocol_version: @experimental.experimental_v2_protocol_version,
    info: {
      name: "v2-interop-fixture-agent",
      title: None,
      version: "fixture",
      meta: None,
    },
    capabilities: {
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
        fork: MarkerUnsupported,
        meta: None,
      }),
      auth: MarkerUnsupported,
      meta: None,
    },
    auth_methods: None,
    meta: None,
  }
}

///|
/// Fold the recorded typed updates with the pure consumer fold, failing the
/// test on any typed rejection instead of silently skipping an update.
fn interop_v2_client_fold(
  recordings : InteropV2ClientRecordings,
) -> @experimental.ExperimentalV2SessionFold raise {
  let mut folded = @experimental.experimental_v2_session_fold_new()
  for update in recordings.updates {
    folded = match
      @experimental.experimental_v2_session_fold_apply(folded, update.update) {
      Ok(next) => next
      Err(error) =>
        fail("v2 interop: update rejected by the fold: \{Repr(error)}")
    }
  }
  folded
}

///|
/// The positive full-stack v2 interop proof.  The client initializes (pin 2),
/// creates one session, and drives one prompt; the agent process streams a
/// user-message upsert, two agent-message chunks sharing one `messageId`, a
/// tool-call create, `state_update running`, one two-option permission
/// round-trip, the completing tool-call patch carrying the selected option id
/// in `rawOutput`, and `state_update idle` with `stopReason end_turn`, then
/// answers the prompt with the selection echoed in `_meta`.  The client closes
/// the child's stdin — the ACP stdio shutdown signal — the agent exits on its
/// own EOF, the client engine ends on the child's stdout EOF, and the whole
/// composition returns with the child reaped inside the call.
async test "v2 moonbit client drives a v2 moonbit agent process end to end over stdio" {
  let fixture = interop_v2_fixture_program.wait()
  let recordings = interop_v2_client_recordings()
  let endpoint = interop_v2_client_endpoint(recordings)
  let connections : @aqueue.Queue[@experimental.ExperimentalV2ClientConnection] = Queue(
    kind=Unbounded,
  )
  let child_stdins : @aqueue.Queue[@process.WriteToProcess] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let driver = group.spawn(() => {
      let connection = connections.get()
      let child_stdin = child_stdins.get()
      let initialized = connection.initialize(
        @experimental.experimental_v2_client_initialize_params(
          info=interop_v2_client_info(),
          capabilities=endpoint.capabilities(),
        ),
      )
      assert_eq(
        initialized.protocol_version,
        @experimental.experimental_v2_protocol_version,
      )
      assert_eq(initialized.info, {
        name: "v2-interop-fixture-agent",
        title: None,
        version: "fixture",
        meta: None,
      })
      assert_eq(
        initialized.capabilities,
        interop_v2_agent_advertisement().capabilities,
      )
      assert_eq(initialized.auth_methods, None)
      let session = connection.new_session({
        cwd: "/",
        additional_directories: None,
        mcp_servers: None,
        meta: None,
      })
      assert_eq(session, {
        session_id: "interop-session",
        config_options: None,
        meta: None,
      })
      let prompt = connection.prompt({
        session_id: "interop-session",
        prompt: [],
        meta: None,
      })
      // The agent echoes the permission selection it observed inside the
      // result `_meta` object: the exact proof that the option the client
      // handler selected crossed the real wire back to the agent.
      match prompt.meta {
        Some(Object(fields)) =>
          assert_eq(
            fields.get("selectedOptionId"),
            Some(Json::string("allow-once")),
          )
        _ => fail("expected the selected option id in the prompt result meta")
      }
      child_stdin.close()
    })
    @experimental.experimental_v2_client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @experimental.experimental_v2_client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_v2_client_state(endpoint),
      handlers=interop_v2_client_handlers(recordings),
      command=fixture,
      args=["serve"],
      spawned=ports => {
        let _ = child_stdins.try_put(ports.child_stdin) catch { _ => false }
      },
      trace=_ => (),
    )
    driver.wait()
  })
  // Client-side ordered wire transcript: exactly one settled reply per
  // outbound request, in engine id order, and no outbound failure.
  assert_eq(recordings.responses, ["1", "2", "3"])
  assert_eq(recordings.failures.length(), 0)
  // The permission round-trip reached the client handler exactly once, with
  // the fixture's two-option request intact.
  assert_eq(recordings.permissions.length(), 1)
  assert_eq(recordings.permissions[0], {
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
  })
  // Exactly the seven scripted updates arrived, in wire order.
  assert_eq(recordings.updates.length(), 7)
  // The consumer fold composes end to end: same-messageId chunks aggregate
  // into one two-block message, the tool call is created and patched with the
  // permission-selected evidence, and the turn ends idle with end_turn.
  let folded = interop_v2_client_fold(recordings)
  assert_eq(folded.phase, TurnIdle)
  assert_eq(folded.stop_reason, Some(StopReasonEndTurn))
  assert_eq(folded.user_messages, [
    {
      message_id: "fixture-user-message",
      blocks: [
        Known(
          BlockText({ text: "Find the matches", annotations: None, meta: None }),
        ),
      ],
      meta: None,
    },
  ])
  assert_eq(folded.agent_messages, [
    {
      message_id: "fixture-agent-message",
      blocks: [
        Known(BlockText({ text: "Inter", annotations: None, meta: None })),
        Known(BlockText({ text: "op", annotations: None, meta: None })),
      ],
      meta: None,
    },
  ])
  assert_eq(folded.agent_thoughts, [])
  assert_eq(folded.tool_calls, [
    {
      tool_call_id: "fixture-tool",
      title: PatchValue("Search repository"),
      kind: PatchValue(ToolKindRead),
      status: PatchValue(ToolCallStatusCompleted),
      content: PatchOmitted,
      locations: PatchOmitted,
      raw_input: PatchOmitted,
      raw_output: PatchValue(Json::string("allow-once")),
      meta: PatchOmitted,
    },
  ])
  assert_eq(folded.terminals, [])
  assert_eq(folded.plans, [])
  assert_eq(folded.config_options, None)
  assert_eq(folded.available_commands, None)
  assert_eq(folded.session_title, None)
  assert_eq(folded.session_updated_at, None)
  assert_eq(folded.session_meta, None)
  assert_eq(folded.usage, None)
  assert_eq(folded.preserved, [])
}

///|
/// The failure-path v2 interop proof.  The fixture agent performs the
/// identical streamed turn — user message, chunks, tool create, running state,
/// permission round-trip — and then dies mid-prompt by design through libc
/// `exit`, which writes nothing to stdout.  The permission reply strictly
/// orders after every streamed frame on the agent's serial writer, so the
/// client deterministically observed all five pre-death updates and answered
/// the permission before the death; the still-parked prompt then settles
/// exactly once with one typed broker failure when the child's stdout reaches
/// EOF.  The composition returns (no hang) with the dead child reaped inside
/// the call.
async test "v2 moonbit client settles one typed failure when the agent dies mid-prompt" {
  let fixture = interop_v2_fixture_program.wait()
  let recordings = interop_v2_client_recordings()
  let endpoint = interop_v2_client_endpoint(recordings)
  let connections : @aqueue.Queue[@experimental.ExperimentalV2ClientConnection] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let driver = group.spawn(() => {
      let connection = connections.get()
      let initialized = connection.initialize(
        @experimental.experimental_v2_client_initialize_params(
          info=interop_v2_client_info(),
          capabilities=endpoint.capabilities(),
        ),
      )
      assert_eq(
        initialized.protocol_version,
        @experimental.experimental_v2_protocol_version,
      )
      let session = connection.new_session({
        cwd: "/",
        additional_directories: None,
        mcp_servers: None,
        meta: None,
      })
      assert_eq(session.session_id, "interop-session")
      let errors : Array[@experimental.ExperimentalV2ClientConnectionError] = []
      ignore(
        connection.prompt({
          session_id: "interop-session",
          prompt: [],
          meta: None,
        }),
      ) catch {
        error => errors.push(error)
      }
      assert_eq(errors.length(), 1)
      match errors[0] {
        BrokerFailure(method_name~) => assert_eq(method_name, "session/prompt")
        _ => fail("expected one typed broker failure for the parked prompt")
      }
    })
    @experimental.experimental_v2_client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @experimental.experimental_v2_client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_v2_client_state(endpoint),
      handlers=interop_v2_client_handlers(recordings),
      command=fixture,
      args=["die"],
      trace=_ => (),
    )
    driver.wait()
  })
  // The prompt never settled a reply; initialize and session/new did.
  assert_eq(recordings.responses, ["1", "2"])
  // Exactly-once typed settle for the parked outbound prompt: engine id 3,
  // closed by the child's stdout EOF.
  assert_eq(recordings.failures.length(), 1)
  assert_eq(recordings.failures[0].0, Number(3))
  assert_true(recordings.failures[0].1 is EndOfInput)
  // Everything the agent streamed before dying arrived, the permission
  // round-trip completed, and the fold holds exactly the pre-death state.
  assert_eq(recordings.updates.length(), 5)
  assert_eq(recordings.permissions.length(), 1)
  let folded = interop_v2_client_fold(recordings)
  assert_eq(folded.phase, TurnRunning)
  assert_eq(folded.stop_reason, None)
  assert_eq(folded.user_messages.length(), 1)
  assert_eq(folded.agent_messages.length(), 1)
  assert_eq(folded.agent_messages[0].blocks.length(), 2)
  assert_eq(folded.tool_calls.length(), 1)
  assert_eq(folded.tool_calls[0].status, PatchValue(ToolCallStatusPending))
  assert_eq(folded.tool_calls[0].raw_output, PatchOmitted)
}

///|
/// The benign late-cancel v2 interop regression.  `$/cancel_request` is
/// best-effort and real ACP clients routinely send cancels that lose the race
/// with an already-delivered response, so the agent engine must tolerate one
/// instead of failing the connection.  The client settles `initialize`
/// (engine id 1), then emits the bidirectional cancellation for that
/// already-settled id, and the very next request must still round-trip over
/// the same live pipes.
async test "v2 agent tolerates a late wire cancel and keeps serving" {
  let fixture = interop_v2_fixture_program.wait()
  let recordings = interop_v2_client_recordings()
  let endpoint = interop_v2_client_endpoint(recordings)
  let connections : @aqueue.Queue[@experimental.ExperimentalV2ClientConnection] = Queue(
    kind=Unbounded,
  )
  let child_stdins : @aqueue.Queue[@process.WriteToProcess] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let driver = group.spawn(() => {
      let connection = connections.get()
      let child_stdin = child_stdins.get()
      let initialized = connection.initialize(
        @experimental.experimental_v2_client_initialize_params(
          info=interop_v2_client_info(),
          capabilities=endpoint.capabilities(),
        ),
      )
      assert_eq(
        initialized.protocol_version,
        @experimental.experimental_v2_protocol_version,
      )
      // Settle-then-cancel race: the reply for engine id 1 was already
      // observed above, so this cancellation targets an already-settled id.
      connection.cancel_request(RequestIdNumber(1))
      // The connection must keep serving traffic after the benign cancel.
      let session = connection.new_session({
        cwd: "/",
        additional_directories: None,
        mcp_servers: None,
        meta: None,
      })
      assert_eq(session.session_id, "interop-session")
      child_stdin.close()
    })
    @experimental.experimental_v2_client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @experimental.experimental_v2_client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_v2_client_state(endpoint),
      handlers=interop_v2_client_handlers(recordings),
      command=fixture,
      args=["serve"],
      spawned=ports => {
        let _ = child_stdins.try_put(ports.child_stdin) catch { _ => false }
      },
      trace=_ => (),
    )
    driver.wait()
  })
  // Both engine requests settled exactly one reply and nothing failed.
  assert_eq(recordings.responses, ["1", "2"])
  assert_eq(recordings.failures.length(), 0)
}

///|
/// Newline-delimited frame reader over the spawned child's real stdout, so
/// the batch scenario can observe the exact wire frames the agent writes.
struct InteropV2FrameReader {
  source : @process.ReadFromProcess
  mut framing : @transport.FramingState
  buffered : Array[String]
}

///|
fn interop_v2_frame_reader(
  source : @process.ReadFromProcess,
) -> InteropV2FrameReader {
  {
    source,
    framing: try! @transport.framing_state(max_frame_bytes=1024 * 1024),
    buffered: [],
  }
}

///|
async fn interop_v2_frame(reader : InteropV2FrameReader) -> String {
  for ;; {
    if reader.buffered.length() > 0 {
      return reader.buffered.remove(0)
    }
    match reader.source.read_some(max_len=4096) {
      None =>
        fail("v2 interop: child stdout reached EOF before the expected frame")
      Some(chunk) => {
        let step = @transport.framing_feed(reader.framing, chunk)
        reader.framing = step.state
        for frame in step.frames {
          reader.buffered.push(frame)
        }
      }
    }
  }
}

///|
/// Drain the remaining stream to EOF; a partial final line fails the framing
/// finish, so a clean return also proves the child's stdout ended on a frame
/// boundary.
async fn interop_v2_drain(reader : InteropV2FrameReader) -> Array[String] {
  for ;; {
    match reader.source.read_some(max_len=4096) {
      None => {
        let _ = @transport.framing_finish(reader.framing)
        return reader.buffered
      }
      Some(chunk) => {
        let step = @transport.framing_feed(reader.framing, chunk)
        reader.framing = step.state
        for frame in step.frames {
          reader.buffered.push(frame)
        }
      }
    }
  }
}

///|
fn interop_v2_wire_line(frame : String) -> Bytes {
  @utf8.encode(frame + "\n")
}

///|
/// Decode one child frame as a successful single-object response.  The shared
/// codec rejects arrays, so a passing decode is itself the proof that the
/// reply left the agent as a normal lone-object frame.
fn interop_v2_success_frame(frame : String) -> @jsonrpc.JsonRpcSuccess raise {
  match @jsonrpc.jsonrpc_decode(frame) {
    Response(Success(success)) => success
    _ =>
      fail("v2 interop: expected one successful single-object response frame")
  }
}

///|
/// The batch-frame interop proof.  A raw driver writes frames straight to the
/// child's stdin through `runtime_process_ports` — no client engine runs here,
/// because a reply to a driver-chosen id would be an unknown response for any
/// engine correlation table — while the fixture agent's stdio reader is
/// wrapped by `experimental_v2_batch_expanding_ports` (`batch=true`).  One
/// two-entry batch frame carrying a `session/list` request and a
/// `session/cancel` notification for a never-seen session id crosses the real
/// pipe; the expansion feeds both entries to the engine in order, the list
/// reply leaves as a normal single-object frame, the notification produces no
/// reply, and the very next request still round-trips over the same pipes.
async test "v2 agent processes a two-entry batch frame" {
  let fixture = interop_v2_fixture_program.wait()
  @async.with_task_group(group => {
    let spawned = @runtime.runtime_process_ports(
      group,
      handlers={
        request: _ => HandlerSuccess(Json::null()),
        notification: _ => (),
        response: _ => (),
        outbound_failure: None,
      },
      command=fixture,
      args=["serve"],
      trace=_ => (),
    )
    let reader = interop_v2_frame_reader(spawned.child_stdout)
    spawned.child_stdin.write(
      interop_v2_wire_line(
        "{\"jsonrpc\":\"2.0\",\"id\":\"raw-init\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":2,\"info\":{\"name\":\"v2-interop-client\",\"version\":\"test\"},\"capabilities\":{}}}",
      ),
    )
    let initialized = interop_v2_success_frame(interop_v2_frame(reader))
    assert_eq(initialized.id, String("raw-init"))
    assert_eq(
      try! @experimental.experimental_v2_decode_initialize_result(
        initialized.result,
      ),
      interop_v2_agent_advertisement(),
    )
    // ONE batch frame line: a session/list request plus a session/cancel
    // notification for a session the agent never created.
    let batch = try! @experimental.experimental_v2_batch_encode([
      Request(
        try! @jsonrpc.JsonRpcRequest::new(
          id=String("raw-list"),
          method_name="session/list",
          params=try! @experimental.experimental_v2_encode_list_sessions_params({
              cwd: None,
              cursor: None,
              meta: None,
            },
          ),
        ),
      ),
      Notification(
        try! @jsonrpc.JsonRpcNotification::new(
          method_name="session/cancel",
          params=try! @experimental.experimental_v2_encode_cancel_session_params({
              session_id: "never-seen",
              meta: None,
            },
          ),
        ),
      ),
    ])
    spawned.child_stdin.write(interop_v2_wire_line(batch))
    let list_frame = interop_v2_frame(reader)
    assert_false(list_frame.has_prefix("["))
    let listed = interop_v2_success_frame(list_frame)
    assert_eq(listed.id, String("raw-list"))
    let sessions = try! @experimental.experimental_v2_decode_list_sessions_result(
      listed.result,
    )
    assert_eq(sessions.sessions.length(), 1)
    assert_eq(sessions.sessions[0].session_id, "interop-session")
    assert_eq(sessions.sessions[0].title, Some("Interop fixture session"))
    // The notification produced no reply: exactly one frame answered the
    // batch, and the connection continues — the next request round-trips.
    spawned.child_stdin.write(
      interop_v2_wire_line(
        "{\"jsonrpc\":\"2.0\",\"id\":\"raw-new\",\"method\":\"session/new\",\"params\":{\"cwd\":\"/\"}}",
      ),
    )
    let created = interop_v2_success_frame(interop_v2_frame(reader))
    assert_eq(created.id, String("raw-new"))
    assert_eq(
      try! @experimental.experimental_v2_decode_new_session_result(
        created.result,
      ),
      { session_id: "interop-session", config_options: None, meta: None },
    )
    // The ACP stdio shutdown signal: the agent exits on its own EOF, and the
    // drained stream holds no further frame — the notification never replied.
    spawned.child_stdin.close()
    assert_eq(interop_v2_drain(reader), [])
  })
}
