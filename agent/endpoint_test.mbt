///|
async fn agent_endpoint_test_failing_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  raise HandlerError::Application(message="backend unavailable")
}

///|
async fn agent_endpoint_test_thrown_cancel_new(
  _context : AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.pause()
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  abort("expected task cancellation")
}

///|
async test "typed async endpoint handlers and context ports are callable" {
  let spec = agent_spec(
    info=agent_service_test_info("async"),
    sessions=agent_service_test_sessions(false),
    support=agent_support(),
  ).unwrap()
  let endpoint = agent_endpoint_from_spec(spec)
  let context = agent_service_test_context()
  let new_result = endpoint.new_session(context, {
    cwd: "/",
    additional_directories: Omitted,
    mcp_servers: [],
    meta: Omitted,
  })
  assert_eq(new_result.session_id, "created")
  let prompt_result = endpoint.prompt(context, {
    session_id: "s",
    prompt: [],
    meta: Omitted,
  })
  assert_eq(prompt_result.stop_reason, EndTurn)
  endpoint.cancel(context, { session_id: "s", meta: Omitted })
  context.session_update({
    session_id: "s",
    update: CurrentModeUpdate({ current_mode_id: "mode", meta: Omitted }),
    meta: Omitted,
  })
  let permission_result = context.request_permission({
    session_id: "s",
    tool_call: {
      tool_call_id: "call",
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
  })
  assert_true(permission_result.outcome is Cancelled)
}

///|
async test "generic handler errors are normalized at the endpoint boundary" {
  let spec = agent_spec(
    info=agent_service_test_info("error-boundary"),
    sessions=agent_session_service(
      new_session=agent_endpoint_test_failing_new,
      prompt=agent_service_test_prompt,
      cancel=agent_service_test_cancel,
    ),
    support=agent_support(),
  ).unwrap()
  let endpoint = agent_endpoint_from_spec(spec)
  try
    endpoint.new_session(agent_service_test_context(), {
      cwd: "/",
      additional_directories: Omitted,
      mcp_servers: [],
      meta: Omitted,
    })
  catch {
    Application(message~) =>
      assert_eq(message, "session/new: backend unavailable")
    _ => fail("expected structured application error")
  } noraise {
    _ => fail("expected failing handler to raise")
  }
}

///|
async test "endpoint preserves real task cancellation as structured cancellation" {
  let spec = agent_spec(
    info=agent_service_test_info("task-cancel"),
    sessions=agent_session_service(
      new_session=agent_endpoint_test_thrown_cancel_new,
      prompt=agent_service_test_prompt,
      cancel=agent_service_test_cancel,
    ),
    support=agent_support(),
  ).unwrap()
  let endpoint = agent_endpoint_from_spec(spec)
  try
    endpoint.new_session(agent_service_test_context(), {
      cwd: "/",
      additional_directories: Omitted,
      mcp_servers: [],
      meta: Omitted,
    })
  catch {
    Cancelled => ()
    _ => fail("real task cancellation must remain structured cancellation")
  } noraise {
    _ => fail("real task cancellation must raise")
  }
}

///|
async test "missing optional operation fails instead of falling back" {
  let spec = agent_spec(
    info=agent_service_test_info("optional"),
    sessions=agent_service_test_sessions(false),
    support=agent_support(),
  ).unwrap()
  let endpoint = agent_endpoint_from_spec(spec)
  try
    endpoint.load_session(agent_service_test_context(), {
      mcp_servers: [],
      cwd: "/",
      additional_directories: Omitted,
      session_id: "s",
      meta: Omitted,
    })
  catch {
    UnavailableOperation(method_name="session/load") => ()
    _ => fail("expected missing optional operation to fail")
  } noraise {
    _ => fail("expected missing optional operation to fail")
  }
}
