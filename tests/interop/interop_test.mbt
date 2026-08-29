///|
/// Full-stack MoonBit-to-MoonBit stdio interop proof.
///
/// A real MoonBit CLIENT runtime (`client_connect_process` on the single
/// connection engine) drives a real MoonBit AGENT runtime
/// (`agent_serve_stdio_with_outbound` inside the `tests/interop/agent-fixture`
/// executable) in a separate OS process over real pipes: the child's stdin is
/// the engine's writer, the child's stdout is the engine's reader, and every
/// frame — requests, streamed `session/update` notifications, the
/// `session/request_permission` reverse request, and each reply — crosses the
/// real newline framing and both engines.  This is the strongest in-repo
/// stand-in for the deferred TS/Rust four-way interop.
///
/// Determinism discipline: every assertion is gated on fully round-tripped
/// frames or EOF, never on sleeps or timing.  The fixture build uses a
/// test-local target directory so it cannot contend with the ambient
/// `moon test` build, mirroring the pattern the `moonbitlang/async` library
/// itself uses for its process test programs.
let interop_fixture_program : @async.Lazy[String] = Lazy(() => {
  let code = @process.run("moon", [
    "build", "tests/interop/agent-fixture", "--target", "native", "--target-dir",
    "_build/interop",
  ])
  if code != 0 {
    abort("interop test: agent fixture build failed with exit code \{code}")
  }
  "_build/interop/native/debug/build/tests/interop/agent-fixture/agent-fixture.exe"
})

///|
/// The client-side observation seams shared by both interop tests: typed
/// session updates recorded in wire order, permission requests recorded with
/// the auto-selected reply, settled outbound reply ids in settle order, and
/// typed outbound failures for exactly-once settle proofs.
struct InteropClientRecordings {
  updates : Array[@session_protocol.SessionUpdateParams]
  permissions : Array[@protocol_data.RequestPermissionRequest]
  responses : Array[String]
  failures : Array[(@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind)]
}

///|
fn interop_client_recordings() -> InteropClientRecordings {
  { updates: [], permissions: [], responses: [], failures: [], }
}

///|
/// The raw engine handler port for the interop client.  Real inbound agent
/// traffic (updates, permission) is owned by the client adapter and its
/// endpoint services; this port records the client-side observable wire
/// transcript — each settled outbound reply id, in order — and every typed
/// outbound failure.
fn interop_client_handlers(
  recordings : InteropClientRecordings,
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
/// The interop client endpoint: real services whose handlers record typed
/// values.  The session-update sink records each typed update in arrival
/// order; the permission handler auto-selects the first offered option, the
/// policy a headless client would use.
fn interop_client_endpoint(
  recordings : InteropClientRecordings,
) -> @client.ClientEndpoint {
  let spec = @client.client_spec(
    info={
      name: "interop-client",
      title: Omitted,
      version: "test",
      meta: Omitted,
    },
    session=@client.client_session_service(
      session_update=async fn(params : @session_protocol.SessionUpdateParams) {
        @async.pause()
        recordings.updates.push(params)
      },
      request_permission=async fn(
        request : @protocol_data.RequestPermissionRequest,
      ) -> @protocol_data.RequestPermissionResponse {
        @async.pause()
        recordings.permissions.push(request)
        {
          outcome: Selected({
            option_id: request.options[0].option_id,
            meta: Omitted,
          }),
          meta: Omitted,
        }
      },
    ),
  )
  @reader.Reader::run(@client.client_program(@reader.Reader::pure(spec)), ()).unwrap()
}

///|
/// Client adapter state seeded from the endpoint, identical to the client
/// package's own test-fixture derivation.
fn interop_client_state(
  endpoint : @client.ClientEndpoint,
) -> @client.ClientAdapterState {
  @client.client_adapter_state_new(
    protocol=@client_protocol.client_protocol_state_ready(
      capabilities=Value(endpoint.capabilities()),
    ),
  )
}

///|
fn interop_client_initialize_params() -> @protocol_data.InitializeParams {
  {
    protocol_version: 1,
    client_capabilities: Omitted,
    client_info: Omitted,
    meta: Omitted,
  }
}

///|
fn interop_client_new_session_params() -> @session_protocol.NewSessionParams {
  { cwd: "/", additional_directories: Omitted, mcp_servers: [], meta: Omitted, }
}

///|
/// Fold the recorded typed updates with the pure consumer fold, failing the
/// test on any typed rejection instead of silently skipping an update.
fn interop_client_fold(
  recordings : InteropClientRecordings,
) -> @protocol_data.SessionUpdateFold {
  let mut folded = @protocol_data.session_update_fold(known_modes=[])
  for update in recordings.updates {
    folded = @protocol_data.session_update_apply(folded, update.update).unwrap()
  }
  folded
}

///|
/// The positive full-stack interop proof.  The client initializes, creates
/// one session, and drives one prompt; the agent process streams two agent
/// message chunks sharing one `messageId`, one tool call, and one tool call
/// update, issues one permission request, and answers `end_turn` with the
/// permission selection echoed in `meta`.  The client then closes the child's
/// stdin — the ACP stdio shutdown signal — the agent exits on its own EOF,
/// the client engine ends on the child's stdout EOF, and the whole
/// composition returns with the child reaped inside the call.
async test "moonbit client drives a moonbit agent process end to end over stdio" {
  let fixture = interop_fixture_program.wait()
  let recordings = interop_client_recordings()
  let endpoint = interop_client_endpoint(recordings)
  let connections : @aqueue.Queue[@client.ClientConnection] = Queue(
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
        interop_client_initialize_params(),
      )
      assert_eq(initialized.protocol_version, 1)
      assert_eq(
        initialized.agent_info,
        Value({
          name: "interop-fixture-agent",
          title: Omitted,
          version: "fixture",
          meta: Omitted,
        }),
      )
      assert_eq(initialized.auth_methods, Omitted)
      let session = connection.new_session(interop_client_new_session_params())
      assert_eq(session, {
        session_id: "interop-session",
        modes: Omitted,
        config_options: Omitted,
        meta: Omitted,
      })
      let prompt = connection.prompt({
        session_id: "interop-session",
        prompt: [],
        meta: Omitted,
      })
      assert_eq(prompt.stop_reason, EndTurn)
      // The agent echoes the permission selection it observed inside the
      // result `_meta` object: this is the exact proof that the option the
      // client handler selected crossed the real wire back to the agent.
      match prompt.meta {
        Value(Object(fields)) =>
          assert_eq(
            fields.get("selectedOptionId"),
            Some(Json::string("allow-once")),
          )
        _ => fail("expected the selected option id in the prompt result meta")
      }
      child_stdin.close()
    })
    @client.client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @broker.client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_client_state(endpoint),
      handlers=interop_client_handlers(recordings),
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
  })
  // Exactly the four scripted updates arrived, in wire order.
  assert_eq(recordings.updates.length(), 4)
  // The consumer fold composes end to end: same-messageId chunks aggregate
  // into one two-block message, the tool call is tracked and patched.
  let folded = interop_client_fold(recordings)
  assert_eq(folded.user_messages, [])
  assert_eq(folded.agent_thoughts, [])
  assert_eq(folded.agent_messages, [
    {
      message_id: Value("fixture-message"),
      blocks: [
        Text({ annotations: Omitted, text: "Inter", meta: Omitted, }),
        Text({ annotations: Omitted, text: "op", meta: Omitted, }),
      ],
    },
  ])
  assert_eq(folded.tool_calls, [
    {
      tool_call_id: "fixture-tool",
      title: "Search repository",
      kind: Value(Read),
      status: Value(Completed),
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Value(Json::string("3 matches")),
      meta: Omitted,
    },
  ])
  assert_eq(folded.plan, None)
  assert_eq(folded.available_commands, [])
  assert_eq(folded.current_mode_id, None)
  assert_eq(folded.config_options, [])
  assert_eq(folded.session_title, Omitted)
  assert_eq(folded.session_updated_at, Omitted)
  assert_eq(folded.usage, None)
}

///|
/// The failure-path interop proof.  The fixture agent performs the identical
/// scripted turn — updates, tool states, permission round-trip — and then
/// dies mid-prompt by design.  The permission reply strictly orders after
/// every streamed frame on the agent's serial writer, so the client
/// deterministically observed all four updates and answered the permission
/// before the death; the still-parked prompt then settles exactly once with
/// one typed broker failure when the child's stdout reaches EOF.  The
/// composition returns (no hang) with the dead child reaped inside the call.
async test "moonbit client settles one typed failure when the agent dies mid-prompt" {
  let fixture = interop_fixture_program.wait()
  let recordings = interop_client_recordings()
  let endpoint = interop_client_endpoint(recordings)
  let connections : @aqueue.Queue[@client.ClientConnection] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let driver = group.spawn(() => {
      let connection = connections.get()
      let initialized = connection.initialize(
        interop_client_initialize_params(),
      )
      assert_eq(initialized.protocol_version, 1)
      let session = connection.new_session(interop_client_new_session_params())
      assert_eq(session.session_id, "interop-session")
      let failures : Array[@client.ClientConnectionError] = []
      ignore(
        connection.prompt({
          session_id: "interop-session",
          prompt: [],
          meta: Omitted,
        }),
      ) catch {
        error => failures.push(error)
      }
      assert_eq(failures, [
        ClientConnectionBrokerFailure(method_name="session/prompt"),
      ])
    })
    @client.client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @broker.client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_client_state(endpoint),
      handlers=interop_client_handlers(recordings),
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
  // Everything the agent streamed before dying arrived and was folded.
  assert_eq(recordings.updates.length(), 4)
  assert_eq(recordings.permissions.length(), 1)
  let folded = interop_client_fold(recordings)
  assert_eq(folded.agent_messages.length(), 1)
  assert_eq(folded.agent_messages[0].blocks.length(), 2)
  assert_eq(folded.tool_calls.length(), 1)
  assert_eq(folded.tool_calls[0].status, Value(Completed))
  assert_eq(folded.tool_calls[0].raw_output, Value(Json::string("3 matches")))
}

///|
/// The benign late-cancel interop regression. ACP v1 makes `$/cancel_request`
/// best-effort and real ACP clients routinely send cancels that lose the race
/// with an already-delivered response, so the agent engine must tolerate one
/// instead of failing the connection. The client settles `initialize`
/// (engine id 1), then emits the bidirectional cancellation for that
/// already-settled id, and the very next request must still round-trip over
/// the same live pipes: if the agent failed fast it would die on the spot,
/// the client engine would observe its stdout EOF, and `session/new` would
/// settle as a typed broker failure instead of a session id.
async test "moonbit client late cancel keeps the agent connection serving" {
  let fixture = interop_fixture_program.wait()
  let recordings = interop_client_recordings()
  let endpoint = interop_client_endpoint(recordings)
  let connections : @aqueue.Queue[@client.ClientConnection] = Queue(
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
        interop_client_initialize_params(),
      )
      assert_eq(initialized.protocol_version, 1)
      // Settle-then-cancel race: the reply for engine id 1 was already
      // observed above, so this cancellation targets an already-settled id.
      connection.cancel_request(Number(1))
      // The connection must keep serving traffic after the benign cancel.
      let session = connection.new_session(interop_client_new_session_params())
      assert_eq(session.session_id, "interop-session")
      child_stdin.close()
    })
    @client.client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @broker.client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_client_state(endpoint),
      handlers=interop_client_handlers(recordings),
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
/// The `session/fork` round-trip interop proof (upstream unstable, RFD
/// session-fork, Draft).  The fixture agent mounts the fork service, so the
/// real initialize result must advertise the derived `session.fork` marker;
/// the client then forks the live `interop-session` and the deterministic
/// `forked-`-prefixed id proves the request and its typed result both crossed
/// the real pipes, framing, and both engines.
async test "moonbit client forks a session on a live agent process over stdio" {
  let fixture = interop_fixture_program.wait()
  let recordings = interop_client_recordings()
  let endpoint = interop_client_endpoint(recordings)
  let connections : @aqueue.Queue[@client.ClientConnection] = Queue(
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
        interop_client_initialize_params(),
      )
      assert_eq(initialized.protocol_version, 1)
      // Capability derivation is service presence: the mounted fork handler
      // must surface as the session.fork marker in the real advertisement.
      match initialized.agent_capabilities {
        Value(
          {
            session_capabilities: Value({ fork: Value({ meta: Omitted, }), .. }),
            ..
          }
        ) => ()
        _ =>
          fail(
            "expected the derived session.fork marker in the initialize result",
          )
      }
      let forked = connection.fork_session({
        cwd: "/",
        session_id: "interop-session",
        additional_directories: Omitted,
        mcp_servers: Omitted,
        meta: Omitted,
      })
      assert_eq(forked, {
        session_id: "forked-interop-session",
        modes: Omitted,
        config_options: Omitted,
        meta: Omitted,
      })
      child_stdin.close()
    })
    @client.client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @broker.client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=interop_client_state(endpoint),
      handlers=interop_client_handlers(recordings),
      command=fixture,
      args=["serve"],
      spawned=ports => {
        let _ = child_stdins.try_put(ports.child_stdin) catch { _ => false }
      },
      trace=_ => (),
    )
    driver.wait()
  })
  // Initialize and session/fork each settled exactly one reply, nothing failed.
  assert_eq(recordings.responses, ["1", "2"])
  assert_eq(recordings.failures.length(), 0)
}
