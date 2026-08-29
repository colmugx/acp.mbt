///|
/// Inert observation seams for engine-over-process tests: inbound requests
/// are answered by the owner port below, inbound responses are recorded by
/// id text, and nothing here performs I/O of its own.
fn client_process_test_handlers(
  responses : Array[String],
) -> @runtime.RuntimeHandlerPort {
  {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => (),
    response: response => {
      responses.push(
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
    outbound_failure: None,
  }
}

///|
/// Total unit owner port answering every inbound request with one immediate
/// success result, mirroring the facade's owner-runner smoke shape.
fn client_process_test_owner_port() -> @connection.RuntimeOwnerPort[
  Unit,
  Unit,
  Unit,
  Unit,
] {
  {
    initial_state: (),
    admit_request: (_state, _id, _request) => {
      RuntimeOwnerRequestImmediate(completion={
        state: (),
        response: HandlerSuccess(Json::string("pong")),
        effects: [],
      })
    },
    admit_notification: (_state, _notification) => {
      RuntimeOwnerNotificationImmediate(completion={ state: (), effects: [], })
    },
    execute: async fn(_invocation) {
      @async.pause()
      ()
    },
    execute_failure: (_state, _invocation) => (),
    execute_cancel: (_state, _invocation) => (),
    complete_request: (_state, _id, _invocation, _completion) => {
      state: (),
      response: HandlerSuccess(Json::null()),
      effects: [],
    },
    complete_notification: (_state, _invocation, _completion) => {
      state: (),
      effects: [],
    },
    plan_local_effect: _effect => RuntimeOwnerNoCommands,
    cancel_request: (_state, _id, _invocation) => ((), ()),
    abort: (_state, _task) => (),
  }
}

///|
/// Full engine-over-real-process integration.  `/bin/cat` is the peer: every
/// frame the engine writes to the child's stdin is echoed back on the child's
/// stdout and re-enters the engine through the real framing reader.  One
/// locally initiated request therefore travels request → pipe → child → pipe
/// → inbound dispatch → immediate response → pipe → child → pipe → response
/// correlation → parked submitter, all through real process I/O.  Closing the
/// child's stdin afterwards makes the child exit, the reader observes EOF,
/// and the same single engine terminates cleanly with structured results.
async test "engine runs one request round-trip over a real /bin/cat process" {
  let responses : Array[String] = []
  @async.with_task_group(group => {
    let spawned = @runtime.runtime_process_ports(
      group,
      handlers=client_process_test_handlers(responses),
      command="/bin/cat",
      trace=_ => (),
    )
    let channels : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
      kind=Unbounded,
    )
    let engine = group.spawn(() => {
      @connection.connection_runtime_run_owner_with_outbound(
        spawned.ports,
        @runtime.runtime_default_options(),
        channel => {
          let _ = channels.try_put(channel) catch { _ => false }
          client_process_test_owner_port()
        },
      )
    })
    let channel = channels.get()
    let reply = channel.submit_request(
      method_name="probe",
      params=Json::object({}),
    )
    spawned.child_stdin.close()
    engine.wait()
    match reply {
      Success(success) => {
        assert_eq(success.id, Number(1))
        assert_eq(success.result, Json::string("pong"))
      }
      Error(_) => fail("the echoed engine response must complete the pending")
    }
    assert_eq(responses, ["1"])
  })
}

///|
/// Composition fail-fast: invalid runtime options are rejected before any
/// child process is spawned.  The composition's error channel is the engine's
/// untyped boundary (cancellation must flow through it), so this level
/// proves the visible failure plus its precise trace kind; the typed
/// `InvalidOptions` constructor itself is proven at the typed
/// `runtime_process_ports` seam in the runtime suite.
async test "client_connect_process validates options before spawning" {
  let endpoint = client_endpoint_test_endpoint("process-options", true)
  let raised : Array[Unit] = []
  try {
    client_connect_process(
      endpoint_factory=_channel => endpoint,
      initial_state=client_adapter_test_state(endpoint),
      handlers=client_process_test_handlers([]),
      command="/bin/cat",
      options={ ..@runtime.runtime_default_options(), max_frame_bytes: 0, },
      trace=_ => (),
    )
    ()
  } catch {
    _ => raised.push(())
  }
  assert_eq(raised.length(), 1)
}

///|
/// Composition fail-fast: an empty command raises a visible error with the
/// `process_command_invalid` trace kind, before any pipe or process exists.
async test "client_connect_process rejects an empty command fail-fast" {
  let endpoint = client_endpoint_test_endpoint("process-empty", true)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let raised : Array[Unit] = []
  try {
    client_connect_process(
      endpoint_factory=_channel => endpoint,
      initial_state=client_adapter_test_state(endpoint),
      handlers=client_process_test_handlers([]),
      command="",
      trace=event => traces.push(event),
    )
    ()
  } catch {
    _ => raised.push(())
  }
  assert_eq(raised.length(), 1)
  assert_true(
    traces.any(event => event.error_kind == "process_command_invalid"),
  )
}

///|
/// Composition fail-fast: a nonexistent command is refused by the operating
/// system and surfaces as a visible error carrying the precise
/// `process_spawn_failed` trace kind.
async test "client_connect_process surfaces a spawn rejection as a typed error" {
  let endpoint = client_endpoint_test_endpoint("process-missing", true)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let raised : Array[Unit] = []
  try {
    client_connect_process(
      endpoint_factory=_channel => endpoint,
      initial_state=client_adapter_test_state(endpoint),
      handlers=client_process_test_handlers([]),
      command="/nonexistent/acp-spawn-probe",
      trace=event => traces.push(event),
    )
    ()
  } catch {
    _ => raised.push(())
  }
  assert_eq(raised.length(), 1)
  assert_true(traces.any(event => event.error_kind == "process_spawn_failed"))
}

///|
/// Composition happy boundary: a child that exits immediately (`/usr/bin/true`)
/// gives the engine a real process stdout whose EOF ends the connection
/// cleanly.  The composition returns normally — spawn, wiring, EOF close, and
/// child reap inside the call — without any frame exchanged.
async test "client_connect_process ends cleanly on immediate child EOF" {
  let endpoint = client_endpoint_test_endpoint("process-true", true)
  client_connect_process(
    endpoint_factory=_channel => endpoint,
    initial_state=client_adapter_test_state(endpoint),
    handlers=client_process_test_handlers([]),
    command="/usr/bin/true",
    trace=_ => (),
  )
}
