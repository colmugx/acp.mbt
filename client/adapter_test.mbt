///|
fn client_adapter_test_state(endpoint : ClientEndpoint) -> ClientAdapterState {
  client_adapter_state_new(
    protocol=client_protocol_state_ready(
      capabilities=Value(endpoint.capabilities()),
    ),
  )
}

///|
fn client_adapter_test_json(source : String) -> Json {
  protocol_parse_json(source) catch {
    _ => abort("adapter test fixture must be valid JSON")
  }
}

///|
fn client_adapter_test_request(
  id : RequestId,
  method_name : String,
  params : String,
) -> JsonRpcMessage {
  let request = JsonRpcRequest::new(
    id~,
    method_name~,
    params=client_adapter_test_json(params),
  ) catch {
    _ => abort("adapter test request must have structured params")
  }
  JsonRpcMessage::request(request)
}

///|
fn client_adapter_test_notification(
  method_name : String,
  params : String,
) -> JsonRpcMessage {
  let notification = JsonRpcNotification::new(
    method_name~,
    params=client_adapter_test_json(params),
  ) catch {
    _ => abort("adapter test notification must have structured params")
  }
  JsonRpcMessage::notification(notification)
}

///|
fn client_adapter_test_response(
  step : ClientAdapterStep,
) -> JsonRpcResponse raise {
  assert_eq(step.outputs.length(), 1)
  match step.outputs[0] {
    Response(response) => response
    _ => fail("expected one JSON-RPC response")
  }
}

///|
fn client_adapter_test_success(
  step : ClientAdapterStep,
  id : RequestId,
) -> Json raise {
  match client_adapter_test_response(step) {
    Success(success) => {
      assert_eq(success.id, id)
      success.result
    }
    Error(_) => fail("expected a successful JSON-RPC response")
  }
}

///|
fn client_adapter_test_error_code(
  step : ClientAdapterStep,
) -> JsonRpcErrorCode raise {
  match client_adapter_test_response(step) {
    Error(failure) => failure.error.code
    Success(_) => fail("expected a JSON-RPC error response")
  }
}

///|
fn client_adapter_test_immediate(
  admission : ClientAdapterAdmission,
) -> ClientAdapterStep raise {
  match admission {
    Immediate(step) => step
    Invoke(..) => fail("expected an immediate adapter step")
  }
}

///|
async fn client_adapter_test_round_trip(
  state : ClientAdapterState,
  endpoint : ClientEndpoint,
  message : JsonRpcMessage,
) -> ClientAdapterStep raise ClientAdapterError {
  match client_adapter_admit(state, endpoint, message) {
    Immediate(step) => step
    Invoke(state=reserved, invocation~) => {
      let completion = client_adapter_execute(invocation, endpoint)
      client_adapter_complete(reserved, invocation, completion)
    }
  }
}

///|
fn client_adapter_test_full_endpoint() -> ClientEndpoint {
  client_endpoint_test_endpoint("adapter", true)
}

///|
async fn client_adapter_test_failing_update(
  _params : SessionUpdateParams,
) -> Unit {
  @async.pause()
  raise ProtocolDecodeError::InvalidField(
    path="client-adapter-test",
    reason="observer failure",
  )
}

///|
async fn client_adapter_test_application_cancelled(
  _params : ReadTextFileParams,
) -> ReadTextFileResult {
  @async.pause()
  raise HandlerError::Cancelled
}

///|
async fn client_adapter_test_secret_failure(
  _params : ReadTextFileParams,
) -> ReadTextFileResult {
  @async.pause()
  raise ProtocolDecodeError::InvalidField(
    path="secret",
    reason="secret payload must not escape",
  )
}

///|
async fn client_adapter_test_thrown_cancel(
  _params : ReadTextFileParams,
) -> ReadTextFileResult {
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      @async.pause()
      ()
    })
    @async.pause()
    task.cancel()
    task.wait()
  })
  { content: "unreachable", meta: Omitted }
}

///|
async test "Client adapter admits, executes, and completes every request" {
  let endpoint = client_adapter_test_full_endpoint()
  let state = client_adapter_test_state(endpoint)
  let permission = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(1),
      "session/request_permission",
      "{\"sessionId\":\"session\",\"toolCall\":{\"toolCallId\":\"tool\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
    ),
  )
  match client_adapter_test_success(permission, Number(1)) {
    Object(fields) => assert_true(fields.contains("outcome"))
    _ => fail("permission result must be an object")
  }

  let read = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      String("read"),
      "fs/read_text_file",
      "{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}",
    ),
  )
  ignore(client_adapter_test_success(read, String("read")))

  let write = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(3),
      "fs/write_text_file",
      "{\"sessionId\":\"session\",\"path\":\"/tmp/output\",\"content\":\"body\"}",
    ),
  )
  ignore(client_adapter_test_success(write, Number(3)))

  let create = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(4),
      "terminal/create",
      "{\"sessionId\":\"session\",\"command\":\"echo\"}",
    ),
  )
  ignore(client_adapter_test_success(create, Number(4)))

  let output = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(5),
      "terminal/output",
      "{\"sessionId\":\"session\",\"terminalId\":\"terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(output, Number(5)))

  let wait_for_exit = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(6),
      "terminal/wait_for_exit",
      "{\"sessionId\":\"session\",\"terminalId\":\"terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(wait_for_exit, Number(6)))

  let kill = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(7),
      "terminal/kill",
      "{\"sessionId\":\"session\",\"terminalId\":\"terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(kill, Number(7)))

  let release = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(8),
      "terminal/release",
      "{\"sessionId\":\"session\",\"terminalId\":\"terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(release, Number(8)))

  let form = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(9),
      "elicitation/create",
      "{\"mode\":\"form\",\"message\":\"Choose\",\"requestId\":\"request\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}}}",
    ),
  )
  ignore(client_adapter_test_success(form, Number(9)))

  let url = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(10),
      "elicitation/create",
      "{\"mode\":\"url\",\"message\":\"Continue\",\"requestId\":\"request\",\"elicitationId\":\"elicitation\",\"url\":\"https://example.test\"}",
    ),
  )
  ignore(client_adapter_test_success(url, Number(10)))
}

///|
async test "Client notifications stay side-effect free in the adapter" {
  let endpoint = client_adapter_test_full_endpoint()
  let state = client_adapter_test_state(endpoint)
  let update = match
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification(
        "session/update", "{\"sessionId\":\"session\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
      ),
    ) {
    Invoke(state=reserved, invocation~) => {
      let completion = client_adapter_execute(invocation, endpoint)
      client_adapter_complete(reserved, invocation, completion)
    }
    Immediate(_) => fail("session/update must be invoked")
  }
  assert_eq(update.outputs.length(), 0)

  let complete = match
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification(
        "elicitation/complete", "{\"elicitationId\":\"elicitation\"}",
      ),
    ) {
    Invoke(state=reserved, invocation~) => {
      let completion = client_adapter_execute(invocation, endpoint)
      client_adapter_complete(reserved, invocation, completion)
    }
    Immediate(_) => fail("elicitation/complete must be invoked")
  }
  assert_eq(complete.outputs.length(), 0)

  let cancel = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification(
        "$/cancel_request", "{\"requestId\":\"cancel-string\"}",
      ),
    ),
  )
  assert_eq(cancel.outputs.length(), 1)
  match cancel.outputs[0] {
    Command(CancelRequest(request_id=String("cancel-string"))) => ()
    _ => fail("string cancellation must emit a cancel command")
  }

  let cancel_number = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification("$/cancel_request", "{\"requestId\":7}"),
    ),
  )
  assert_eq(cancel_number.outputs.length(), 1)
  match cancel_number.outputs[0] {
    Command(CancelRequest(request_id=Number(7))) => ()
    _ => fail("numeric cancellation must emit a cancel command")
  }

  let malformed_cancel = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification("$/cancel_request", "{}"),
    ),
  )
  assert_eq(malformed_cancel.outputs.length(), 1)
  match malformed_cancel.outputs[0] {
    Command(TraceError(method_name="$/cancel_request", error~)) =>
      assert_eq(error.code, InvalidParams)
    _ => fail("malformed cancellation must remain a trace error")
  }
}

///|
test "Client adapter rejects elicitation completion without URL capability" {
  let form_only_elicitation = try! client_elicitation_service(
    form=client_service_test_form,
    complete=client_service_test_complete,
  )
  let form_only_spec = client_spec(
    info=client_service_test_info("form-only-adapter"),
    session=client_service_test_session(),
    elicitation=form_only_elicitation,
  )
  let endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(form_only_spec)),
    (),
  ).unwrap()
  match
    client_adapter_admit(
      client_adapter_test_state(endpoint),
      endpoint,
      client_adapter_test_notification(
        "elicitation/complete", "{\"elicitationId\":\"elicitation\"}",
      ),
    ) {
    Immediate(step) => {
      assert_eq(step.outputs.length(), 1)
      match step.outputs[0] {
        Command(TraceError(method_name="elicitation/complete", error~)) =>
          assert_eq(error.code, ResourceNotFound)
        _ => fail("denied completion must emit a capability trace")
      }
    }
    Invoke(..) => fail("denied completion must not invoke the handler")
  }
}

///|
async test "Client adapter invokes URL completion when capability is advertised" {
  let endpoint = client_adapter_test_full_endpoint()
  let admission = client_adapter_admit(
    client_adapter_test_state(endpoint),
    endpoint,
    client_adapter_test_notification(
      "elicitation/complete", "{\"elicitationId\":\"elicitation\"}",
    ),
  )
  match admission {
    Invoke(state=reserved, invocation~) => {
      let completion = client_adapter_execute(invocation, endpoint)
      let done = client_adapter_complete(reserved, invocation, completion)
      assert_eq(done.outputs.length(), 0)
    }
    Immediate(_) => fail("URL-enabled completion must invoke the handler")
  }
}

///|
test "Client adapter maps gates, malformed methods, and readiness" {
  let endpoint = client_adapter_test_full_endpoint()
  let state = client_adapter_test_state(endpoint)
  let unknown = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(Number(1), "vendor/unknown", "{}"),
    ),
  )
  assert_eq(client_adapter_test_error_code(unknown), MethodNotFound)

  let wrong_direction = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(2),
        "session/new",
        "{\"cwd\":\"/\",\"mcpServers\":[]}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(wrong_direction), MethodNotFound)

  let malformed = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(Number(3), "fs/read_text_file", "{}"),
    ),
  )
  assert_eq(client_adapter_test_error_code(malformed), InvalidParams)

  let unready = client_adapter_test_immediate(
    client_adapter_admit(
      client_adapter_state_new(
        protocol=client_protocol_state_new(
          capabilities=Value(endpoint.capabilities()),
        ),
      ),
      endpoint,
      client_adapter_test_request(
        Number(4),
        "session/request_permission",
        "{\"sessionId\":\"session\",\"toolCall\":{\"toolCallId\":\"tool\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(unready), InvalidRequest)

  let read_only_spec = client_spec(
    info=client_service_test_info("read-only-adapter"),
    session=client_service_test_session(),
    file_system=client_service_test_read_only_files(),
  )
  let read_only = @reader.Reader::run(
    client_program(@reader.Reader::pure(read_only_spec)),
    (),
  ).unwrap()
  let denied_write = client_adapter_test_immediate(
    client_adapter_admit(
      client_adapter_test_state(read_only),
      read_only,
      client_adapter_test_request(
        Number(5),
        "fs/write_text_file",
        "{\"sessionId\":\"session\",\"path\":\"/tmp/output\",\"content\":\"body\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(denied_write), ResourceNotFound)

  let minimal = client_endpoint_test_endpoint("minimal-adapter", false)
  let denied_terminal = client_adapter_test_immediate(
    client_adapter_admit(
      client_adapter_test_state(minimal),
      minimal,
      client_adapter_test_request(
        Number(6),
        "terminal/create",
        "{\"sessionId\":\"session\",\"command\":\"echo\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(denied_terminal), ResourceNotFound)
}

///|
async test "Client adapter admits independent requests for owner scheduling" {
  let endpoint = client_adapter_test_full_endpoint()
  let initial = client_adapter_test_state(endpoint)
  let first_message = client_adapter_test_request(
    String("first"),
    "fs/read_text_file",
    "{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}",
  )
  let second_message = client_adapter_test_request(
    Number(2),
    "fs/write_text_file",
    "{\"sessionId\":\"session\",\"path\":\"/tmp/output\",\"content\":\"body\"}",
  )
  let first = match client_adapter_admit(initial, endpoint, first_message) {
    Invoke(state=reserved, invocation~) => (reserved, invocation)
    Immediate(_) => fail("first request must be invoked")
  }
  let second = match client_adapter_admit(first.0, endpoint, second_message) {
    Invoke(state=reserved, invocation~) => (reserved, invocation)
    Immediate(_) => fail("second request must be invoked")
  }
  let second_completion = client_adapter_execute(second.1, endpoint)
  let after_second = client_adapter_complete(
    second.0,
    second.1,
    second_completion,
  )
  ignore(client_adapter_test_success(after_second, Number(2)))

  let first_completion = client_adapter_execute(first.1, endpoint)
  let after_first = client_adapter_complete(
    after_second.state,
    first.1,
    first_completion,
  )
  ignore(client_adapter_test_success(after_first, String("first")))
}

///|
async test "Client adapter completion matching is fail-fast" {
  let endpoint = client_adapter_test_full_endpoint()
  let state = client_adapter_test_state(endpoint)
  let admission = client_adapter_admit(
    state,
    endpoint,
    client_adapter_test_request(
      Number(20),
      "fs/read_text_file",
      "{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}",
    ),
  )
  let (reserved, invocation) = match admission {
    Invoke(state=reserved, invocation~) => (reserved, invocation)
    Immediate(_) => fail("request must be invoked")
  }
  let completion = client_adapter_execute(invocation, endpoint)
  ignore(client_adapter_complete(reserved, invocation, completion))

  let wrong : ClientAdapterCompletion = FsWriteTextFileCompleted(
    id=Number(20),
    result=Ok({ meta: Omitted }),
  )
  try client_adapter_complete(reserved, invocation, wrong) catch {
    CompletionMismatch(method_name="fs/read_text_file") => ()
    _ => fail("wrong completion must mismatch")
  } noraise {
    _ => fail("wrong completion must raise")
  }

  let wrong_id : ClientAdapterCompletion = FsReadTextFileCompleted(
    id=Number(21),
    result=Ok({ content: "wrong", meta: Omitted }),
  )
  try client_adapter_complete(reserved, invocation, wrong_id) catch {
    CompletionMismatch(method_name="fs/read_text_file") => ()
    _ => fail("wrong id must mismatch")
  } noraise {
    _ => fail("wrong id must raise")
  }
}

///|
async test "Client adapter notification completion is variant checked" {
  let endpoint = client_adapter_test_full_endpoint()
  let state = client_adapter_test_state(endpoint)
  let admission = client_adapter_admit(
    state,
    endpoint,
    client_adapter_test_notification(
      "session/update", "{\"sessionId\":\"session\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
    ),
  )
  let (reserved, invocation) = match admission {
    Invoke(state=reserved, invocation~) => (reserved, invocation)
    Immediate(_) => fail("notification must be invoked")
  }
  let wrong : ClientAdapterCompletion = ElicitationCompleteCompleted(
    result=Ok(()),
  )
  try client_adapter_complete(reserved, invocation, wrong) catch {
    CompletionMismatch(method_name="session/update") => ()
    _ => fail("wrong notification variant must mismatch")
  } noraise {
    _ => fail("wrong notification variant must raise")
  }

  let completion = client_adapter_execute(invocation, endpoint)
  let done = client_adapter_complete(reserved, invocation, completion)
  assert_eq(done.outputs.length(), 0)

  let failing_service = client_spec(
    info=client_service_test_info("notification-failure"),
    session=client_session_service(
      session_update=client_adapter_test_failing_update,
      request_permission=client_service_test_permission,
    ),
  )
  let failing_endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(failing_service)),
    (),
  ).unwrap()
  let failing_admission = client_adapter_admit(
    client_adapter_test_state(failing_endpoint),
    failing_endpoint,
    client_adapter_test_notification(
      "session/update", "{\"sessionId\":\"session\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
    ),
  )
  match failing_admission {
    Invoke(state=reserved, invocation~) => {
      let completion = client_adapter_execute(invocation, failing_endpoint)
      let trace = client_adapter_complete(reserved, invocation, completion)
      match trace.outputs[0] {
        Command(TraceError(method_name="session/update", error~)) =>
          assert_eq(error.code, InternalError)
        _ => fail("notification failure must be a trace intent")
      }
    }
    Immediate(_) => fail("failing notification must still be invoked")
  }
}

///|
async test "Client adapter maps cancellation and redacts handler failures" {
  let cancelled_files = try! client_file_system_service(
    read=client_adapter_test_application_cancelled,
  )
  let cancelled_spec = client_spec(
    info=client_service_test_info("application-cancelled"),
    session=client_service_test_session(),
    file_system=cancelled_files,
  )
  let cancelled_endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(cancelled_spec)),
    (),
  ).unwrap()
  let cancelled = client_adapter_test_round_trip(
    client_adapter_test_state(cancelled_endpoint),
    cancelled_endpoint,
    client_adapter_test_request(
      Number(30),
      "fs/read_text_file",
      "{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(cancelled), RequestCancelled)

  let secret_files = try! client_file_system_service(
    read=client_adapter_test_secret_failure,
  )
  let secret_spec = client_spec(
    info=client_service_test_info("secret-failure"),
    session=client_service_test_session(),
    file_system=secret_files,
  )
  let secret_endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(secret_spec)),
    (),
  ).unwrap()
  let secret = client_adapter_test_round_trip(
    client_adapter_test_state(secret_endpoint),
    secret_endpoint,
    client_adapter_test_request(
      Number(31),
      "fs/read_text_file",
      "{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(secret), InternalError)
  match client_adapter_test_response(secret) {
    Error(failure) => assert_true(!failure.error.message.contains("secret"))
    Success(_) => fail("secret failure must be an error")
  }

  let thrown_files = try! client_file_system_service(
    read=client_adapter_test_thrown_cancel,
  )
  let thrown_spec = client_spec(
    info=client_service_test_info("task-cancel"),
    session=client_service_test_session(),
    file_system=thrown_files,
  )
  let thrown_endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(thrown_spec)),
    (),
  ).unwrap()
  let thrown = client_adapter_test_round_trip(
    client_adapter_test_state(thrown_endpoint),
    thrown_endpoint,
    client_adapter_test_request(
      Number(32),
      "fs/read_text_file",
      "{\"sessionId\":\"session\",\"path\":\"/tmp/input\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(thrown), RequestCancelled)
}

///|
test "Client adapter rejects endpoint mismatch and inbound responses" {
  let endpoint = client_adapter_test_full_endpoint()
  let mismatched = client_adapter_state_new(
    protocol=client_protocol_state_ready(capabilities=Omitted),
  )
  try
    client_adapter_admit(
      mismatched,
      endpoint,
      client_adapter_test_request(Number(1), "vendor/unknown", "{}"),
    )
  catch {
    EndpointMismatch(reason=_) => ()
    _ => fail("expected endpoint/state mismatch")
  } noraise {
    _ => fail("expected endpoint/state mismatch")
  }

  let state = client_adapter_test_state(endpoint)
  let response = JsonRpcMessage::response(
    JsonRpcResponse::success(id=Number(1), result=Json::string("ok")),
  )
  try client_adapter_admit(state, endpoint, response) catch {
    UnexpectedMessage(kind="response") => ()
    _ => fail("expected inbound response rejection")
  } noraise {
    _ => fail("expected inbound response rejection")
  }
}

///|
using @acp_error {type HandlerError}

///|
using @agent_message {type AgentNotification, type AgentRequest}

///|
using @client_protocol {client_protocol_state_new, client_protocol_state_ready}

///|
using @jsonrpc {
  type JsonRpcErrorCode,
  type JsonRpcMessage,
  type JsonRpcNotification,
  type JsonRpcRequest,
  type JsonRpcResponse,
  type RequestId,
}

///|
using @protocol_data {
  type AuthenticateParams,
  type ElicitationCompleteParams,
  type ElicitationCreateResult,
  type ElicitationFormParams,
  type ElicitationUrlParams,
  type Implementation,
  type InitializeParams,
  type LogoutParams,
  type ProtocolDecodeError,
  type ReadTextFileParams,
  type ReadTextFileResult,
  type RequestPermissionRequest,
  type RequestPermissionResponse,
  type TerminalCreateParams,
  type TerminalCreateResult,
  type TerminalKillParams,
  type TerminalKillResult,
  type TerminalOutputParams,
  type TerminalOutputResult,
  type TerminalReleaseParams,
  type TerminalReleaseResult,
  type TerminalWaitForExitParams,
  type TerminalWaitForExitResult,
  type WriteTextFileParams,
  type WriteTextFileResult,
  protocol_parse_json,
}

///|
using @session_protocol {
  type CloseSessionParams,
  type DeleteSessionParams,
  type ListSessionsParams,
  type LoadSessionParams,
  type NewSessionParams,
  type PromptParams,
  type ResumeSessionParams,
  type SessionUpdateParams,
  type SetSessionConfigOptionParams,
  type SetSessionModeParams,
}

///|
