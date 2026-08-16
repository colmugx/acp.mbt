///|
fn client_service_test_info(name : String) -> Implementation {
  { name, title: Omitted, version: "test", meta: Omitted }
}

///|
async fn client_service_test_update(_params : SessionUpdateParams) -> Unit {
  @async.pause()
}

///|
async fn client_service_test_permission(
  _request : RequestPermissionRequest,
) -> RequestPermissionResponse {
  @async.pause()
  { outcome: Cancelled, meta: Omitted }
}

///|
async fn client_service_test_read(
  _params : ReadTextFileParams,
) -> ReadTextFileResult {
  @async.pause()
  { content: "read", meta: Omitted }
}

///|
async fn client_service_test_failing_read(
  _params : ReadTextFileParams,
) -> ReadTextFileResult {
  @async.pause()
  raise ProtocolDecodeError::InvalidField(
    path="client-test",
    reason="handler failure",
  )
}

///|
async fn client_service_test_write(
  _params : WriteTextFileParams,
) -> WriteTextFileResult {
  @async.pause()
  { meta: Omitted }
}

///|
async fn client_service_test_create(
  _params : TerminalCreateParams,
) -> TerminalCreateResult {
  @async.pause()
  { terminal_id: "terminal", meta: Omitted }
}

///|
async fn client_service_test_output(
  _params : TerminalOutputParams,
) -> TerminalOutputResult {
  @async.pause()
  { output: "output", truncated: false, exit_status: Omitted, meta: Omitted }
}

///|
async fn client_service_test_wait(
  _params : TerminalWaitForExitParams,
) -> TerminalWaitForExitResult {
  @async.pause()
  { exit_code: Value(0UL), signal: Omitted, meta: Omitted }
}

///|
async fn client_service_test_kill(
  _params : TerminalKillParams,
) -> TerminalKillResult {
  @async.pause()
  { meta: Omitted }
}

///|
async fn client_service_test_release(
  _params : TerminalReleaseParams,
) -> TerminalReleaseResult {
  @async.pause()
  { meta: Omitted }
}

///|
async fn client_service_test_form(
  _params : ElicitationFormParams,
) -> ElicitationCreateResult {
  @async.pause()
  { action: Accept, content: Omitted, meta: Omitted }
}

///|
async fn client_service_test_url(
  _params : ElicitationUrlParams,
) -> ElicitationCreateResult {
  @async.pause()
  { action: Accept, content: Omitted, meta: Omitted }
}

///|
async fn client_service_test_complete(
  _params : ElicitationCompleteParams,
) -> Unit {
  @async.pause()
}

///|
fn client_service_test_session() -> ClientSessionService {
  client_session_service(
    session_update=client_service_test_update,
    request_permission=client_service_test_permission,
  )
}

///|
fn client_service_test_files() -> ClientFileSystemService {
  try! client_file_system_service(
    read=client_service_test_read,
    write=client_service_test_write,
  )
}

///|
fn client_service_test_read_only_files() -> ClientFileSystemService {
  try! client_file_system_service(read=client_service_test_read)
}

///|
fn client_service_test_terminal() -> ClientTerminalService {
  client_terminal_service(
    create=client_service_test_create,
    output=client_service_test_output,
    wait_for_exit=client_service_test_wait,
    kill=client_service_test_kill,
    release=client_service_test_release,
  )
}

///|
fn client_service_test_elicitation() -> ClientElicitationService {
  try! client_elicitation_service(
    form=client_service_test_form,
    url=client_service_test_url,
    complete=client_service_test_complete,
  )
}

///|
test "client services reject contradictory optional combinations" {
  try client_file_system_service() catch {
    MissingRequiredService(
      service_name="fs/read_text_file or fs/write_text_file"
    ) => ()
    _ => fail("expected empty filesystem service to fail")
  } noraise {
    _ => fail("expected empty filesystem service to fail")
  }

  try client_elicitation_service(url=client_service_test_url) catch {
    ConflictingSupport(reason="elicitation/url requires elicitation/complete") =>
      ()
    _ => fail("expected URL elicitation to require completion")
  } noraise {
    _ => fail("expected URL elicitation to require completion")
  }

  try client_elicitation_service() catch {
    MissingRequiredService(service_name="elicitation handler") => ()
    _ => fail("expected empty elicitation service to fail")
  } noraise {
    _ => fail("expected empty elicitation service to fail")
  }
}

///|
test "client spec validates implementation and required baseline service" {
  let invalid = client_spec(
    info={ name: "", title: Omitted, version: "test", meta: Omitted },
    session=client_service_test_session(),
  )
  match invalid {
    Err(InvalidImplementation(reason="client name must not be empty")) => ()
    _ => fail("expected invalid client implementation")
  }
}
