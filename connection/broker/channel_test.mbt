///|
using @connection {
  type RuntimeOutboundChannel,
  type RuntimeOwnerPort,
  connection_runtime_run_owner_with_outbound,
}

///|
using @jsonrpc {jsonrpc_decode, type RequestId}

///|
using @runtime {
  type RuntimeOutboundFailureKind,
  type RuntimePorts,
  type RuntimeTraceEvent,
  runtime_default_options,
}

///|
using @session_protocol {type NewSessionParams}

///|
/// Deterministic in-memory ports for the client forward-request tests: the
/// reader is fed from one unbounded queue (`None` is EOF), the writer records
/// frames and signals each write, and the response and outbound-failure
/// callbacks record typed ids so exactly-once settle is observable without
/// engine internals.  No real I/O, timers, or sleeps are involved.
fn broker_channel_test_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[RuntimeTraceEvent],
  responses : Array[RequestId],
  failures : Array[(RequestId, RuntimeOutboundFailureKind)],
) -> RuntimePorts {
  {
    reader: { read: _ => input.get() },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: response => {
        responses.push(
          match response {
            Success(success) => success.id
            Error(_) =>
              fail("expected a successful reply for the forward request")
          },
        )
      },
      outbound_failure: Some((id, failure) => {
        failures.push((id, failure.reason))
      }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
}

///|
/// One minimal total owner port: every inbound peer request is answered
/// immediately with a null success and notifications commit nothing.  The
/// tests exercise the outbound direction, so no async invocation is needed.
fn broker_channel_test_owner_port() -> RuntimeOwnerPort[Unit, Unit, Unit, Unit] {
  {
    initial_state: (),
    admit_request: (_state, _id, _request) => {
      RuntimeOwnerRequestImmediate(completion={
        state: (),
        response: HandlerSuccess(Json::null()),
        effects: [],
      })
    },
    admit_notification: (_state, _notification) => {
      RuntimeOwnerNotificationImmediate(completion={ state: (), effects: [] })
    },
    execute: _invocation => (),
    execute_failure: (_state, _invocation) => (),
    execute_cancel: (_state, _invocation) => (),
    complete_request: (state, _id, _invocation, _completion) => {
      state,
      response: HandlerSuccess(Json::null()),
      effects: [],
    },
    complete_notification: (state, _invocation, _completion) => {
      state,
      effects: [],
    },
    plan_local_effect: _effect => RuntimeOwnerNoCommands,
    cancel_request: (state, _id, _invocation) => (state, ()),
    abort: (state, _task) => state,
  }
}

///|
fn broker_channel_test_new_params(cwd : String) -> NewSessionParams {
  { cwd, additional_directories: Omitted, mcp_servers: [], meta: Omitted }
}

///|
fn broker_channel_test_request(frame : Bytes) -> @jsonrpc.JsonRpcRequest raise {
  match jsonrpc_decode(@utf8.decode(frame.view())) {
    Request(request) => request
    _ => fail("expected one JSON-RPC request frame")
  }
}

///|
/// Run the one owner engine and capture its outbound channel for the test
/// body, mirroring the engine whitebox harness without engine internals.
async fn broker_channel_test_run(
  ports : RuntimePorts,
  captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]],
) -> Unit {
  connection_runtime_run_owner_with_outbound(ports, runtime_default_options(), channel => {
    let _ = captured.try_put(channel) catch { _ => false }
    broker_channel_test_owner_port()
  })
}

///|
async test "client connection over channel submits forward requests with distinct engine ids" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = broker_channel_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => broker_channel_test_run(ports, captured))
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = client_connection_over_channel(channel~)
      let first = connection.new_session(
        broker_channel_test_new_params("/first"),
      )
      let second = connection.new_session(
        broker_channel_test_new_params("/second"),
      )
      (first, second)
    })
    // The fake peer answers each forward request only after observing its
    // frame, so engine id allocation and correlation stay observable.
    ignore(written.get())
    let first_request = broker_channel_test_request(output[0])
    assert_eq(first_request.method_name, "session/new")
    assert_eq(first_request.id, Number(1))
    input.put(
      Some(
        @utf8.encode(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"sessionId\":\"first\"}}\n",
        ),
      ),
    )
    ignore(written.get())
    let second_request = broker_channel_test_request(output[1])
    assert_eq(second_request.method_name, "session/new")
    assert_eq(second_request.id, Number(2))
    input.put(
      Some(
        @utf8.encode(
          "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"second\"}}\n",
        ),
      ),
    )
    let (first, second) = submitter.wait()
    input.put(None)
    runner.wait()
    assert_eq(first.session_id, "first")
    assert_eq(second.session_id, "second")
  })
  assert_eq(output.length(), 2)
  assert_eq(responses, [Number(1), Number(2)])
  assert_eq(failures.length(), 0)
}

///|
async test "client connection over channel maps an undecodable reply to a typed mismatch" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = broker_channel_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => broker_channel_test_run(ports, captured))
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = client_connection_over_channel(channel~)
      try {
        let _ = connection.new_session(broker_channel_test_new_params("/first"))
        fail("expected a typed client connection reply mismatch")
      } catch {
        @client.ClientConnectionError::ClientConnectionReplyMismatch(
          method_name~,
          expected~,
          actual~
        ) => {
          assert_eq(method_name, "session/new")
          assert_eq(expected, "session/new")
          // The static discriminator is a closed category of the broker, not
          // a peer payload.
          assert_eq(actual, "malformed_result")
        }
        _ => fail("expected a typed client connection reply mismatch")
      }
    })
    ignore(written.get())
    input.put(
      Some(
        @utf8.encode(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"unexpected\":true}}\n",
        ),
      ),
    )
    submitter.wait()
    input.put(None)
    runner.wait()
  })
  assert_eq(output.length(), 1)
  assert_eq(responses, [Number(1)])
  assert_eq(failures.length(), 0)
}

///|
async test "client connection over channel reports notifications as typed unavailability" {
  // The submitter classifies its own failure inside its task, so an expected
  // typed unavailability never fails the shared task group.
  let observed : Array[String] = []
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = broker_channel_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => broker_channel_test_run(ports, captured))
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = client_connection_over_channel(channel~)
      // The synchronous notification port fails fast with a typed error; it
      // never claims the notification reached the engine.
      try {
        connection.cancel_request(String("peer-request"))
        observed.push("unexpected-success")
      } catch {
        ClientConnectionUnavailable(method_name~) => observed.push(method_name)
        _ => observed.push("unexpected-error")
      }
    })
    submitter.wait()
    input.put(None)
    runner.wait()
  })
  assert_eq(observed, ["$/cancel_request"])
  assert_eq(output.length(), 0)
  assert_eq(responses.length(), 0)
  assert_eq(failures.length(), 0)
}
