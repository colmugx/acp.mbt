///|
fn agent_service_test_info(name : String) -> Implementation {
  { name, title: Omitted, version: "test", meta: Omitted, }
}

///|
async fn agent_service_test_new(
  _context : @agent.AgentContext,
  _params : NewSessionParams,
) -> NewSessionResult {
  @async.pause()
  {
    session_id: "created",
    modes: Omitted,
    config_options: Omitted,
    meta: Omitted,
  }
}

///|
async fn agent_service_test_prompt(
  _context : @agent.AgentContext,
  _params : PromptParams,
) -> PromptResult {
  @async.pause()
  { stop_reason: EndTurn, meta: Omitted, }
}

///|
async fn agent_service_test_cancel(
  _context : @agent.AgentContext,
  _params : CancelParams,
) -> Unit {
  @async.pause()
}

///|
async fn agent_service_test_load(
  _context : @agent.AgentContext,
  _params : LoadSessionParams,
) -> LoadSessionResult {
  @async.pause()
  { modes: Omitted, config_options: Omitted, meta: Omitted, }
}

///|
async fn agent_service_test_fork(
  _context : @agent.AgentContext,
  _params : ForkSessionParams,
) -> ForkSessionResult {
  @async.pause()
  {
    session_id: "forked",
    modes: Omitted,
    config_options: Omitted,
    meta: Omitted,
  }
}

///|
async fn agent_service_test_list(
  _context : @agent.AgentContext,
  _params : ListSessionsParams,
) -> ListSessionsResult {
  @async.pause()
  { sessions: [], next_cursor: Omitted, meta: Omitted, }
}

///|
async fn agent_service_test_authenticate(
  _context : @agent.AgentContext,
  _params : AuthenticateParams,
) -> AuthenticateResult {
  @async.pause()
  { meta: Omitted, }
}

///|
async fn agent_service_test_logout(
  _context : @agent.AgentContext,
  _params : LogoutParams,
) -> LogoutResult {
  @async.pause()
  { meta: Omitted, }
}

///|
async fn agent_service_test_request_broker(
  request : ClientRequest,
) -> Result[@agent.AgentOutboundReply, @agent.AgentContextError] {
  @async.pause()
  match request {
    SessionRequestPermission(_) =>
      Ok(AgentReplyRequestPermission({ outcome: Cancelled, meta: Omitted, }))
    other => Err(AgentContextUnavailable(method_name=other.method_name()))
  }
}

///|
async fn agent_service_test_notification_broker(
  _notification : ClientNotification,
) -> Result[Unit, @agent.AgentContextError] {
  @async.pause()
  Ok(())
}

///|
fn agent_service_test_context() -> @agent.AgentContext {
  @agent.agent_context(
    request_broker=agent_service_test_request_broker,
    notification_broker=agent_service_test_notification_broker,
  )
}

///|
fn agent_service_test_sessions(
  with_optional : Bool,
) -> @agent.AgentSessionService {
  if with_optional {
    @agent.agent_session_service(
      new_session=agent_service_test_new,
      prompt=agent_service_test_prompt,
      cancel=agent_service_test_cancel,
      load=agent_service_test_load,
      list=agent_service_test_list,
    )
  } else {
    @agent.agent_session_service(
      new_session=agent_service_test_new,
      prompt=agent_service_test_prompt,
      cancel=agent_service_test_cancel,
    )
  }
}

///|
fn agent_service_test_spec(
  name : String,
  image : Bool,
  with_optional : Bool,
) -> Result[@agent.AgentSpec, AgentCompositionError] {
  @agent.agent_spec(
    info=agent_service_test_info(name),
    sessions=agent_service_test_sessions(with_optional),
    support=@agent.agent_support(prompt_image=image),
  )
}

///|
test "agent service constructor keeps required callbacks typed" {
  let service = agent_service_test_sessions(false)
  let spec = @agent.agent_spec(
    info=agent_service_test_info("required"),
    sessions=service,
    support=@agent.agent_support(),
  )
  assert_true(spec is Ok(_))
}

///|
test "agent service constructor accepts an optional typed fork handler" {
  let with_fork = @agent.agent_session_service(
    new_session=agent_service_test_new,
    prompt=agent_service_test_prompt,
    cancel=agent_service_test_cancel,
    fork_session=agent_service_test_fork,
  )
  let with_fork_capabilities = @agent.agent_endpoint_from_spec(
    @agent.agent_spec(
      info=agent_service_test_info("with-fork"),
      sessions=with_fork,
      support=@agent.agent_support(),
    ).unwrap(),
  ).capabilities()
  match with_fork_capabilities.session_capabilities {
    Value(session) => assert_true(session.fork is Value(_))
    _ => fail("a present fork handler should be advertised")
  }
  let without_fork = agent_service_test_sessions(true)
  let without_fork_capabilities = @agent.agent_endpoint_from_spec(
    @agent.agent_spec(
      info=agent_service_test_info("without-fork"),
      sessions=without_fork,
      support=@agent.agent_support(),
    ).unwrap(),
  ).capabilities()
  match without_fork_capabilities.session_capabilities {
    Value(session) => assert_eq(session.fork, Omitted)
    _ => fail("other optional services should still be advertised")
  }
}

///|
test "auth construction fails for missing or duplicate methods" {
  try
    @agent.agent_auth_service(
      methods=[],
      authenticate=agent_service_test_authenticate,
    )
  catch {
    InvalidAuthMethods(reason=_) => ()
    _ => fail("expected empty auth methods to fail")
  } noraise {
    _ => fail("expected empty auth methods to fail")
  }
  let auth_method : AuthMethod = {
    id: "token",
    name: "Token",
    description: Omitted,
    meta: Omitted,
  }
  try
    @agent.agent_auth_service(
      methods=[auth_method, auth_method],
      authenticate=agent_service_test_authenticate,
    )
  catch {
    InvalidAuthMethods(reason=_) => ()
    _ => fail("expected duplicate auth methods to fail")
  } noraise {
    _ => fail("expected duplicate auth methods to fail")
  }
}

///|
test "agent spec rejects incomplete implementation before endpoint exists" {
  let result = agent_service_test_spec("", false, false)
  match result {
    Err(InvalidImplementation(reason=_)) => ()
    _ => fail("expected invalid implementation")
  }
}

///|
test "two caller environments produce isolated endpoint programs" {
  let first_spec = agent_service_test_spec("first", true, false).unwrap()
  let second_spec = agent_service_test_spec("second", false, false).unwrap()
  let first_endpoint = @agent.agent_endpoint_from_spec(first_spec)
  let second_endpoint = @agent.agent_endpoint_from_spec(second_spec)
  assert_eq(first_endpoint.info().name, "first")
  assert_eq(second_endpoint.info().name, "second")
  match first_endpoint.capabilities().prompt_capabilities {
    Value(prompt) => assert_eq(prompt.image, Value(true))
    _ => fail("first environment should derive image support")
  }
  match second_endpoint.capabilities().prompt_capabilities {
    Omitted => ()
    _ => fail("second environment must not inherit first support")
  }
}

///|
test "capabilities derive from optional services and support values" {
  let auth_method : AuthMethod = {
    id: "token",
    name: "Token",
    description: Omitted,
    meta: Omitted,
  }
  let auth = @agent.agent_auth_service(
    methods=[auth_method],
    authenticate=agent_service_test_authenticate,
    logout=agent_service_test_logout,
  )
  let spec = @agent.agent_spec(
    info=agent_service_test_info("capabilities"),
    sessions=agent_service_test_sessions(true),
    support=@agent.agent_support(prompt_image=true, mcp_http=true),
    auth~,
  )
  let endpoint = @agent.agent_endpoint_from_spec(spec.unwrap())
  let capabilities = endpoint.capabilities()
  assert_eq(capabilities.load_session, Value(true))
  match capabilities.session_capabilities {
    Value(session) => {
      assert_eq(session.list, Value({ meta: Omitted, }))
      assert_eq(session.delete, Omitted)
    }
    _ => fail("optional list service should be advertised")
  }
  match capabilities.auth {
    Value(auth_capability) =>
      assert_eq(auth_capability.logout, Value({ meta: Omitted, }))
    _ => fail("auth service should be advertised")
  }
  match capabilities.mcp_capabilities {
    Value(mcp) => assert_eq(mcp.http, Value(true))
    _ => fail("MCP support value should be advertised")
  }
}
