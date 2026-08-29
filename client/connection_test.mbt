///|
fn client_connection_test_initialize() -> InitializeParams {
  {
    protocol_version: 1,
    client_capabilities: Omitted,
    client_info: Omitted,
    meta: Omitted,
  }
}

///|
fn client_connection_test_initialize_v2_request() -> InitializeParams {
  {
    protocol_version: 2,
    client_capabilities: Omitted,
    client_info: Omitted,
    meta: Omitted,
  }
}

///|
fn client_connection_test_authenticate() -> AuthenticateParams {
  { method_id: "token", meta: Omitted, }
}

///|
fn client_connection_test_logout() -> LogoutParams {
  { meta: Omitted, }
}

///|
fn client_connection_test_new_session() -> NewSessionParams {
  {
    cwd: "/tmp",
    additional_directories: Omitted,
    mcp_servers: [],
    meta: Omitted,
  }
}

///|
fn client_connection_test_load_session() -> LoadSessionParams {
  {
    mcp_servers: [],
    cwd: "/tmp",
    additional_directories: Omitted,
    session_id: "session",
    meta: Omitted,
  }
}

///|
fn client_connection_test_resume_session() -> ResumeSessionParams {
  {
    session_id: "session",
    cwd: "/tmp",
    additional_directories: Omitted,
    mcp_servers: Omitted,
    meta: Omitted,
  }
}

///|
fn client_connection_test_fork_session() -> ForkSessionParams {
  {
    cwd: "/tmp",
    session_id: "session",
    additional_directories: Omitted,
    mcp_servers: Omitted,
    meta: Omitted,
  }
}

///|
fn client_connection_test_list_sessions() -> ListSessionsParams {
  { cwd: Omitted, cursor: Omitted, meta: Omitted, }
}

///|
fn client_connection_test_delete_session() -> DeleteSessionParams {
  { session_id: "session", meta: Omitted, }
}

///|
fn client_connection_test_close_session() -> CloseSessionParams {
  { session_id: "session", meta: Omitted, }
}

///|
fn client_connection_test_set_mode() -> SetSessionModeParams {
  { session_id: "session", mode_id: "default", meta: Omitted, }
}

///|
fn client_connection_test_set_config_option() -> SetSessionConfigOptionParams {
  {
    session_id: "session",
    config_id: "verbose",
    value: Boolean(true),
    meta: Omitted,
  }
}

///|
fn client_connection_test_prompt() -> PromptParams {
  { session_id: "session", prompt: [], meta: Omitted, }
}

///|
fn client_connection_test_broker_failure(
  method_name : String,
) -> ClientConnectionError {
  ClientConnectionBrokerFailure(method_name~)
}

///|
async fn client_connection_test_request_broker(
  request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  match request {
    Initialize(params) =>
      if params == client_connection_test_initialize() {
        Ok(
          ClientReplyInitialize({
            protocol_version: 1,
            agent_capabilities: Omitted,
            auth_methods: Omitted,
            agent_info: Omitted,
            meta: Omitted,
          }),
        )
      } else {
        Err(client_connection_test_broker_failure("initialize"))
      }
    Authenticate(params) =>
      if params == client_connection_test_authenticate() {
        Ok(ClientReplyAuthenticate({ meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("authenticate"))
      }
    Logout(params) =>
      if params == client_connection_test_logout() {
        Ok(ClientReplyLogout({ meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("logout"))
      }
    SessionNew(params) =>
      if params == client_connection_test_new_session() {
        Ok(
          ClientReplyNewSession({
            session_id: "new-session",
            modes: Omitted,
            config_options: Omitted,
            meta: Omitted,
          }),
        )
      } else {
        Err(client_connection_test_broker_failure("session/new"))
      }
    SessionLoad(params) =>
      if params == client_connection_test_load_session() {
        Ok(
          ClientReplyLoadSession({
            modes: Omitted,
            config_options: Omitted,
            meta: Omitted,
          }),
        )
      } else {
        Err(client_connection_test_broker_failure("session/load"))
      }
    SessionResume(params) =>
      if params == client_connection_test_resume_session() {
        Ok(
          ClientReplyResumeSession({
            modes: Omitted,
            config_options: Omitted,
            meta: Omitted,
          }),
        )
      } else {
        Err(client_connection_test_broker_failure("session/resume"))
      }
    SessionFork(params) =>
      if params == client_connection_test_fork_session() {
        Ok(
          ClientReplyForkSession({
            session_id: "forked-session",
            modes: Omitted,
            config_options: Omitted,
            meta: Omitted,
          }),
        )
      } else {
        Err(client_connection_test_broker_failure("session/fork"))
      }
    SessionList(params) =>
      if params == client_connection_test_list_sessions() {
        Ok(
          ClientReplyListSessions({
            sessions: [],
            next_cursor: Omitted,
            meta: Omitted,
          }),
        )
      } else {
        Err(client_connection_test_broker_failure("session/list"))
      }
    SessionDelete(params) =>
      if params == client_connection_test_delete_session() {
        Ok(ClientReplyDeleteSession({ meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("session/delete"))
      }
    SessionClose(params) =>
      if params == client_connection_test_close_session() {
        Ok(ClientReplyCloseSession({ meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("session/close"))
      }
    SessionSetMode(params) =>
      if params == client_connection_test_set_mode() {
        Ok(ClientReplySetMode({ meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("session/set_mode"))
      }
    SessionSetConfigOption(params) =>
      if params == client_connection_test_set_config_option() {
        Ok(ClientReplySetConfigOption({ config_options: [], meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("session/set_config_option"))
      }
    SessionPrompt(params) =>
      if params == client_connection_test_prompt() {
        Ok(ClientReplyPrompt({ stop_reason: EndTurn, meta: Omitted, }))
      } else {
        Err(client_connection_test_broker_failure("session/prompt"))
      }
  }
}

///|
fn client_connection_test_notification_broker(
  notification : AgentNotification,
) -> Result[Unit, ClientConnectionError] {
  match notification {
    SessionCancel(params) =>
      if params == { session_id: "session", meta: Omitted, } {
        Ok(())
      } else {
        Err(client_connection_test_broker_failure("session/cancel"))
      }
    CancelRequest(request_id) =>
      if request_id == String("cancel") || request_id == Number(7) {
        Ok(())
      } else {
        Err(client_connection_test_broker_failure("$/cancel_request"))
      }
  }
}

///|
fn client_connection_test_connection() -> ClientConnection {
  client_connection(
    request_broker=client_connection_test_request_broker,
    notification_broker=client_connection_test_notification_broker,
  )
}

///|
async test "ClientConnection maps every stable request to typed reply" {
  let connection = client_connection_test_connection()
  assert_eq(
    connection.initialize(client_connection_test_initialize()).protocol_version,
    1,
  )
  ignore(connection.authenticate(client_connection_test_authenticate()))
  ignore(connection.logout(client_connection_test_logout()))
  assert_eq(
    connection.new_session(client_connection_test_new_session()).session_id,
    "new-session",
  )
  ignore(connection.load_session(client_connection_test_load_session()))
  ignore(connection.resume_session(client_connection_test_resume_session()))
  assert_eq(
    connection.fork_session(client_connection_test_fork_session()).session_id,
    "forked-session",
  )
  assert_eq(
    connection.list_sessions(client_connection_test_list_sessions()).sessions,
    [],
  )
  ignore(connection.delete_session(client_connection_test_delete_session()))
  ignore(connection.close_session(client_connection_test_close_session()))
  ignore(connection.set_mode(client_connection_test_set_mode()))
  ignore(
    connection.set_config_option(client_connection_test_set_config_option()),
  )
  assert_eq(
    connection.prompt(client_connection_test_prompt()).stop_reason,
    EndTurn,
  )
}

///|
test "ClientConnection emits typed cancellation notifications" {
  let connection = client_connection_test_connection()
  connection.cancel({ session_id: "session", meta: Omitted, })
  connection.cancel_request(String("cancel"))
  connection.cancel_request(Number(7))
}

///|
async fn client_connection_test_mismatch_broker(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Ok(ClientReplyLogout({ meta: Omitted, }))
}

///|
async test "ClientConnection rejects mismatched replies" {
  let connection = client_connection(
    request_broker=client_connection_test_mismatch_broker,
    notification_broker=client_connection_test_notification_broker,
  )
  let error = try
    connection.initialize(client_connection_test_initialize())
  catch {
    error => error
  } noraise {
    _ => fail("reply mismatch must be an explicit error")
  }
  match error {
    ClientConnectionReplyMismatch(method_name~, expected~, actual~) => {
      assert_eq(method_name, "initialize")
      assert_eq(expected, "initialize")
      assert_eq(actual, "logout")
    }
    _ => fail("wrong error for reply mismatch")
  }
}

///|
async fn client_connection_test_fork_mismatch_broker(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Ok(ClientReplyDeleteSession({ meta: Omitted, }))
}

///|
async test "ClientConnection rejects a fork reply carrying another method" {
  let connection = client_connection(
    request_broker=client_connection_test_fork_mismatch_broker,
    notification_broker=client_connection_test_notification_broker,
  )
  let error = try
    connection.fork_session(client_connection_test_fork_session())
  catch {
    error => error
  } noraise {
    _ => fail("fork reply mismatch must be an explicit error")
  }
  match error {
    ClientConnectionReplyMismatch(method_name~, expected~, actual~) => {
      assert_eq(method_name, "session/fork")
      assert_eq(expected, "session/fork")
      assert_eq(actual, "session/delete")
    }
    _ => fail("wrong error for fork reply mismatch")
  }
}

///|
async fn client_connection_test_unavailable_broker(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Err(ClientConnectionUnavailable(method_name="session/new"))
}

///|
async fn client_connection_test_cancelled_broker(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Err(ClientConnectionCancelled(method_name="initialize"))
}

///|
async fn client_connection_test_failed_broker(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Err(ClientConnectionBrokerFailure(method_name="initialize"))
}

///|
async fn client_connection_test_thrown_cancel(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.sleep(1000)
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  Err(ClientConnectionBrokerFailure(method_name="initialize"))
}

///|
async fn client_connection_test_thrown_failure(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  raise Failure("transport detail must not cross the facade")
}

///|
async test "ClientConnection preserves explicit broker failures" {
  let unavailable = client_connection(
    request_broker=client_connection_test_unavailable_broker,
    notification_broker=client_connection_test_notification_broker,
  )
  let unavailable_error = try
    unavailable.new_session(client_connection_test_new_session())
  catch {
    error => error
  } noraise {
    _ => fail("unavailable broker result must be raised")
  }
  assert_true(
    unavailable_error is ClientConnectionUnavailable(method_name="session/new"),
  )

  let cancelled = client_connection(
    request_broker=client_connection_test_cancelled_broker,
    notification_broker=client_connection_test_notification_broker,
  )
  let cancelled_error = try
    cancelled.initialize(client_connection_test_initialize())
  catch {
    error => error
  } noraise {
    _ => fail("cancelled broker result must be raised")
  }
  assert_true(
    cancelled_error is ClientConnectionCancelled(method_name="initialize"),
  )

  let failed = client_connection(
    request_broker=client_connection_test_failed_broker,
    notification_broker=client_connection_test_notification_broker,
  )
  let failed_error = try
    failed.initialize(client_connection_test_initialize())
  catch {
    error => error
  } noraise {
    _ => fail("broker failure result must be raised")
  }
  assert_true(
    failed_error is ClientConnectionBrokerFailure(method_name="initialize"),
  )
}

///|
async test "ClientConnection maps thrown cancellation and failure explicitly" {
  let cancelled = client_connection(
    request_broker=client_connection_test_thrown_cancel,
    notification_broker=client_connection_test_notification_broker,
  )
  let cancelled_error = try
    cancelled.initialize(client_connection_test_initialize())
  catch {
    error => error
  } noraise {
    _ => fail("thrown cancellation must be observable")
  }
  assert_true(
    cancelled_error is ClientConnectionCancelled(method_name="initialize"),
  )

  let failed = client_connection(
    request_broker=client_connection_test_thrown_failure,
    notification_broker=client_connection_test_notification_broker,
  )
  let failed_error = try
    failed.initialize(client_connection_test_initialize())
  catch {
    error => error
  } noraise {
    _ => fail("thrown broker failure must be observable")
  }
  assert_true(
    failed_error is ClientConnectionBrokerFailure(method_name="initialize"),
  )
}

///|
async fn client_connection_test_initialize_v1(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Ok(
    ClientReplyInitialize({
      protocol_version: 1,
      agent_capabilities: Omitted,
      auth_methods: Omitted,
      agent_info: Omitted,
      meta: Omitted,
    }),
  )
}

///|
async fn client_connection_test_initialize_invalid_result(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Ok(
    ClientReplyInitialize({
      protocol_version: 2,
      agent_capabilities: Omitted,
      auth_methods: Omitted,
      agent_info: Omitted,
      meta: Omitted,
    }),
  )
}

///|
async fn client_connection_test_initialize_v1_other_info(
  _request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  @async.pause()
  Ok(
    ClientReplyInitialize({
      protocol_version: 1,
      agent_capabilities: Omitted,
      auth_methods: Omitted,
      agent_info: Value({
        name: "other-agent",
        title: Omitted,
        version: "test",
        meta: Omitted,
      }),
      meta: Omitted,
    }),
  )
}

///|
fn client_connection_test_noop_notification(
  _notification : AgentNotification,
) -> Result[Unit, ClientConnectionError] {
  Ok(())
}

///|
async test "ClientConnection instances isolate their injected brokers" {
  let first = client_connection(
    request_broker=client_connection_test_initialize_v1,
    notification_broker=client_connection_test_noop_notification,
  )
  let second = client_connection(
    request_broker=client_connection_test_initialize_v1_other_info,
    notification_broker=client_connection_test_noop_notification,
  )
  let first_result = first.initialize(client_connection_test_initialize())
  let second_result = second.initialize(client_connection_test_initialize())
  assert_eq(first_result.protocol_version, 1)
  assert_eq(second_result.protocol_version, 1)
  match (first_result.agent_info, second_result.agent_info) {
    (Omitted, Value(info)) => assert_eq(info.name, "other-agent")
    _ => fail("isolated v1 brokers must keep distinct agent info")
  }
}

///|
async test "ClientConnection rejects non-v1 initialize request and result" {
  let request_version = client_connection(
    request_broker=client_connection_test_initialize_v1,
    notification_broker=client_connection_test_noop_notification,
  )
  let request_error = try
    request_version.initialize(client_connection_test_initialize_v2_request())
  catch {
    error => error
  } noraise {
    _ => fail("non-v1 initialize request must be rejected")
  }
  match request_error {
    ClientConnectionUnsupportedVersion(method_name="initialize", version=2) =>
      ()
    _ => fail("wrong error for non-v1 initialize request")
  }

  let result_version = client_connection(
    request_broker=client_connection_test_initialize_invalid_result,
    notification_broker=client_connection_test_noop_notification,
  )
  let result_error = try
    result_version.initialize(client_connection_test_initialize())
  catch {
    error => error
  } noraise {
    _ => fail("non-v1 initialize result must be rejected")
  }
  match result_error {
    ClientConnectionUnsupportedVersion(method_name="initialize", version=2) =>
      ()
    _ => fail("wrong error for non-v1 initialize result")
  }
}
