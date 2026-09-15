///|
fn agent_context_test_permission_request() -> RequestPermissionRequest {
  {
    session_id: "session",
    tool_call: {
      tool_call_id: "tool-call",
      kind: Omitted,
      status: Omitted,
      title: Omitted,
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Omitted,
      meta: Omitted,
    },
    options: [],
    meta: Omitted,
  }
}

///|
fn agent_context_test_read_params() -> ReadTextFileParams {
  {
    session_id: "session",
    path: "/tmp/context.txt",
    line: Omitted,
    limit: Omitted,
    meta: Omitted,
  }
}

///|
fn agent_context_test_write_params() -> WriteTextFileParams {
  {
    session_id: "session",
    path: "/tmp/context.txt",
    content: "typed",
    meta: Omitted,
  }
}

///|
fn agent_context_test_terminal_create_params() -> TerminalCreateParams {
  {
    session_id: "session",
    command: "printf",
    args: Omitted,
    env: Omitted,
    cwd: Omitted,
    output_byte_limit: Omitted,
    meta: Omitted,
  }
}

///|
fn agent_context_test_terminal_output_params() -> TerminalOutputParams {
  { session_id: "session", terminal_id: "terminal", meta: Omitted, }
}

///|
fn agent_context_test_terminal_wait_params() -> TerminalWaitForExitParams {
  { session_id: "session", terminal_id: "terminal", meta: Omitted, }
}

///|
fn agent_context_test_terminal_kill_params() -> TerminalKillParams {
  { session_id: "session", terminal_id: "terminal", meta: Omitted, }
}

///|
fn agent_context_test_terminal_release_params() -> TerminalReleaseParams {
  { session_id: "session", terminal_id: "terminal", meta: Omitted, }
}

///|
fn agent_context_test_elicitation_params() -> ElicitationCreateParams {
  Form({
    scope: Request(String("request")),
    message: "Please choose",
    requested_schema: Json::object(Map([])),
    meta: Omitted,
  })
}

///|
fn agent_context_test_update_params() -> SessionUpdateParams {
  {
    session_id: "session",
    update: CurrentModeUpdate({ current_mode_id: "default", meta: Omitted, }),
    meta: Omitted,
  }
}

///|
fn agent_context_test_complete_params() -> ElicitationCompleteParams {
  { elicitation_id: "elicitation", meta: Omitted, }
}

///|
async fn agent_context_test_all_requests(
  request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  match request {
    SessionRequestPermission(params) => {
      assert_eq(params.session_id, "session")
      assert_eq(params.tool_call.tool_call_id, "tool-call")
      Ok(AgentReplyRequestPermission({ outcome: Cancelled, meta: Omitted, }))
    }
    FsReadTextFile(params) => {
      assert_eq(params.path, "/tmp/context.txt")
      Ok(AgentReplyFsReadTextFile({ content: "contents", meta: Omitted, }))
    }
    FsWriteTextFile(params) => {
      assert_eq(params.content, "typed")
      Ok(AgentReplyFsWriteTextFile({ meta: Omitted, }))
    }
    TerminalCreate(params) => {
      assert_eq(params.command, "printf")
      Ok(AgentReplyTerminalCreate({ terminal_id: "terminal", meta: Omitted, }))
    }
    TerminalOutput(params) => {
      assert_eq(params.terminal_id, "terminal")
      Ok(
        AgentReplyTerminalOutput({
          output: "output",
          truncated: false,
          exit_status: Omitted,
          meta: Omitted,
        }),
      )
    }
    TerminalWaitForExit(params) => {
      assert_eq(params.terminal_id, "terminal")
      Ok(
        AgentReplyTerminalWaitForExit({
          exit_code: Value(0UL),
          signal: Omitted,
          meta: Omitted,
        }),
      )
    }
    TerminalKill(params) => {
      assert_eq(params.terminal_id, "terminal")
      Ok(AgentReplyTerminalKill({ meta: Omitted, }))
    }
    TerminalRelease(params) => {
      assert_eq(params.terminal_id, "terminal")
      Ok(AgentReplyTerminalRelease({ meta: Omitted, }))
    }
    ElicitationCreate(Form(params)) => {
      assert_eq(params.message, "Please choose")
      Ok(
        AgentReplyElicitationCreate({
          action: Accept,
          content: Omitted,
          meta: Omitted,
        }),
      )
    }
    ElicitationCreate(Url(_)) => fail("expected the form elicitation fixture")
  }
}

///|
async fn agent_context_test_notifications(
  notification : ClientNotification,
) -> Result[Unit, AgentContextError] {
  @async.pause()
  match notification {
    SessionUpdate(params) => assert_eq(params.session_id, "session")
    ElicitationComplete(params) =>
      assert_eq(params.elicitation_id, "elicitation")
    CancelRequest(String(request_id)) => assert_eq(request_id, "request")
    CancelRequest(Number(_)) => fail("expected string cancellation id")
    CancelRequest(Null) => fail("expected string cancellation id")
  }
  Ok(())
}

///|
fn agent_context_test_all_methods_context() -> AgentContext {
  agent_context(
    request_broker=agent_context_test_all_requests,
    notification_broker=agent_context_test_notifications,
  )
}

///|
async test "AgentContext exposes every typed Client request and notification" {
  let context = agent_context_test_all_methods_context()
  let permission = context.request_permission(
    agent_context_test_permission_request(),
  )
  assert_true(permission.outcome is Cancelled)
  let read = context.read_text_file(agent_context_test_read_params())
  assert_eq(read.content, "contents")
  let write = context.write_text_file(agent_context_test_write_params())
  assert_true(write.meta is Omitted)
  let create = context.terminal_create(
    agent_context_test_terminal_create_params(),
  )
  assert_eq(create.terminal_id, "terminal")
  let output = context.terminal_output(
    agent_context_test_terminal_output_params(),
  )
  assert_eq(output.output, "output")
  let wait = context.terminal_wait_for_exit(
    agent_context_test_terminal_wait_params(),
  )
  assert_true(wait.exit_code is Value(0))
  let kill = context.terminal_kill(agent_context_test_terminal_kill_params())
  assert_true(kill.meta is Omitted)
  let release = context.terminal_release(
    agent_context_test_terminal_release_params(),
  )
  assert_true(release.meta is Omitted)
  let elicitation = context.elicitation_create(
    agent_context_test_elicitation_params(),
  )
  assert_true(elicitation.action is Accept)
  context.session_update(agent_context_test_update_params())
  context.elicitation_complete(agent_context_test_complete_params())
  context.cancel_request(String("request"))
}

///|
async fn agent_context_test_mismatch_request(
  _request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  Ok(AgentReplyFsReadTextFile({ content: "wrong", meta: Omitted, }))
}

///|
async test "AgentContext rejects a reply with the wrong typed variant" {
  let context = agent_context(
    request_broker=agent_context_test_mismatch_request,
    notification_broker=agent_context_test_notifications,
  )
  try
    context.request_permission(agent_context_test_permission_request())
  catch {
    AgentContextReplyMismatch(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected typed reply mismatch")
  } noraise {
    _ => fail("expected typed reply mismatch")
  }
}

///|
async fn agent_context_test_unavailable_request(
  request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  Err(AgentContextUnavailable(method_name=request.method_name()))
}

///|
async fn agent_context_test_cancelled_request(
  _request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  Err(AgentContextCancelled(method_name="terminal/kill"))
}

///|
async fn agent_context_test_broker_failure_request(
  _request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  Err(AgentContextBrokerFailure(method_name="terminal/release"))
}

///|
async fn agent_context_test_failing_notification(
  _notification : ClientNotification,
) -> Result[Unit, AgentContextError] {
  @async.pause()
  Err(AgentContextBrokerFailure(method_name="session/update"))
}

///|
async test "AgentContext preserves typed unavailable cancellation and broker failures" {
  let unavailable = agent_context(
    request_broker=agent_context_test_unavailable_request,
    notification_broker=agent_context_test_notifications,
  )
  try unavailable.read_text_file(agent_context_test_read_params()) catch {
    AgentContextUnavailable(method_name~) =>
      assert_eq(method_name, "fs/read_text_file")
    _ => fail("expected unavailable error")
  } noraise {
    _ => fail("expected unavailable error")
  }

  let cancelled = agent_context(
    request_broker=agent_context_test_cancelled_request,
    notification_broker=agent_context_test_notifications,
  )
  try cancelled.terminal_kill(agent_context_test_terminal_kill_params()) catch {
    AgentContextCancelled(method_name~) =>
      assert_eq(method_name, "terminal/kill")
    _ => fail("expected cancellation error")
  } noraise {
    _ => fail("expected cancellation error")
  }

  let failed = agent_context(
    request_broker=agent_context_test_broker_failure_request,
    notification_broker=agent_context_test_failing_notification,
  )
  try
    failed.terminal_release(agent_context_test_terminal_release_params())
  catch {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "terminal/release")
    _ => fail("expected broker failure")
  } noraise {
    _ => fail("expected broker failure")
  }
  try failed.session_update(agent_context_test_update_params()) catch {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/update")
    _ => fail("expected notification broker failure")
  } noraise {
    _ => fail("expected notification broker failure")
  }
}

///|
async fn agent_context_test_raise_cancelled(
  _request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  raise HandlerError::Cancelled
}

///|
async fn agent_context_test_thrown_cancel(
  _request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.pause()
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  Err(AgentContextBrokerFailure(method_name="unreachable"))
}

///|
async fn agent_context_test_raise_failure(
  _request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  raise HandlerError::Application(message="secret payload")
}

///|
async test "AgentContext distinguishes task cancellation from handler errors" {
  let cancelled = agent_context(
    request_broker=agent_context_test_raise_cancelled,
    notification_broker=agent_context_test_notifications,
  )
  try
    cancelled.request_permission(agent_context_test_permission_request())
  catch {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected non-cancellation handler error mapping")
  } noraise {
    _ => fail("expected non-cancellation handler error mapping")
  }

  let failed = agent_context(
    request_broker=agent_context_test_raise_failure,
    notification_broker=agent_context_test_notifications,
  )
  try failed.request_permission(agent_context_test_permission_request()) catch {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected redacted broker failure")
  } noraise {
    _ => fail("expected redacted broker failure")
  }
}

///|
async fn agent_context_test_thrown_notification_failure(
  _notification : ClientNotification,
) -> Result[Unit, AgentContextError] {
  @async.pause()
  raise HandlerError::Application(message="notification secret")
}

///|
async test "AgentContext maps thrown notification failures with method" {
  let context = agent_context(
    request_broker=agent_context_test_all_requests,
    notification_broker=agent_context_test_thrown_notification_failure,
  )
  try context.session_update(agent_context_test_update_params()) catch {
    AgentContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/update")
    _ => fail("expected thrown notification failure")
  } noraise {
    _ => fail("expected thrown notification failure")
  }
}

///|
async test "AgentContext maps actual task cancellation with method" {
  let context = agent_context(
    request_broker=agent_context_test_thrown_cancel,
    notification_broker=agent_context_test_notifications,
  )
  try
    context.request_permission(agent_context_test_permission_request())
  catch {
    AgentContextCancelled(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected actual task cancellation")
  } noraise {
    _ => fail("expected actual task cancellation")
  }
}

///|
async fn agent_context_test_first_context_request(
  request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  match request {
    SessionRequestPermission(_) =>
      Ok(AgentReplyRequestPermission({ outcome: Cancelled, meta: Omitted, }))
    other => Err(AgentContextUnavailable(method_name=other.method_name()))
  }
}

///|
async fn agent_context_test_second_context_request(
  request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  @async.pause()
  match request {
    SessionRequestPermission(_) =>
      Ok(
        AgentReplyRequestPermission({
          outcome: Selected({ option_id: "allow", meta: Omitted, }),
          meta: Omitted,
        }),
      )
    other => Err(AgentContextUnavailable(method_name=other.method_name()))
  }
}

///|
async test "two AgentContext values keep caller transports isolated" {
  let first = agent_context(
    request_broker=agent_context_test_first_context_request,
    notification_broker=agent_context_test_notifications,
  )
  let second = agent_context(
    request_broker=agent_context_test_second_context_request,
    notification_broker=agent_context_test_notifications,
  )
  let first_result = first.request_permission(
    agent_context_test_permission_request(),
  )
  let second_result = second.request_permission(
    agent_context_test_permission_request(),
  )
  assert_true(first_result.outcome is Cancelled)
  assert_true(second_result.outcome is Selected(_))
}

///|
async test "AgentContext defaults the clientInfo accessor to Omitted" {
  let context = agent_context(
    request_broker=agent_context_test_all_requests,
    notification_broker=agent_context_test_notifications,
  )
  assert_true((context.client_info)() is Omitted)
}
