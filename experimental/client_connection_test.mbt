///|
/// One in-process forward broker: every typed request is answered with the
/// queued reply or typed error, and submissions are recorded so the facade's
/// submission shape stays observable without real I/O.
#warnings("-unused_async")
fn experimental_v2_client_connection_test_broker(
  submitted : Array[ExperimentalV2ClientForwardRequest],
  replies : Array[
    Result[
      ExperimentalV2ClientForwardReply,
      ExperimentalV2ClientConnectionError,
    ],
  ],
) -> ExperimentalV2ClientForwardRequestBroker {
  let cursor : Ref[Int] = { val: 0 }
  async fn(request) {
    submitted.push(request)
    if cursor.val >= replies.length() {
      return Err(BrokerFailure(method_name=request.method_name()))
    }
    let reply = replies[cursor.val]
    cursor.val += 1
    reply
  }
}

///|
async test "v2 client connection forwards initialize and pins version 2" {
  let submitted : Array[ExperimentalV2ClientForwardRequest] = []
  let agent_info = experimental_v2_client_test_info("agent")
  let connection = experimental_v2_client_connection(
    request_broker=experimental_v2_client_connection_test_broker(submitted, [
      Ok(
        ReplyInitialize({
          protocol_version: 2,
          info: agent_info,
          capabilities: {
            session: MarkerSupported({
              prompt: MarkerUnsupported,
              mcp: MarkerUnsupported,
              delete: MarkerUnsupported,
              additional_directories: MarkerUnsupported,
              meta: None,
            }),
            auth: MarkerUnsupported,
            meta: None,
          },
          auth_methods: None,
          meta: None,
        }),
      ),
    ]),
    notification_broker=_notification => Ok(()),
  )
  let result = connection.initialize({
    protocol_version: 2,
    info: experimental_v2_client_test_info("client"),
    capabilities: experimental_v2_client_test_capabilities(),
    meta: None,
  })
  assert_eq(result.protocol_version, 2)
  assert_eq(result.info, agent_info)
  assert_eq(submitted.length(), 1)
  assert_true(submitted[0] is Initialize(_))
  // A non-pinned result is the state machine's terminal typed failure.
  let rejected = experimental_v2_client_connection(
    request_broker=experimental_v2_client_connection_test_broker(submitted, [
      Ok(
        ReplyInitialize({
          protocol_version: 1,
          info: agent_info,
          capabilities: {
            session: MarkerUnsupported,
            auth: MarkerUnsupported,
            meta: None,
          },
          auth_methods: None,
          meta: None,
        }),
      ),
    ]),
    notification_broker=_notification => Ok(()),
  )
  try
    rejected.initialize({
      protocol_version: 2,
      info: experimental_v2_client_test_info("client"),
      capabilities: experimental_v2_client_test_capabilities(),
      meta: None,
    })
  catch {
    UnsupportedVersion(method_name~, offered~) => {
      assert_eq(method_name, "initialize")
      assert_eq(offered, 1)
    }
    _ => fail("expected a typed unsupported-version failure")
  } noraise {
    _ => fail("expected a typed unsupported-version failure")
  }
  // Non-pinned outgoing params never reach the broker.
  try
    rejected.initialize({
      protocol_version: 3,
      info: experimental_v2_client_test_info("client"),
      capabilities: experimental_v2_client_test_capabilities(),
      meta: None,
    })
  catch {
    UnsupportedVersion(method_name~, offered~) => {
      assert_eq(method_name, "initialize")
      assert_eq(offered, 3)
    }
    _ => fail("expected a typed unsupported-version failure")
  } noraise {
    _ => fail("expected a typed unsupported-version failure")
  }
  assert_eq(submitted.length(), 2)
}

///|
async test "v2 client connection reports mismatched replies typed" {
  let submitted : Array[ExperimentalV2ClientForwardRequest] = []
  let connection = experimental_v2_client_connection(
    request_broker=experimental_v2_client_connection_test_broker(submitted, [
      Ok(ReplyCloseSession({ meta: None })),
    ]),
    notification_broker=_notification => Ok(()),
  )
  try
    connection.prompt({ session_id: "session", prompt: [], meta: None })
  catch {
    ReplyMismatch(method_name~) =>
      assert_eq(method_name, "session/prompt: session/close")
    _ => fail("expected a typed reply mismatch")
  } noraise {
    _ => fail("expected a typed reply mismatch")
  }
  assert_true(submitted[0] is SessionPrompt(_))
}

///|
async test "v2 client connection classifies broker failures and cancels" {
  let submitted : Array[ExperimentalV2ClientForwardRequest] = []
  let cancelled = experimental_v2_client_connection(
    request_broker=experimental_v2_client_connection_test_broker(submitted, [
      Err(Cancelled(method_name="session/new")),
    ]),
    notification_broker=_notification => Ok(()),
  )
  try
    cancelled.new_session({
      cwd: "/",
      additional_directories: None,
      mcp_servers: None,
      meta: None,
    })
  catch {
    Cancelled(method_name~) => assert_eq(method_name, "session/new")
    _ => fail("expected a typed cancellation")
  } noraise {
    _ => fail("expected a typed cancellation")
  }
  // A broker that raises a foreign exception is classified as a broker
  // failure, never a success.
  let defect = experimental_v2_client_connection(
    request_broker=async fn(request) {
      ignore(request)
      @async.pause()
      raise ExperimentalV2ClientHandlerError::Application(message="defect")
    },
    notification_broker=_notification => Ok(()),
  )
  try defect.list_sessions({ cwd: None, cursor: None, meta: None }) catch {
    BrokerFailure(method_name~) => assert_eq(method_name, "session/list")
    _ => fail("expected a typed broker failure")
  } noraise {
    _ => fail("expected a typed broker failure")
  }
}

///|
async test "v2 client connection submits notifications synchronously" {
  let notifications : Array[ExperimentalV2ClientForwardNotification] = []
  let connection = experimental_v2_client_connection(
    request_broker=experimental_v2_client_connection_test_broker([], []),
    notification_broker=notification => {
      notifications.push(notification)
      Ok(())
    },
  )
  connection.cancel_session({ session_id: "session", meta: None })
  connection.cancel_request(RequestIdNumber(7))
  assert_eq(notifications, [
    SessionCancel({ session_id: "session", meta: None }),
    CancelRequest(RequestIdNumber(7)),
  ])
}
