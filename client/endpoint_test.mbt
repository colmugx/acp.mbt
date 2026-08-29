///|
fn client_endpoint_test_spec(
  name : String,
  full : Bool,
) -> Result[ClientSpec, ClientCompositionError] {
  let info = client_service_test_info(name)
  let session = client_service_test_session()
  if full {
    client_spec(
      info~,
      session~,
      file_system=client_service_test_files(),
      terminal=client_service_test_terminal(),
      elicitation=client_service_test_elicitation(),
    )
  } else {
    client_spec(info~, session~)
  }
}

///|
fn client_endpoint_test_read_params() -> ReadTextFileParams {
  {
    session_id: "session",
    path: "/tmp/input",
    line: Omitted,
    limit: Omitted,
    meta: Omitted,
  }
}

///|
fn client_endpoint_test_write_params() -> WriteTextFileParams {
  {
    session_id: "session",
    path: "/tmp/output",
    content: "body",
    meta: Omitted,
  }
}

///|
fn client_endpoint_test_permission() -> RequestPermissionRequest {
  {
    session_id: "session",
    tool_call: {
      tool_call_id: "tool",
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
fn client_endpoint_test_update() -> SessionUpdateParams {
  {
    session_id: "session",
    update: CurrentModeUpdate({ current_mode_id: "code", meta: Omitted, }),
    meta: Omitted,
  }
}

///|
fn client_endpoint_test_form() -> ElicitationFormParams {
  {
    scope: Request(String("request")),
    message: "Choose",
    requested_schema: try! protocol_parse_json(
      "{\"type\":\"object\",\"properties\":{}}",
    ),
    meta: Omitted,
  }
}

///|
fn client_endpoint_test_url() -> ElicitationUrlParams {
  {
    scope: Request(String("request")),
    elicitation_id: "elicitation",
    message: "Continue",
    url: "https://example.test",
    meta: Omitted,
  }
}

///|
fn client_endpoint_test_complete() -> ElicitationCompleteParams {
  { elicitation_id: "elicitation", meta: Omitted, }
}

///|
fn client_endpoint_test_endpoint(name : String, full : Bool) -> ClientEndpoint {
  let result = @reader.Reader::run(
    client_program(@reader.Reader::pure(client_endpoint_test_spec(name, full))),
    (),
  )
  result.unwrap()
}

///|
test "client Reader programs isolate capabilities per environment" {
  let projected : @reader.Reader[
    String,
    Result[ClientSpec, ClientCompositionError],
  ] = @reader.Reader::bind(@reader.asks(fn(env : String) { env }), fn(
    env : String,
  ) {
    @reader.Reader::pure(client_endpoint_test_spec(env, env == "full"))
  })
  let program = client_program(projected)
  let full = @reader.Reader::run(program, "full").unwrap()
  let minimal = @reader.Reader::run(program, "minimal").unwrap()
  let full_capabilities = full.capabilities()
  let minimal_capabilities = minimal.capabilities()

  match full_capabilities.fs {
    Value(fs) => {
      assert_eq(fs.read_text_file, Value(true))
      assert_eq(fs.write_text_file, Value(true))
    }
    _ => fail("full environment should advertise filesystem")
  }
  assert_eq(full_capabilities.terminal, Value(true))
  match full_capabilities.elicitation {
    Value(elicitation) => {
      assert_eq(elicitation.form, Value({ meta: Omitted, }))
      assert_eq(elicitation.url, Value({ meta: Omitted, }))
    }
    _ => fail("full environment should advertise elicitation")
  }

  assert_eq(minimal_capabilities.fs, Omitted)
  assert_eq(minimal_capabilities.terminal, Omitted)
  assert_eq(minimal_capabilities.elicitation, Omitted)
}

///|
test "filesystem capability derivation remains independent" {
  let result = client_spec(
    info=client_service_test_info("read-only"),
    session=client_service_test_session(),
    file_system=client_service_test_read_only_files(),
  )
  let endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(result)),
    (),
  ).unwrap()
  match endpoint.capabilities().fs {
    Value(fs) => {
      assert_eq(fs.read_text_file, Value(true))
      assert_eq(fs.write_text_file, Omitted)
    }
    _ => fail("read-only filesystem should advertise only read")
  }
}

///|
async test "all typed Client endpoint invocations are callable" {
  let endpoint = client_endpoint_test_endpoint("all", true)
  endpoint.session_update(client_endpoint_test_update())
  let permission = endpoint.request_permission(
    client_endpoint_test_permission(),
  )
  assert_true(permission.outcome is Cancelled)

  let read = endpoint.read_text_file(client_endpoint_test_read_params())
  assert_eq(read.content, "read")
  ignore(endpoint.write_text_file(client_endpoint_test_write_params()))

  let terminal_create = endpoint.terminal_create({
    session_id: "session",
    command: "echo",
    args: Omitted,
    env: Omitted,
    cwd: Omitted,
    output_byte_limit: Omitted,
    meta: Omitted,
  })
  assert_eq(terminal_create.terminal_id, "terminal")
  ignore(
    endpoint.terminal_output({
      session_id: "session",
      terminal_id: "terminal",
      meta: Omitted,
    }),
  )
  ignore(
    endpoint.terminal_wait_for_exit({
      session_id: "session",
      terminal_id: "terminal",
      meta: Omitted,
    }),
  )
  ignore(
    endpoint.terminal_kill({
      session_id: "session",
      terminal_id: "terminal",
      meta: Omitted,
    }),
  )
  ignore(
    endpoint.terminal_release({
      session_id: "session",
      terminal_id: "terminal",
      meta: Omitted,
    }),
  )

  let form = endpoint.elicitation_form(client_endpoint_test_form())
  assert_true(form.action is Accept)
  let url = endpoint.elicitation_url(client_endpoint_test_url())
  assert_true(url.action is Accept)
  endpoint.elicitation_complete(client_endpoint_test_complete())
}

///|
async test "missing optional endpoint operation is structured" {
  let endpoint = client_endpoint_test_endpoint("minimal", false)
  try endpoint.read_text_file(client_endpoint_test_read_params()) catch {
    UnavailableOperation(method_name="fs/read_text_file") => ()
    _ => fail("expected unavailable filesystem operation")
  } noraise {
    _ => fail("expected unavailable filesystem operation")
  }
}

///|
async test "ordinary handler errors map at the endpoint boundary" {
  let file_system = try! client_file_system_service(
    read=client_service_test_failing_read,
  )
  let spec = client_spec(
    info=client_service_test_info("failure"),
    session=client_service_test_session(),
    file_system~,
  )
  let endpoint = @reader.Reader::run(
    client_program(@reader.Reader::pure(spec)),
    (),
  ).unwrap()
  try endpoint.read_text_file(client_endpoint_test_read_params()) catch {
    Application(message~) => assert_true(message.length() > 0)
    _ => fail("expected generic handler failure to map to Application")
  } noraise {
    _ => fail("expected generic handler failure to map to Application")
  }
}
