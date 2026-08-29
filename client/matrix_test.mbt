///|
/// SDK-scope acceptance tests for the v1 stable Agent -> Client method matrix
/// (rows D02-D11 of docs/implementation-plan/04-v1-completeness-matrix.md).
///
/// The Client adapter owns readiness/capability gates, strict typed decode
/// before any handler runs, typed handler delivery, and typed result encoding
/// afterwards.  Service-owned boundaries (file contents, terminal process
/// lifecycle, terminal id registries, elicitation id registries) are asserted
/// where the SDK must stay typed and fail fast and are documented inline
/// where the SDK deliberately holds no state.

///|
fn client_matrix_test_endpoint(
  spec : Result[ClientSpec, ClientCompositionError],
) -> ClientEndpoint {
  @reader.Reader::run(client_program(@reader.Reader::pure(spec)), ()).unwrap()
}

///|
/// The wire name of one delivered session update variant.  Cross-checking it
/// against the fixture discriminator proves the discriminator/variant mapping
/// instead of only proving decode success.
fn client_matrix_test_update_kind(update : SessionUpdate) -> String {
  match update {
    UserMessageChunk(_) => "user_message_chunk"
    AgentMessageChunk(_) => "agent_message_chunk"
    AgentThoughtChunk(_) => "agent_thought_chunk"
    ToolCall(_) => "tool_call"
    ToolCallUpdate(_) => "tool_call_update"
    Plan(_) => "plan"
    AvailableCommandsUpdate(_) => "available_commands_update"
    CurrentModeUpdate(_) => "current_mode_update"
    ConfigOptionUpdate(_) => "config_option_update"
    SessionInfoUpdate(_) => "session_info_update"
    UsageUpdate(_) => "usage_update"
  }
}

///|
/// Assert that a rejected notification produced exactly one typed trace
/// intent and no JSON-RPC response.
fn client_matrix_test_trace_error(
  admission : ClientAdapterAdmission,
  method_name~ : String,
  code~ : JsonRpcErrorCode,
) -> Unit raise {
  let step = client_adapter_test_immediate(admission)
  assert_eq(step.outputs.length(), 1)
  match step.outputs[0] {
    Command(TraceError(method_name=traced, error~)) => {
      assert_eq(traced, method_name)
      assert_eq(error.code, code)
    }
    Response(_) => fail("notification rejection must not emit a response")
    Command(_) => fail("expected a trace intent")
  }
}

///|
/// Capture every delivered session update in the caller-owned typed sink.
fn client_matrix_test_capture_updates(
  seen~ : Array[SessionUpdateParams],
) -> ClientSessionUpdateHandler {
  async fn(params : SessionUpdateParams) -> Unit {
    @async.pause()
    seen.push(params)
  }
}

///|
fn client_matrix_test_capture_read(
  seen~ : Array[ReadTextFileParams],
) -> ClientReadTextFileHandler {
  async fn(params : ReadTextFileParams) -> ReadTextFileResult {
    @async.pause()
    seen.push(params)
    { content: "matrix-read", meta: Omitted, }
  }
}

///|
/// Model a missing file as the service-owned typed rejection: an unavailable
/// operation that the adapter surfaces as resource-not-found.
fn client_matrix_test_unavailable_read() -> ClientReadTextFileHandler {
  async fn(_params : ReadTextFileParams) -> ReadTextFileResult {
    @async.pause()
    raise HandlerError::UnavailableOperation(method_name="fs/read_text_file")
  }
}

///|
fn client_matrix_test_capture_write(
  seen~ : Array[WriteTextFileParams],
) -> ClientWriteTextFileHandler {
  async fn(params : WriteTextFileParams) -> WriteTextFileResult {
    @async.pause()
    seen.push(params)
    { meta: Omitted, }
  }
}

///|
/// Model a failed write as an application failure that must remain visible
/// as a JSON-RPC error, never a silent success.
fn client_matrix_test_failing_write() -> ClientWriteTextFileHandler {
  async fn(_params : WriteTextFileParams) -> WriteTextFileResult {
    @async.pause()
    raise HandlerError::Application(message="disk full")
  }
}

///|
fn client_matrix_test_fixed_create(
  terminal_id : String,
) -> ClientTerminalCreateHandler {
  async fn(_params : TerminalCreateParams) -> TerminalCreateResult {
    @async.pause()
    { terminal_id, meta: Omitted, }
  }
}

///|
/// A buggy service returning a degenerate empty terminal id.  The result
/// codec must turn this into an observable failure, never a success response.
fn client_matrix_test_degenerate_create() -> ClientTerminalCreateHandler {
  async fn(_params : TerminalCreateParams) -> TerminalCreateResult {
    @async.pause()
    { terminal_id: "", meta: Omitted, }
  }
}

///|
/// Capture every output query; only the live terminal id succeeds, unknown
/// ids are the service-owned resource failure.
fn client_matrix_test_tracked_output(
  terminal_id~ : String,
  seen~ : Array[TerminalOutputParams],
) -> ClientTerminalOutputHandler {
  async fn(params : TerminalOutputParams) -> TerminalOutputResult {
    @async.pause()
    seen.push(params)
    if params.terminal_id == terminal_id {
      {
        output: "matrix-output",
        truncated: false,
        exit_status: Value({
          exit_code: Value(0UL),
          signal: Omitted,
          meta: Omitted,
        }),
        meta: Omitted,
      }
    } else {
      raise HandlerError::UnavailableOperation(method_name="terminal/output")
    }
  }
}

///|
/// Return the final status by terminal id: normal exit or signal death.
/// Unknown ids are the service-owned resource failure.
fn client_matrix_test_status_wait() -> ClientTerminalWaitForExitHandler {
  async fn(params : TerminalWaitForExitParams) -> TerminalWaitForExitResult {
    @async.pause()
    if params.terminal_id == "exit-0" {
      { exit_code: Value(0UL), signal: Omitted, meta: Omitted, }
    } else if params.terminal_id == "signaled" {
      { exit_code: Omitted, signal: Value("SIGTERM"), meta: Omitted, }
    } else {
      raise HandlerError::UnavailableOperation(
        method_name="terminal/wait_for_exit",
      )
    }
  }
}

///|
/// Release exactly once.  The released-id registry is service-owned state;
/// repeat releases and post-release ids surface as resource failures.
fn client_matrix_test_release_once(
  terminal_id~ : String,
  released~ : Array[String],
) -> ClientTerminalReleaseHandler {
  async fn(params : TerminalReleaseParams) -> TerminalReleaseResult {
    @async.pause()
    if params.terminal_id == terminal_id && !released.contains(terminal_id) {
      released.push(terminal_id)
      { meta: Omitted, }
    } else {
      raise HandlerError::UnavailableOperation(method_name="terminal/release")
    }
  }
}

///|
/// Output handler honoring a service-owned released-id registry.
fn client_matrix_test_registry_output(
  terminal_id~ : String,
  released~ : Array[String],
) -> ClientTerminalOutputHandler {
  async fn(params : TerminalOutputParams) -> TerminalOutputResult {
    @async.pause()
    if params.terminal_id == terminal_id && !released.contains(terminal_id) {
      {
        output: "matrix-output",
        truncated: false,
        exit_status: Omitted,
        meta: Omitted,
      }
    } else {
      raise HandlerError::UnavailableOperation(method_name="terminal/output")
    }
  }
}

///|
fn client_matrix_test_form_result(
  result~ : ElicitationCreateResult,
  seen~ : Array[ElicitationFormParams],
) -> ClientElicitationFormHandler {
  async fn(params : ElicitationFormParams) -> ElicitationCreateResult {
    @async.pause()
    seen.push(params)
    result
  }
}

///|
fn client_matrix_test_url_result(
  result~ : ElicitationCreateResult,
  seen~ : Array[ElicitationUrlParams],
) -> ClientElicitationUrlHandler {
  async fn(params : ElicitationUrlParams) -> ElicitationCreateResult {
    @async.pause()
    seen.push(params)
    result
  }
}

///|
/// Complete only known elicitation ids.  The active-id registry is
/// service-owned; unknown ids must never be recorded as completed.
fn client_matrix_test_registry_complete(
  active~ : Array[String],
  completed~ : Array[String],
) -> ClientElicitationCompleteHandler {
  async fn(params : ElicitationCompleteParams) -> Unit {
    @async.pause()
    if active.contains(params.elicitation_id) {
      completed.push(params.elicitation_id)
    } else {
      raise HandlerError::UnavailableOperation(
        method_name="elicitation/complete",
      )
    }
  }
}

///|
async test "matrix D02 session update delivers every variant typed without responses" {
  let received : Array[SessionUpdateParams] = []
  let spec = client_spec(
    info=client_service_test_info("matrix-update"),
    session=client_session_service(
      session_update=client_matrix_test_capture_updates(seen=received),
      request_permission=client_service_test_permission,
    ),
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let fixtures : Array[(String, String)] = [
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"user_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"streamed\"},\"messageId\":\"m-1\"}}",
      "user_message_chunk",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"reply\"},\"messageId\":\"m-2\"}}",
      "agent_message_chunk",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"agent_thought_chunk\",\"content\":{\"type\":\"text\",\"text\":\"thinking\"}}}",
      "agent_thought_chunk",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"tool_call\",\"toolCallId\":\"call-1\",\"title\":\"Run\"}}",
      "tool_call",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"tool_call_update\",\"toolCallId\":\"call-1\",\"status\":\"completed\"}}",
      "tool_call_update",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"plan\",\"entries\":[{\"content\":\"Step\",\"priority\":\"high\",\"status\":\"completed\"}]}}",
      "plan",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"available_commands_update\",\"availableCommands\":[{\"name\":\"help\",\"description\":\"Show help\"}]}}",
      "available_commands_update",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
      "current_mode_update",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"config_option_update\",\"configOptions\":[{\"id\":\"confirm\",\"name\":\"Confirm\",\"type\":\"boolean\",\"currentValue\":true}]}}",
      "config_option_update",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"session_info_update\",\"title\":\"Matrix\",\"updatedAt\":\"2026-08-16T00:00:00Z\"}}",
      "session_info_update",
    ),
    (
      "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"usage_update\",\"used\":120,\"size\":240}}",
      "usage_update",
    ),
  ]
  for fixture in fixtures {
    let (source, expected_kind) = fixture
    let step = client_adapter_test_round_trip(
      state,
      endpoint,
      client_adapter_test_notification("session/update", source),
    )
    assert_eq(step.state, state)
    assert_eq(step.outputs.length(), 0)
    let delivered = received[received.length() - 1]
    assert_eq(delivered.session_id, "matrix")
    assert_eq(client_matrix_test_update_kind(delivered.update), expected_kind)
  }
  assert_eq(received.length(), 11)
  match received[3].update {
    ToolCall(tool_call) => assert_eq(tool_call.tool_call_id, "call-1")
    _ => fail("expected the tool_call fixture")
  }
  match received[8].update {
    ConfigOptionUpdate(options) =>
      assert_true(
        options.config_options[0].kind is Boolean({ current_value: true, }),
      )
    _ => fail("expected the config_option_update fixture")
  }
  match received[10].update {
    UsageUpdate(usage) => {
      assert_eq(usage.used, 120UL)
      assert_eq(usage.size, 240UL)
    }
    _ => fail("expected the usage_update fixture")
  }
  client_matrix_test_trace_error(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification(
        "session/update", "{\"sessionId\":\"matrix\",\"update\":{\"sessionUpdate\":\"bogus\"}}",
      ),
    ),
    method_name="session/update",
    code=InvalidParams,
  )
  client_matrix_test_trace_error(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification(
        "session/update", "{\"sessionId\":\"matrix\"}",
      ),
    ),
    method_name="session/update",
    code=InvalidParams,
  )
}

///|
async test "matrix D03 fs read text file is typed gated and strict" {
  let seen : Array[ReadTextFileParams] = []
  let files = try! client_file_system_service(
    read=client_matrix_test_capture_read(seen~),
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-read"),
    session=client_service_test_session(),
    file_system=files,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let read = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(3),
      "fs/read_text_file",
      "{\"sessionId\":\"s\",\"path\":\"/tmp/input\",\"line\":2,\"limit\":5}",
    ),
  )
  let decoded = read_text_file_result_from_json(
    client_adapter_test_success(read, Number(3)),
  )
  assert_eq(decoded.content, "matrix-read")
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].session_id, "s")
  assert_eq(seen[0].path, "/tmp/input")
  assert_eq(seen[0].line, Value(2UL))
  assert_eq(seen[0].limit, Value(5UL))
  assert_eq(read.state, state)

  let relative = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(4),
        "fs/read_text_file",
        "{\"sessionId\":\"s\",\"path\":\"relative\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(relative), InvalidParams)

  let zero_line = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(5),
        "fs/read_text_file",
        "{\"sessionId\":\"s\",\"path\":\"/tmp/input\",\"line\":0}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(zero_line), InvalidParams)

  let minimal = client_endpoint_test_endpoint("matrix-read-minimal", false)
  let ungated = client_adapter_test_immediate(
    client_adapter_admit(
      client_adapter_test_state(minimal),
      minimal,
      client_adapter_test_request(
        Number(6),
        "fs/read_text_file",
        "{\"sessionId\":\"s\",\"path\":\"/tmp/input\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(ungated), ResourceNotFound)

  // Boundary: file existence is service-owned; the missing-file rejection is
  // the handler's typed unavailable operation, surfaced as resource-not-found.
  let missing_files = try! client_file_system_service(
    read=client_matrix_test_unavailable_read(),
  )
  let missing_spec = client_spec(
    info=client_service_test_info("matrix-read-missing"),
    session=client_service_test_session(),
    file_system=missing_files,
  )
  let missing_endpoint = client_matrix_test_endpoint(missing_spec)
  let missing = client_adapter_test_round_trip(
    client_adapter_test_state(missing_endpoint),
    missing_endpoint,
    client_adapter_test_request(
      Number(7),
      "fs/read_text_file",
      "{\"sessionId\":\"s\",\"path\":\"/tmp/gone\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(missing), ResourceNotFound)
}

///|
async test "matrix D04 fs write text file is typed and failures stay visible" {
  let seen : Array[WriteTextFileParams] = []
  let files = try! client_file_system_service(
    write=client_matrix_test_capture_write(seen~),
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-write"),
    session=client_service_test_session(),
    file_system=files,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let write = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(4),
      "fs/write_text_file",
      "{\"sessionId\":\"s\",\"path\":\"/tmp/output\",\"content\":\"body\"}",
    ),
  )
  let decoded = write_text_file_result_from_json(
    client_adapter_test_success(write, Number(4)),
  )
  assert_eq(decoded.meta, Omitted)
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].path, "/tmp/output")
  assert_eq(seen[0].content, "body")
  assert_eq(write.state, state)

  for
    case in [
      (5L, "{\"sessionId\":\"s\",\"path\":\"relative\",\"content\":\"body\"}"),
      (6L, "{\"sessionId\":\"s\",\"path\":\"/tmp/output\"}"),
    ] {
    let (id, source) = case
    let rejected = client_adapter_test_immediate(
      client_adapter_admit(
        state,
        endpoint,
        client_adapter_test_request(Number(id), "fs/write_text_file", source),
      ),
    )
    assert_eq(client_adapter_test_error_code(rejected), InvalidParams)
  }

  // Boundary: write persistence is service-owned; a failed write must stay a
  // visible JSON-RPC error and never collapse into a success response.
  let failing_files = try! client_file_system_service(
    write=client_matrix_test_failing_write(),
  )
  let failing_spec = client_spec(
    info=client_service_test_info("matrix-write-failing"),
    session=client_service_test_session(),
    file_system=failing_files,
  )
  let failing_endpoint = client_matrix_test_endpoint(failing_spec)
  let failing = client_adapter_test_round_trip(
    client_adapter_test_state(failing_endpoint),
    failing_endpoint,
    client_adapter_test_request(
      Number(7),
      "fs/write_text_file",
      "{\"sessionId\":\"s\",\"path\":\"/tmp/output\",\"content\":\"body\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(failing), InternalError)
}

///|
async test "matrix D05 terminal create validates shape and terminal id" {
  let seen : Array[TerminalCreateParams] = []
  let terminal = client_terminal_service(
    create=async fn(params : TerminalCreateParams) -> TerminalCreateResult {
      @async.pause()
      seen.push(params)
      { terminal_id: "matrix-terminal", meta: Omitted, }
    },
    output=client_service_test_output,
    wait_for_exit=client_service_test_wait,
    kill=client_service_test_kill,
    release=client_service_test_release,
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-create"),
    session=client_service_test_session(),
    terminal~,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let created = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(5),
      "terminal/create",
      "{\"sessionId\":\"s\",\"command\":\"/bin/echo\",\"args\":[\"hi\"],\"env\":[{\"name\":\"KEY\",\"value\":\"v\"}],\"cwd\":\"/tmp\",\"outputByteLimit\":4096}",
    ),
  )
  let decoded = terminal_create_result_from_json(
    client_adapter_test_success(created, Number(5)),
  )
  assert_eq(decoded.terminal_id, "matrix-terminal")
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].command, "/bin/echo")
  assert_eq(seen[0].args, Value(["hi"]))
  match seen[0].env {
    Value(variables) => {
      assert_eq(variables.length(), 1)
      assert_eq(variables[0].name, "KEY")
      assert_eq(variables[0].value, "v")
    }
    _ => fail("env must reach the handler as a typed value")
  }
  assert_eq(seen[0].cwd, Value("/tmp"))
  assert_eq(seen[0].output_byte_limit, Value(4096UL))
  assert_eq(created.state, state)

  let relative_cwd = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(6),
        "terminal/create",
        "{\"sessionId\":\"s\",\"command\":\"/bin/echo\",\"cwd\":\"relative\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(relative_cwd), InvalidParams)

  let minimal = client_endpoint_test_endpoint("matrix-create-minimal", false)
  let ungated = client_adapter_test_immediate(
    client_adapter_admit(
      client_adapter_test_state(minimal),
      minimal,
      client_adapter_test_request(
        Number(7),
        "terminal/create",
        "{\"sessionId\":\"s\",\"command\":\"/bin/echo\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(ungated), ResourceNotFound)

  // Boundary: process spawning is service-owned; the SDK still rejects a
  // degenerate empty terminalId result instead of acknowledging it.
  let degenerate = client_terminal_service(
    create=client_matrix_test_degenerate_create(),
    output=client_service_test_output,
    wait_for_exit=client_service_test_wait,
    kill=client_service_test_kill,
    release=client_service_test_release,
  )
  let degenerate_spec = client_spec(
    info=client_service_test_info("matrix-create-degenerate"),
    session=client_service_test_session(),
    terminal=degenerate,
  )
  let degenerate_endpoint = client_matrix_test_endpoint(degenerate_spec)
  let degenerate_step = client_adapter_test_round_trip(
    client_adapter_test_state(degenerate_endpoint),
    degenerate_endpoint,
    client_adapter_test_request(
      Number(8),
      "terminal/create",
      "{\"sessionId\":\"s\",\"command\":\"/bin/echo\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(degenerate_step), InternalError)
}

///|
async test "matrix D06 terminal output is repeatable and result shape is exact" {
  let seen : Array[TerminalOutputParams] = []
  let terminal = client_terminal_service(
    create=client_matrix_test_fixed_create("matrix-terminal"),
    output=client_matrix_test_tracked_output(
      terminal_id="matrix-terminal",
      seen~,
    ),
    wait_for_exit=client_service_test_wait,
    kill=client_service_test_kill,
    release=client_service_test_release,
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-output"),
    session=client_service_test_session(),
    terminal~,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let exit_cases : Array[(Int64, ProtocolNullable[UInt64])] = [
    (6L, Value(0UL)),
    (7L, Value(0UL)),
  ]
  for case in exit_cases {
    let (id, expected_exit) = case
    let output = client_adapter_test_round_trip(
      state,
      endpoint,
      client_adapter_test_request(
        Number(id),
        "terminal/output",
        "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
      ),
    )
    let decoded = terminal_output_result_from_json(
      client_adapter_test_success(output, Number(id)),
    )
    assert_eq(decoded.output, "matrix-output")
    assert_eq(decoded.truncated, false)
    match decoded.exit_status {
      Value(status) => assert_eq(status.exit_code, expected_exit)
      _ => fail("exit status must decode as a typed value")
    }
  }
  assert_eq(seen.length(), 2)
  assert_eq(seen[0].terminal_id, "matrix-terminal")
  assert_eq(seen[1].terminal_id, "matrix-terminal")

  let malformed = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(8),
        "terminal/output",
        "{\"sessionId\":\"s\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(malformed), InvalidParams)

  // Boundary: terminal id validity is service-owned; an unknown (or released)
  // id is the handler's typed rejection surfaced as resource-not-found.
  let unknown = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(9),
      "terminal/output",
      "{\"sessionId\":\"s\",\"terminalId\":\"gone\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(unknown), ResourceNotFound)
}

///|
async test "matrix D07 terminal wait for exit returns the final status" {
  let terminal = client_terminal_service(
    create=client_matrix_test_fixed_create("matrix-terminal"),
    output=client_service_test_output,
    wait_for_exit=client_matrix_test_status_wait(),
    kill=client_service_test_kill,
    release=client_service_test_release,
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-wait"),
    session=client_service_test_session(),
    terminal~,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let exited = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(7),
      "terminal/wait_for_exit",
      "{\"sessionId\":\"s\",\"terminalId\":\"exit-0\"}",
    ),
  )
  let exit_decoded = terminal_wait_for_exit_result_from_json(
    client_adapter_test_success(exited, Number(7)),
  )
  assert_eq(exit_decoded.exit_code, Value(0UL))
  assert_eq(exit_decoded.signal, Omitted)

  let signaled = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(8),
      "terminal/wait_for_exit",
      "{\"sessionId\":\"s\",\"terminalId\":\"signaled\"}",
    ),
  )
  let signal_decoded = terminal_wait_for_exit_result_from_json(
    client_adapter_test_success(signaled, Number(8)),
  )
  assert_eq(signal_decoded.exit_code, Omitted)
  assert_eq(signal_decoded.signal, Value("SIGTERM"))

  let malformed = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(9),
        "terminal/wait_for_exit",
        "{\"sessionId\":\"s\",\"terminalId\":7}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(malformed), InvalidParams)

  // Boundary: id validity is service-owned; unknown ids stay typed failures.
  let unknown = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(10),
      "terminal/wait_for_exit",
      "{\"sessionId\":\"s\",\"terminalId\":\"gone\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(unknown), ResourceNotFound)
}

///|
async test "matrix D08 terminal kill terminates without releasing the id" {
  let seen : Array[TerminalOutputParams] = []
  let terminal = client_terminal_service(
    create=client_matrix_test_fixed_create("matrix-terminal"),
    output=client_matrix_test_tracked_output(
      terminal_id="matrix-terminal",
      seen~,
    ),
    wait_for_exit=client_service_test_wait,
    kill=client_service_test_kill,
    release=client_service_test_release,
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-kill"),
    session=client_service_test_session(),
    terminal~,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let killed = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(8),
      "terminal/kill",
      "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(killed, Number(8)))
  assert_eq(killed.state, state)
  // Boundary: kill/release lifecycle is service-owned and the SDK keeps no
  // terminal registry, so kill can never act as release: output on the same
  // id still dispatches and succeeds through the typed service.
  let output_after_kill = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(9),
      "terminal/output",
      "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(output_after_kill, Number(9)))
  assert_eq(seen.length(), 1)

  // Kill and release are distinct typed operations; crossing their
  // completions fails fast instead of aliasing one into the other.
  let admission = client_adapter_admit(
    state,
    endpoint,
    client_adapter_test_request(
      Number(10),
      "terminal/kill",
      "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  let (reserved, invocation) = match admission {
    Invoke(state=reserved, invocation~) => (reserved, invocation)
    Immediate(_) => fail("terminal/kill must be invoked")
  }
  let crossed : ClientAdapterCompletion = TerminalReleaseCompleted(
    id=Number(10),
    result=Ok({ meta: Omitted, }),
  )
  try client_adapter_complete(reserved, invocation, crossed) catch {
    CompletionMismatch(method_name="terminal/kill") => ()
    _ => fail("expected a kill/release completion mismatch")
  } noraise {
    _ => fail("expected a kill/release completion mismatch")
  }

  let malformed = client_adapter_test_immediate(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_request(
        Number(11),
        "terminal/kill",
        "{\"sessionId\":\"s\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(malformed), InvalidParams)
}

///|
async test "matrix D09 terminal release invalidates ids in the service" {
  let released : Array[String] = []
  let terminal = client_terminal_service(
    create=client_matrix_test_fixed_create("matrix-terminal"),
    output=client_matrix_test_registry_output(
      terminal_id="matrix-terminal",
      released~,
    ),
    wait_for_exit=client_service_test_wait,
    kill=client_service_test_kill,
    release=client_matrix_test_release_once(
      terminal_id="matrix-terminal",
      released~,
    ),
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-release"),
    session=client_service_test_session(),
    terminal~,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let released_step = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(9),
      "terminal/release",
      "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  ignore(client_adapter_test_success(released_step, Number(9)))
  // The SDK keeps no release state: the adapter state is untouched and id
  // invalidation lives entirely in the service registry below.
  assert_eq(released_step.state, state)

  // Boundary: after release the id must fail in the service; the typed
  // rejection is resource-not-found, never a stale success.
  let output_after_release = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(10),
      "terminal/output",
      "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  assert_eq(
    client_adapter_test_error_code(output_after_release),
    ResourceNotFound,
  )

  // Repeat release is diagnosable through the same typed path.
  let repeat_release = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_request(
      Number(11),
      "terminal/release",
      "{\"sessionId\":\"s\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  assert_eq(client_adapter_test_error_code(repeat_release), ResourceNotFound)
}

///|
async test "matrix D10 elicitation create outcomes are typed per mode" {
  let form_seen : Array[ElicitationFormParams] = []
  let accept_content = client_adapter_test_json(
    "{\"name\":\"Ada\",\"count\":2}",
  )
  let accepted : ElicitationCreateResult = {
    action: Accept,
    content: Value(accept_content),
    meta: Omitted,
  }
  let declined : ElicitationCreateResult = {
    action: Decline,
    content: Omitted,
    meta: Omitted,
  }
  let cancelled : ElicitationCreateResult = {
    action: Cancel,
    content: Omitted,
    meta: Omitted,
  }
  let form_files_spec = (result : ElicitationCreateResult) => {
    let elicitation = try! client_elicitation_service(
      form=client_matrix_test_form_result(result~, seen=form_seen),
    )
    client_spec(
      info=client_service_test_info("matrix-elicitation-form"),
      session=client_service_test_session(),
      elicitation~,
    )
  }
  let accept_endpoint = client_matrix_test_endpoint(form_files_spec(accepted))
  let accept_state = client_adapter_test_state(accept_endpoint)
  let form_request = "{\"mode\":\"form\",\"message\":\"Choose\",\"requestId\":\"request\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}}"
  let form_accepted = client_adapter_test_round_trip(
    accept_state,
    accept_endpoint,
    client_adapter_test_request(Number(10), "elicitation/create", form_request),
  )
  let accept_decoded = elicitation_create_result_from_json(
    client_adapter_test_success(form_accepted, Number(10)),
  )
  assert_eq(accept_decoded.action, Accept)
  assert_eq(accept_decoded.content, Value(accept_content))
  assert_eq(form_seen.length(), 1)
  assert_eq(form_seen[0].message, "Choose")
  match form_seen[0].scope {
    Request(String("request")) => ()
    _ => fail("request scope must reach the handler typed")
  }

  let decline_endpoint = client_matrix_test_endpoint(form_files_spec(declined))
  let form_declined = client_adapter_test_round_trip(
    client_adapter_test_state(decline_endpoint),
    decline_endpoint,
    client_adapter_test_request(Number(11), "elicitation/create", form_request),
  )
  let decline_decoded = elicitation_create_result_from_json(
    client_adapter_test_success(form_declined, Number(11)),
  )
  assert_eq(decline_decoded.action, Decline)
  assert_eq(decline_decoded.content, Omitted)

  let cancel_endpoint = client_matrix_test_endpoint(form_files_spec(cancelled))
  let form_cancelled = client_adapter_test_round_trip(
    client_adapter_test_state(cancel_endpoint),
    cancel_endpoint,
    client_adapter_test_request(Number(12), "elicitation/create", form_request),
  )
  let cancel_decoded = elicitation_create_result_from_json(
    client_adapter_test_success(form_cancelled, Number(12)),
  )
  assert_eq(cancel_decoded.action, Cancel)
  assert_eq(cancel_decoded.content, Omitted)

  let url_seen : Array[ElicitationUrlParams] = []
  let url_elicitation = try! client_elicitation_service(
    url=client_matrix_test_url_result(result=declined, seen=url_seen),
    complete=client_service_test_complete,
  )
  let url_spec = client_spec(
    info=client_service_test_info("matrix-elicitation-url"),
    session=client_service_test_session(),
    elicitation=url_elicitation,
  )
  let url_endpoint = client_matrix_test_endpoint(url_spec)
  let url_state = client_adapter_test_state(url_endpoint)
  let url_delivered = client_adapter_test_round_trip(
    url_state,
    url_endpoint,
    client_adapter_test_request(
      Number(13),
      "elicitation/create",
      "{\"mode\":\"url\",\"message\":\"Continue\",\"requestId\":\"request\",\"elicitationId\":\"matrix-url\",\"url\":\"https://example.test/approve\"}",
    ),
  )
  ignore(
    elicitation_create_result_from_json(
      client_adapter_test_success(url_delivered, Number(13)),
    ),
  )
  assert_eq(url_seen.length(), 1)
  assert_eq(url_seen[0].elicitation_id, "matrix-url")
  assert_eq(url_seen[0].url, "https://example.test/approve")

  // An unadvertised mode must not be displayed nor fabricate a response:
  // the capability gate rejects before any handler exists to call.
  let form_denied = client_adapter_test_immediate(
    client_adapter_admit(
      url_state,
      url_endpoint,
      client_adapter_test_request(
        Number(14),
        "elicitation/create",
        form_request,
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(form_denied), ResourceNotFound)
  let form_only_elicitation = try! client_elicitation_service(
    form=client_service_test_form,
  )
  let form_only_spec = client_spec(
    info=client_service_test_info("matrix-elicitation-form-only"),
    session=client_service_test_session(),
    elicitation=form_only_elicitation,
  )
  let form_only_endpoint = client_matrix_test_endpoint(form_only_spec)
  let url_denied = client_adapter_test_immediate(
    client_adapter_admit(
      client_adapter_test_state(form_only_endpoint),
      form_only_endpoint,
      client_adapter_test_request(
        Number(15),
        "elicitation/create",
        "{\"mode\":\"url\",\"message\":\"Continue\",\"requestId\":\"request\",\"elicitationId\":\"e\",\"url\":\"https://example.test\"}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(url_denied), ResourceNotFound)

  // Mode mixing is rejected by the strict codec before any handler runs.
  let mixed = client_adapter_test_immediate(
    client_adapter_admit(
      accept_state,
      accept_endpoint,
      client_adapter_test_request(
        Number(16),
        "elicitation/create",
        "{\"mode\":\"form\",\"message\":\"Choose\",\"requestId\":\"request\",\"elicitationId\":\"e\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}}}",
      ),
    ),
  )
  assert_eq(client_adapter_test_error_code(mixed), InvalidParams)

  // Unlike session/request_permission (whose selected option is validated
  // against the admitted request), every elicitation action is valid for any
  // request; the request-dependent invariant is the accept-content shape.  A
  // handler fabricating content on decline is rejected at completion instead
  // of silently dropping the payload.
  let fabricated : ElicitationCreateResult = {
    action: Decline,
    content: Value(accept_content),
    meta: Omitted,
  }
  let fabricated_endpoint = client_matrix_test_endpoint(
    form_files_spec(fabricated),
  )
  let fabricated_step = client_adapter_test_round_trip(
    client_adapter_test_state(fabricated_endpoint),
    fabricated_endpoint,
    client_adapter_test_request(Number(17), "elicitation/create", form_request),
  )
  assert_eq(client_adapter_test_error_code(fabricated_step), InternalError)
}

///|
async test "matrix D11 elicitation complete never finishes unknown ids" {
  let active : Array[String] = ["matrix-live"]
  let completed : Array[String] = []
  let elicitation = try! client_elicitation_service(
    url=client_service_test_url,
    complete=client_matrix_test_registry_complete(active~, completed~),
  )
  let spec = client_spec(
    info=client_service_test_info("matrix-complete"),
    session=client_service_test_session(),
    elicitation~,
  )
  let endpoint = client_matrix_test_endpoint(spec)
  let state = client_adapter_test_state(endpoint)
  let known = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_notification(
      "elicitation/complete", "{\"elicitationId\":\"matrix-live\"}",
    ),
  )
  assert_eq(known.state, state)
  assert_eq(known.outputs.length(), 0)
  assert_eq(completed, ["matrix-live"])

  // Boundary: id membership is service-owned; an unknown id must not be
  // recorded as completed and the failure stays a side-effect-free trace
  // intent because this is a notification, never a response.
  let unknown = client_adapter_test_round_trip(
    state,
    endpoint,
    client_adapter_test_notification(
      "elicitation/complete", "{\"elicitationId\":\"matrix-unknown\"}",
    ),
  )
  assert_eq(unknown.state, state)
  match unknown.outputs[0] {
    Command(TraceError(method_name="elicitation/complete", error~)) =>
      assert_eq(error.code, ResourceNotFound)
    _ => fail("unknown completion must be a trace intent")
  }
  assert_eq(completed, ["matrix-live"])

  client_matrix_test_trace_error(
    client_adapter_admit(
      state,
      endpoint,
      client_adapter_test_notification("elicitation/complete", "{}"),
    ),
    method_name="elicitation/complete",
    code=InvalidParams,
  )
}

///|
/// One minimal total owner port: this test only exercises the outbound
/// direction, so every inbound hook stays total and side-effect free.
fn client_matrix_test_owner_port() -> @connection.RuntimeOwnerPort[
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
/// body, mirroring the broker channel harness without engine internals.
async fn client_matrix_test_channel_run(
  ports : @runtime.RuntimePorts,
  captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]],
) -> Unit {
  @connection.connection_runtime_run_owner_with_outbound(
    ports,
    @runtime.runtime_default_options(),
    channel => {
      let _ = captured.try_put(channel) catch { _ => false }
      client_matrix_test_owner_port()
    },
  )
}

///|
/// Upstream unstable (RFD session-fork, Draft): the client wire frame for
/// `session/fork` mirrors `session/resume`'s client face — one typed forward
/// request frame with exact params, settled by one typed reply frame whose
/// session id addresses the fork copy.
async test "matrix session fork wire frame mirrors the resume client recipe" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let ports = client_runtime_test_ports(input, output, written, traces)
  let captured : @aqueue.Queue[@connection.RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      client_matrix_test_channel_run(ports, captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let connection = @broker.client_connection_over_channel(channel~)
      connection.fork_session({
        cwd: "/",
        session_id: "matrix",
        additional_directories: Omitted,
        mcp_servers: Omitted,
        meta: Omitted,
      })
    })
    // The fake agent answers the fork only after observing its frame, so the
    // request wire shape and the reply correlation stay observable.
    ignore(written.get())
    let fork_request = client_runtime_test_request(output[0])
    assert_eq(fork_request.method_name, "session/fork")
    assert_eq(fork_request.id, Number(1))
    assert_eq(
      fork_request.params,
      Some(client_adapter_test_json("{\"cwd\":\"/\",\"sessionId\":\"matrix\"}")),
    )
    input.put(
      client_runtime_test_chunk(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"sessionId\":\"matrix-fork-1\"}}\n",
      ),
    )
    let forked = submitter.wait()
    input.put(None)
    runner.wait()
    assert_eq(forked.session_id, "matrix-fork-1")
    assert_eq(forked.modes, Omitted)
    assert_eq(forked.config_options, Omitted)
  })
  assert_eq(output.length(), 1)
}
