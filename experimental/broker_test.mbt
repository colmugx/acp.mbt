///|
/// Deterministic in-memory ports for the v2 over-channel broker tests: the
/// reader is fed from one unbounded queue (`None` is EOF), the writer records
/// frames and signals each write, and the response and outbound-failure
/// callbacks record typed ids so exactly-once settle is observable without
/// engine internals.  No real I/O, timers, or sleeps are involved.
fn experimental_v2_broker_test_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[@runtime.RuntimeTraceEvent],
  responses : Array[String],
  failures : Array[(@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind)],
) -> @runtime.RuntimePorts {
  {
    reader: { read: _ => input.get(), },
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
fn experimental_v2_broker_test_owner_port() -> @connection.RuntimeOwnerPort[
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
        response: HandlerSuccess(Json::null()),
        effects: [],
      })
    },
    admit_notification: (_state, _notification) => {
      RuntimeOwnerNotificationImmediate(completion={ state: (), effects: [], })
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
/// Run the one owner engine and capture its outbound channel for the test
/// body, mirroring the engine whitebox harness without engine internals.
async fn experimental_v2_broker_test_run(
  ports : @runtime.RuntimePorts,
  captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]],
) -> Unit {
  @connection.connection_runtime_run_owner_with_outbound(
    ports,
    @runtime.runtime_default_options(),
    channel => {
      let _ = captured.try_put(channel) catch { _ => false }
      experimental_v2_broker_test_owner_port()
    },
  )
}

///|
fn experimental_v2_broker_test_chunk(frame : String) -> Bytes? {
  Some(@utf8.encode(frame))
}

///|
fn experimental_v2_broker_test_request(
  frame : Bytes,
) -> @jsonrpc.JsonRpcRequest raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Request(request) => request
    _ => fail("expected one JSON-RPC request frame")
  }
}

///|
fn experimental_v2_broker_test_notification(
  frame : Bytes,
) -> @jsonrpc.JsonRpcNotification raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Notification(notification) => notification
    _ => fail("expected one JSON-RPC notification frame")
  }
}

///|
fn experimental_v2_broker_test_request_params(
  request : @jsonrpc.JsonRpcRequest,
) -> Json raise {
  match request.params {
    Some(params) => params
    None => fail("expected the outbound request to carry params")
  }
}

///|
fn experimental_v2_broker_test_notification_params(
  notification : @jsonrpc.JsonRpcNotification,
) -> Json raise {
  match notification.params {
    Some(params) => params
    None => fail("expected the outbound notification to carry params")
  }
}

///|
async test "v2 client connection over channel round-trips initialize and pins version 2" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_broker_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      experimental_v2_broker_test_run(ports, captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = experimental_v2_client_connection_over_channel(channel~)
      let params = experimental_v2_client_initialize_params(
        info=experimental_v2_client_test_info("client"),
        capabilities=experimental_v2_client_test_capabilities(),
      )
      let accepted = connection.initialize(params)
      let offers : Array[Int] = []
      try connection.initialize({ ..params, meta: None, }) catch {
        UnsupportedVersion(method_name~, offered~) => {
          assert_eq(method_name, "initialize")
          offers.push(offered)
          ()
        }
        _ => fail("expected a typed unsupported-version failure")
      } noraise {
        _ => fail("expected a typed unsupported-version failure")
      }
      assert_eq(offers, [1])
      (accepted.protocol_version, accepted.info)
    })
    ignore(written.get())
    assert_eq(
      experimental_v2_broker_test_request(output[0]).method_name,
      "initialize",
    )
    input.put(
      experimental_v2_broker_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":2,\"info\":{\"name\":\"agent\",\"version\":\"1\"},\"capabilities\":{\"session\":{}}}}\n",
      ),
    )
    ignore(written.get())
    input.put(
      experimental_v2_broker_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"protocolVersion\":1,\"info\":{\"name\":\"agent\",\"version\":\"1\"}}}\n",
      ),
    )
    let (version, info) = submitter.wait()
    input.put(None)
    runner.wait()
    assert_eq(version, 2)
    assert_eq(info, experimental_v2_client_test_info("agent"))
  })
  assert_eq(output.length(), 2)
  assert_eq(responses, ["1", "2"])
  assert_eq(failures.length(), 0)
}

///|
async test "v2 client connection over channel maps an undecodable reply to a typed mismatch" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_broker_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      experimental_v2_broker_test_run(ports, captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = experimental_v2_client_connection_over_channel(channel~)
      try {
        let _ = connection.prompt({
          session_id: "session",
          prompt: [],
          meta: None,
        })
        fail("expected a typed reply mismatch")
      } catch {
        ExperimentalV2ClientConnectionError::ReplyMismatch(method_name~) =>
          assert_eq(method_name, "session/prompt")
        _ => fail("expected a typed reply mismatch")
      }
    })
    ignore(written.get())
    input.put(
      experimental_v2_broker_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"unexpected\":true}}\n",
      ),
    )
    submitter.wait()
    input.put(None)
    runner.wait()
  })
  assert_eq(output.length(), 1)
  assert_eq(responses, ["1"])
  assert_eq(failures.length(), 0)
}

///|
async test "v2 client connection over channel classifies wire error codes" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_broker_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      experimental_v2_broker_test_run(ports, captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = experimental_v2_client_connection_over_channel(channel~)
      let params : ExperimentalV2NewSessionParams = {
        cwd: "/",
        additional_directories: None,
        mcp_servers: None,
        meta: None,
      }
      try {
        let _ = connection.new_session(params)
        fail("expected a typed cancellation")
      } catch {
        ExperimentalV2ClientConnectionError::Cancelled(method_name~) =>
          assert_eq(method_name, "session/new")
        _ => fail("expected a typed cancellation")
      }
      try {
        let _ = connection.new_session({ ..params, cwd: "/second", })
        fail("expected a typed broker failure")
      } catch {
        ExperimentalV2ClientConnectionError::BrokerFailure(method_name~) =>
          assert_eq(method_name, "session/new")
        _ => fail("expected a typed broker failure")
      }
    })
    ignore(written.get())
    input.put(
      experimental_v2_broker_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32800,\"message\":\"cancelled\"}}\n",
      ),
    )
    ignore(written.get())
    input.put(
      experimental_v2_broker_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32603,\"message\":\"denied\"}}\n",
      ),
    )
    submitter.wait()
    input.put(None)
    runner.wait()
  })
  assert_eq(output.length(), 2)
  assert_eq(responses, ["1", "2"])
  assert_eq(failures.length(), 0)
}

///|
async test "v2 client connection over channel submits sync notifications" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_broker_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      experimental_v2_broker_test_run(ports, captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = experimental_v2_client_connection_over_channel(channel~)
      connection.cancel_session({ session_id: "session", meta: None, })
      connection.cancel_request(RequestIdStr("peer-request"))
    })
    ignore(written.get())
    ignore(written.get())
    submitter.wait()
    input.put(None)
    runner.wait()
    assert_eq(output.length(), 2)
    match @jsonrpc.jsonrpc_decode(@utf8.decode(output[0].view())) {
      Notification(notification) => {
        assert_eq(notification.method_name, "session/cancel")
        guard notification.params is Some(Object(fields)) else {
          fail("expected session/cancel params")
        }
        assert_true(fields.get("sessionId") is Some(String("session")))
      }
      _ => fail("expected exactly one session/cancel frame")
    }
    match @jsonrpc.jsonrpc_decode(@utf8.decode(output[1].view())) {
      Notification(notification) => {
        assert_eq(notification.method_name, "$/cancel_request")
        guard notification.params is Some(Object(fields)) else {
          fail("expected $/cancel_request params")
        }
        assert_true(fields.get("requestId") is Some(String("peer-request")))
      }
      _ => fail("expected exactly one $/cancel_request frame")
    }
    assert_eq(responses.length(), 0)
    assert_eq(failures.length(), 0)
  })
}

///|
async test "v2 client connection over channel maps closed notifications to typed unavailability" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_broker_test_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      experimental_v2_broker_test_run(ports, captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      // Hand the engine-owned channel back before the engine closes so the
      // post-close check reuses the exact handle the engine constructed.
      let _ = captured.try_put(channel) catch { _ => false }
    })
    submitter.wait()
    input.put(None)
    runner.wait()
    let channel = captured.get()
    let connection = experimental_v2_client_connection_over_channel(channel~)
    try {
      connection.cancel_session({ session_id: "session", meta: None, })
      fail("expected a typed unavailability")
    } catch {
      ExperimentalV2ClientConnectionError::Unavailable(method_name~) =>
        assert_eq(method_name, "session/cancel")
      _ => fail("expected a typed unavailability")
    }
    assert_eq(output.length(), 0)
    assert_eq(responses.length(), 0)
    assert_eq(failures.length(), 0)
  })
}
