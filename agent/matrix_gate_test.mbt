///|
/// SDK-scope acceptance tests for the handshake, gate, and boundary rows of
/// docs/implementation-plan/04-v1-completeness-matrix.md that live in the
/// Agent adapter: A07/B02 (v1-only version negotiation without partial
/// state), B01 (business traffic before initialize), B09 (the logout gate),
/// B08/F05 (prompt content capability gates before invocation), G03 (a denied
/// remote MCP transport never falls back to stdio), G04 (authentication
/// required cannot be bypassed), G05 (a cancelled permission settles the turn
/// after the required updates), and G07 (gate decisions surface as typed
/// responses or method-named trace intents, never stdout).

///|
/// Assert that a rejected notification produced exactly one typed trace
/// intent carrying the method name, and no JSON-RPC response.  This is the
/// adapter half of row G07; the engine half (owner_trace reaching the trace
/// sink instead of the writer port) is proven in agent/runtime_test.mbt.
fn agent_matrix_gate_test_trace_error(
  admission : AgentAdapterAdmission,
  method_name~ : String,
  code~ : JsonRpcErrorCode,
) -> Unit raise {
  let step = match admission {
    Immediate(step) => step
    Invoke(..) => fail("a rejected notification must not invoke a handler")
  }
  assert_eq(step.outputs.length(), 1)
  match step.outputs[0] {
    Command(TraceError(method_name=traced, error~)) => {
      assert_eq(traced, method_name)
      assert_eq(error.code, code)
    }
    Response(_) => fail("notification rejection must not emit a response")
    Notification(_) => fail("notification rejection must not emit a frame")
    Command(_) => fail("expected a trace intent")
  }
}

///|
/// Rows A07/B02 (agent side): an initialize request carrying a non-v1
/// protocolVersion is answered with the Agent's own v1 version while the
/// adapter stays pre-initialized, so no partial handshake state exists and
/// business traffic keeps failing until a real v1 initialize arrives.  The
/// client-side half (rejecting a non-v1 initialize result, closing instead of
/// continuing) is proven in client/connection_test.mbt.
async test "matrix A07 B02 non-v1 initialize keeps the agent pre-initialized" {
  let endpoint = agent_adapter_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let mismatch = match
    agent_adapter_admit(
      initial,
      endpoint,
      agent_adapter_test_request(
        Number(1),
        "initialize",
        "{\"protocolVersion\":2,\"clientCapabilities\":{}}",
      ),
    ) {
    Immediate(step) => step
    Invoke(..) => fail("initialize must complete synchronously")
  }
  // The reply carries the agent's own latest version (v1); the peer decides
  // to close.  There is no silent upgrade and no negotiated state.
  let decoded = initialize_result_from_json(
    agent_adapter_test_success(mismatch, Number(1)),
  )
  assert_eq(decoded.protocol_version, 1)
  assert_true(mismatch.state.protocol().phase is AwaitingInitialize)
  assert_true(mismatch.state.protocol().protocol_version is Omitted)
  // Business traffic on the un-negotiated connection is still rejected with
  // the state exactly unchanged: no partial initialize leaked into the phase.
  let premature = agent_adapter_admit(
    mismatch.state,
    endpoint,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  match premature {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
      assert_eq(step.state, mismatch.state)
    }
    Invoke(..) => fail("a non-v1 handshake must not admit business traffic")
  }
  // A subsequent v1 initialize negotiates normally on the same connection.
  let accepted = match
    agent_adapter_admit(
      mismatch.state,
      endpoint,
      agent_adapter_test_request(
        Number(3),
        "initialize",
        "{\"protocolVersion\":1}",
      ),
    ) {
    Immediate(step) => step
    Invoke(..) => fail("initialize must complete synchronously")
  }
  assert_true(accepted.state.protocol().phase is Initialized)
  assert_eq(
    initialize_result_from_json(agent_adapter_test_success(accepted, Number(3))).protocol_version,
    1,
  )
  ignore(agent_service_test_context())
}

///|
/// Row B01: every business request and notification before initialize is
/// rejected typed — requests get one typed error response, notifications get
/// one method-named trace intent — and the pre-initialize state never moves.
async test "matrix B01 business traffic before initialize is rejected typed" {
  let endpoint = agent_adapter_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let premature_request = agent_adapter_admit(
    initial,
    endpoint,
    agent_adapter_test_request(
      Number(1),
      "session/prompt",
      "{\"sessionId\":\"s\",\"prompt\":[]}",
    ),
  )
  match premature_request {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
      assert_eq(step.state, initial)
    }
    Invoke(..) => fail("a session method before initialize must not invoke")
  }
  agent_matrix_gate_test_trace_error(
    agent_adapter_admit(
      initial,
      endpoint,
      agent_adapter_test_notification("session/cancel", "{\"sessionId\":\"s\"}"),
    ),
    method_name="session/cancel",
    code=InvalidRequest,
  )
  ignore(agent_service_test_context())
}

///|
/// Row B09 remainder: `logout` is gated by the advertised `auth.logout`
/// capability.  An endpoint without the auth service advertises nothing, so
/// logout is denied before any handler exists, before and after initialize.
async test "matrix B09 logout is gated by the advertised auth capability" {
  let endpoint = agent_adapter_test_endpoint()
  let initial = agent_adapter_test_state(endpoint)
  let before_initialize = agent_adapter_admit(
    initial,
    endpoint,
    agent_adapter_test_request(Number(1), "logout", "{}"),
  )
  match before_initialize {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), InvalidRequest)
    Invoke(..) => fail("logout before initialize must not invoke")
  }
  let initialized = agent_adapter_test_initialized(endpoint, Number(2))
  let ungated = agent_adapter_admit(
    initialized.state,
    endpoint,
    agent_adapter_test_request(Number(3), "logout", "{}"),
  )
  match ungated {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, initialized.state)
      assert_true(step.state.reservation() is Idle)
    }
    Invoke(..) => fail("logout without auth.logout must not invoke a handler")
  }
}

///|
/// Rows B08/F03/F04/F05: prompt content gates are enforced during admission,
/// before any handler exists.  Text and resource_link blocks are baseline
/// traffic that every prompt Agent accepts (rows F01/F02); image, audio, and
/// embedded resources additionally require the negotiated prompt capability.
async test "matrix B08 F05 prompt content gates run before invocation" {
  let plain = agent_adapter_test_endpoint()
  let plain_initialized = agent_adapter_test_initialized(plain, Number(1))
  let gated_fixtures : Array[(Int64, String)] = [
    (
      2L, "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"image\",\"data\":\"aA==\",\"mimeType\":\"image/png\"}]}",
    ),
    (
      3L, "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"audio\",\"data\":\"aA==\",\"mimeType\":\"audio/wav\"}]}",
    ),
    (
      4L, "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"resource\",\"resource\":{\"uri\":\"file:///tmp/a\",\"text\":\"body\"}}]}",
    ),
  ]
  for fixture in gated_fixtures {
    let (id, source) = fixture
    let denied = agent_adapter_admit(
      plain_initialized.state,
      plain,
      agent_adapter_test_request(Number(id), "session/prompt", source),
    )
    match denied {
      Immediate(step) => {
        assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
        assert_eq(step.state, plain_initialized.state)
      }
      Invoke(..) => fail("an ungated prompt block must not invoke a handler")
    }
  }
  // Baseline blocks need no capability: text and resource_link dispatch.
  for
    case in [
      (
        5L, "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"text\",\"text\":\"run\"}]}",
      ),
      (
        6L, "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"resource_link\",\"uri\":\"file:///tmp/a\",\"name\":\"a\"}]}",
      ),
    ] {
    let (id, source) = case
    match
      agent_adapter_admit(
        plain_initialized.state,
        plain,
        agent_adapter_test_request(Number(id), "session/prompt", source),
      ) {
      Invoke(state=_, invocation=SessionPromptInvocation(_)) => ()
      Immediate(_) => fail("baseline prompt blocks must invoke")
      Invoke(..) => fail("prompt admitted the wrong invocation")
    }
  }
  // With every prompt capability advertised the same payloads reach the
  // handler as typed blocks.
  let seen : Array[PromptParams] = []
  let supported = agent_endpoint_from_spec(
    agent_spec(
      info=agent_service_test_info("matrix-prompt-gates"),
      sessions=agent_session_service(
        new_session=agent_service_test_new,
        prompt=async fn(
          _context : AgentContext,
          params : PromptParams,
        ) -> PromptResult {
          @async.pause()
          seen.push(params)
          { stop_reason: EndTurn, meta: Omitted }
        },
        cancel=agent_service_test_cancel,
      ),
      support=agent_support(
        prompt_image=true,
        prompt_audio=true,
        prompt_embedded_context=true,
      ),
    ).unwrap(),
  )
  let supported_initialized = agent_adapter_test_initialized(
    supported,
    Number(7),
  )
  let mixed = agent_adapter_test_invoke(
    supported_initialized.state,
    supported,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(8),
      "session/prompt",
      "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"text\",\"text\":\"run\"},{\"type\":\"image\",\"data\":\"aA==\",\"mimeType\":\"image/png\"},{\"type\":\"audio\",\"data\":\"aA==\",\"mimeType\":\"audio/wav\"},{\"type\":\"resource_link\",\"uri\":\"file:///tmp/a\",\"name\":\"a\"},{\"type\":\"resource\",\"resource\":{\"uri\":\"file:///tmp/a\",\"text\":\"body\"}}]}",
    ),
  )
  let decoded = prompt_result_from_json(
    agent_adapter_test_success(mixed, Number(8)),
  )
  assert_eq(decoded.stop_reason, EndTurn)
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].prompt.length(), 5)
  assert_true(seen[0].prompt[0] is Text(_))
  assert_true(seen[0].prompt[1] is Image(_))
  assert_true(seen[0].prompt[2] is Audio(_))
  assert_true(seen[0].prompt[3] is ResourceLink(_))
  assert_true(seen[0].prompt[4] is Resource(_))
}

///|
/// Row G03: when a session request mixes transports, the denial comes from
/// the remote entry that lacks its capability, and the same request without
/// that entry dispatches.  A denied HTTP/SSE server can never be silently
/// reinterpreted as stdio: the wire discriminator is decoded first and the
/// gate denies the whole request before any handler runs (the codec half —
/// an HTTP entry never decoding as stdio — is proven in
/// protocol/matrix_test.mbt).
async test "matrix G03 a denied remote MCP server never falls back to stdio" {
  let unsupported = agent_adapter_test_b09_endpoint(agent_support())
  let unsupported_initialized = agent_adapter_test_initialized(
    unsupported,
    Number(1),
  )
  let mixed = agent_adapter_admit(
    unsupported_initialized.state,
    unsupported,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"local\",\"command\":\"/bin/tool\",\"args\":[],\"env\":[]},{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]}",
    ),
  )
  match mixed {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
      assert_eq(step.state, unsupported_initialized.state)
    }
    Invoke(..) => fail("a denied remote MCP entry must not invoke a handler")
  }
  match
    agent_adapter_admit(
      unsupported_initialized.state,
      unsupported,
      agent_adapter_test_request(
        Number(3),
        "session/new",
        "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"local\",\"command\":\"/bin/tool\",\"args\":[],\"env\":[]}]}",
      ),
    ) {
    Invoke(state=_, invocation=SessionNewInvocation(_)) => ()
    Immediate(_) => fail("the stdio-only list must dispatch unchanged")
    Invoke(..) => fail("session/new admitted the wrong invocation")
  }
  let http_only = agent_adapter_test_b09_endpoint(agent_support(mcp_http=true))
  let http_initialized = agent_adapter_test_initialized(http_only, Number(4))
  match
    agent_adapter_admit(
      http_initialized.state,
      http_only,
      agent_adapter_test_request(
        Number(5),
        "session/new",
        "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"http\",\"name\":\"remote\",\"url\":\"https://example.test\",\"headers\":[]}]}",
      ),
    ) {
    Invoke(state=_, invocation=SessionNewInvocation(_)) => ()
    Immediate(_) => fail("an advertised HTTP transport must dispatch")
    Invoke(..) => fail("session/new admitted the wrong invocation")
  }
  let sse_denied = agent_adapter_admit(
    http_initialized.state,
    http_only,
    agent_adapter_test_request(
      Number(6),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[{\"type\":\"sse\",\"name\":\"events\",\"url\":\"https://example.test/events\",\"headers\":[]}]}",
    ),
  )
  match sse_denied {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), ResourceNotFound)
    Invoke(..) => fail("an unadvertised SSE transport must not invoke")
  }
}

///|
/// Row G04: an agent that advertises authentication answers every
/// session-creating method with -32000 AuthRequired until authentication
/// succeeds, and returns to that state after logout.  No request shape,
/// notification, failed authenticate attempt, or premature logout bypasses
/// the gate; none of them moves the protocol state.
async test "matrix G04 auth required cannot be bypassed for session creation" {
  let auth_endpoint = agent_adapter_test_auth_endpoint()
  let initialized = agent_adapter_test_initialized(auth_endpoint, Number(1))
  assert_true(
    initialized.state.protocol().authentication is AwaitingAuthentication,
  )
  let denied_new = agent_adapter_admit(
    initialized.state,
    auth_endpoint,
    agent_adapter_test_request(
      Number(2),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  match denied_new {
    Immediate(step) => {
      assert_eq(agent_adapter_test_error_code(step), AuthRequired)
      assert_eq(step.state, initialized.state)
      assert_true(step.state.reservation() is Idle)
    }
    Invoke(..) => fail("session creation before authentication must not invoke")
  }
  // A cancel notification cannot sneak past the gate either: it is traced
  // with its method name and produces no response (row G07).
  agent_matrix_gate_test_trace_error(
    agent_adapter_admit(
      initialized.state,
      auth_endpoint,
      agent_adapter_test_notification("session/cancel", "{\"sessionId\":\"s\"}"),
    ),
    method_name="session/cancel",
    code=AuthRequired,
  )
  // Logging out before authenticating is a typed auth failure, not a bypass.
  let premature_logout = agent_adapter_admit(
    initialized.state,
    auth_endpoint,
    agent_adapter_test_request(Number(3), "logout", "{}"),
  )
  match premature_logout {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), AuthRequired)
    Invoke(..) => fail("logout before authentication must not invoke")
  }
  // A failing authenticate handler keeps the gate engaged: the reservation
  // is released and the connection still requires authentication.
  let failing = agent_adapter_test_auth_endpoint_with(
    agent_adapter_test_failing_auth,
  )
  let failing_initialized = agent_adapter_test_initialized(failing, Number(4))
  let failed_auth = agent_adapter_test_invoke(
    failing_initialized.state,
    failing,
    agent_service_test_context(),
    agent_adapter_test_request(
      Number(5),
      "authenticate",
      "{\"methodId\":\"token\"}",
    ),
  )
  assert_eq(agent_adapter_test_error_code(failed_auth), InternalError)
  assert_true(failed_auth.state.reservation() is Idle)
  assert_true(
    failed_auth.state.protocol().authentication is AwaitingAuthentication,
  )
  let still_denied = agent_adapter_admit(
    failed_auth.state,
    failing,
    agent_adapter_test_request(
      Number(6),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  match still_denied {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), AuthRequired)
    Invoke(..) => fail("a failed authenticate must not open session creation")
  }
  // The full sequence: authenticate succeeds, session creation opens,
  // logout completes, and session creation requires authentication again.
  let auth_admission = match
    agent_adapter_admit(
      initialized.state,
      auth_endpoint,
      agent_adapter_test_request(
        Number(7),
        "authenticate",
        "{\"methodId\":\"token\"}",
      ),
    ) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => fail("an advertised authenticate must invoke")
  }
  let authenticated = agent_adapter_complete(
    auth_admission.0,
    auth_admission.1,
    AuthenticateCompleted(id=Number(7), result=Ok({ meta: Omitted })),
  )
  ignore(agent_adapter_test_success(authenticated, Number(7)))
  assert_true(authenticated.state.protocol().authentication is Authenticated)
  match
    agent_adapter_admit(
      authenticated.state,
      auth_endpoint,
      agent_adapter_test_request(
        Number(8),
        "session/new",
        "{\"cwd\":\"/\",\"mcpServers\":[]}",
      ),
    ) {
    Invoke(state=_, invocation=SessionNewInvocation(_)) => ()
    Immediate(_) => fail("session creation after authentication must invoke")
    Invoke(..) => fail("session/new admitted the wrong invocation")
  }
  let logout_admission = match
    agent_adapter_admit(
      authenticated.state,
      auth_endpoint,
      agent_adapter_test_request(Number(9), "logout", "{}"),
    ) {
    Invoke(state~, invocation~) => (state, invocation)
    Immediate(_) => fail("an advertised logout must invoke")
  }
  assert_true(logout_admission.0.reservation() is LogoutPending(_))
  let logged_out = agent_adapter_complete(
    logout_admission.0,
    logout_admission.1,
    LogoutCompleted(id=Number(9), result=Ok({ meta: Omitted })),
  )
  ignore(agent_adapter_test_success(logged_out, Number(9)))
  assert_true(
    logged_out.state.protocol().authentication is AwaitingAuthentication,
  )
  let denied_again = agent_adapter_admit(
    logged_out.state,
    auth_endpoint,
    agent_adapter_test_request(
      Number(10),
      "session/new",
      "{\"cwd\":\"/\",\"mcpServers\":[]}",
    ),
  )
  match denied_again {
    Immediate(step) =>
      assert_eq(agent_adapter_test_error_code(step), AuthRequired)
    Invoke(..) => fail("session creation after logout must not invoke")
  }
}

///|
/// Row G05: when the Client answers a pending permission request with the
/// cancelled outcome, the Agent bridge delivers it typed, the already-sent
/// tool update stays complete, and the turn settles as a success prompt
/// response with stopReason "cancelled" — never a dangling permission.
///
/// Boundary: wiring `session/cancel` to task cancellation is the connection
/// runtime's job.  On that path the engine cancels the reverse permission
/// task and the Client adapter converts the cancellation into the same
/// `{outcome:"cancelled"}` response (client/adapter_test.mbt), so the flow
/// proven here is exactly the one the runtime produces; an application that
/// leaves a permission unanswered without cancelling cannot occur through the
/// typed context, whose brokers always resolve or raise.
async test "matrix G05 cancelled permission settles the turn after final updates" {
  let updates : Array[SessionUpdateParams] = []
  let permissions : Array[RequestPermissionRequest] = []
  let notification_broker : AgentContextNotificationBroker = notification => {
    match notification {
      SessionUpdate(params) => updates.push(params)
      _ => abort("expected the completed tool update notification")
    }
    Ok(())
  }
  let request_broker : AgentContextRequestBroker = request => {
    match request {
      SessionRequestPermission(params) => {
        permissions.push(params)
        Ok(AgentReplyRequestPermission({ outcome: Cancelled, meta: Omitted }))
      }
      _ => abort("expected the typed permission request")
    }
  }
  let context = agent_context(request_broker~, notification_broker~)
  let endpoint = agent_endpoint_from_spec(
    agent_spec(
      info=agent_service_test_info("matrix-g05"),
      sessions=agent_session_service(
        new_session=agent_service_test_new,
        prompt=async fn(
          context : AgentContext,
          _params : PromptParams,
        ) -> PromptResult {
          @async.pause()
          // The required final tool update completes before the permission
          // is resolved, so the Client has already received it when the
          // cancellation outcome arrives.
          context.session_update({
            session_id: "s",
            update: ToolCallUpdate({
              tool_call_id: "call-1",
              kind: Omitted,
              status: Value(Completed),
              title: Omitted,
              content: Omitted,
              locations: Omitted,
              raw_input: Omitted,
              raw_output: Omitted,
              meta: Omitted,
            }),
            meta: Omitted,
          })
          let response = context.request_permission({
            session_id: "s",
            tool_call: {
              tool_call_id: "call-1",
              kind: Omitted,
              status: Value(InProgress),
              title: Omitted,
              content: Omitted,
              locations: Omitted,
              raw_input: Omitted,
              raw_output: Omitted,
              meta: Omitted,
            },
            options: [
              {
                option_id: "allow",
                name: "Allow",
                kind: AllowOnce,
                meta: Omitted,
              },
            ],
            meta: Omitted,
          })
          assert_true(response.outcome is Cancelled)
          { stop_reason: Cancelled, meta: Omitted }
        },
        cancel=agent_service_test_cancel,
      ),
      support=agent_support(),
    ).unwrap(),
  )
  let initialized = agent_adapter_test_initialized(endpoint, Number(1))
  let settled = agent_adapter_test_invoke(
    initialized.state,
    endpoint,
    context,
    agent_adapter_test_request(
      Number(2),
      "session/prompt",
      "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"text\",\"text\":\"run\"}]}",
    ),
  )
  let decoded = prompt_result_from_json(
    agent_adapter_test_success(settled, Number(2)),
  )
  assert_eq(decoded.stop_reason, Cancelled)
  assert_eq(updates.length(), 1)
  match updates[0].update {
    ToolCallUpdate(update) => assert_true(update.status is Value(Completed))
    _ => fail("expected the completed tool call update")
  }
  assert_eq(permissions.length(), 1)
  assert_eq(permissions[0].tool_call.tool_call_id, "call-1")
  assert_eq(permissions[0].options.length(), 1)
}
