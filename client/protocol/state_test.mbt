///|
using @message {
  type ClientNotification,
  type ClientMessageError,
  type ClientRequest,
  decode_client_request,
  decode_client_notification,
}

///|
using @protocol_data {
  type ClientCapabilities,
  type ProtocolNullable,
  type CapabilityMarker,
  protocol_parse_json,
}

///|
fn client_state_test_marker() -> CapabilityMarker {
  { meta: Omitted, }
}

///|
fn client_state_test_capabilities(
  read : ProtocolNullable[Bool],
  write : ProtocolNullable[Bool],
  terminal : ProtocolNullable[Bool],
  form : ProtocolNullable[CapabilityMarker],
  url : ProtocolNullable[CapabilityMarker],
) -> ClientCapabilities {
  {
    fs: Value({ read_text_file: read, write_text_file: write, meta: Omitted, }),
    terminal,
    elicitation: Value({ form, url, meta: Omitted, }),
    session: Omitted,
    plan: Omitted,
    auth: Omitted,
    meta: Omitted,
  }
}

///|
fn client_state_test_json(source : String) -> Json {
  protocol_parse_json(source) catch {
    _ => abort("test fixture must be valid JSON")
  }
}

///|
fn client_state_test_request(
  method_name : String,
  source : String,
) -> ClientRequest raise ClientMessageError {
  let value = client_state_test_json(source)
  decode_client_request(method_name, Some(value))
}

///|
fn client_state_test_notification(
  method_name : String,
  source : String,
) -> ClientNotification raise ClientMessageError {
  let value = client_state_test_json(source)
  decode_client_notification(method_name, Some(value))
}

///|
fn client_state_test_permission_request() -> ClientRequest raise ClientMessageError {
  client_state_test_request(
    "session/request_permission", "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call-1\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
  )
}

///|
fn client_state_test_update_notification() -> ClientNotification raise ClientMessageError {
  client_state_test_notification(
    "session/update", "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
  )
}

///|
fn client_state_test_complete_notification() -> ClientNotification raise ClientMessageError {
  client_state_test_notification(
    "elicitation/complete", "{\"elicitationId\":\"e\"}",
  )
}

///|
fn client_state_test_form_request() -> ClientRequest raise ClientMessageError {
  client_state_test_request(
    "elicitation/create", "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}",
  )
}

///|
fn client_state_test_url_request() -> ClientRequest raise ClientMessageError {
  client_state_test_request(
    "elicitation/create", "{\"mode\":\"url\",\"message\":\"Continue\",\"elicitationId\":\"e\",\"url\":\"https://example.test\",\"requestId\":1}",
  )
}

///|
test "unready client rejects business traffic and Ready is one-shot" {
  let capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Omitted,
    Omitted,
    Omitted,
  )
  let state = client_protocol_state_new(capabilities=Value(capabilities))
  let read = client_state_test_request(
    "fs/read_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
  )
  try client_protocol_reduce(state, Request(read)) catch {
    NotReady(method_name="fs/read_text_file") => ()
    _ => fail("expected unready request rejection")
  } noraise {
    _ => fail("expected unready request rejection")
  }

  let ready = client_protocol_reduce(state, Ready)
  assert_eq(ready.state.phase, Ready)
  assert_eq(ready.commands.length(), 0)
  try client_protocol_reduce(ready.state, Ready) catch {
    AlreadyReady => ()
    _ => fail("expected repeated Ready rejection")
  } noraise {
    _ => fail("expected repeated Ready rejection")
  }
}

///|
test "permission and session updates are baseline traffic" {
  let capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Omitted,
    Omitted,
    Omitted,
  )
  let state = client_protocol_state_ready(capabilities=Value(capabilities))
  let permission = client_state_test_permission_request()
  let permission_step = client_protocol_reduce(state, Request(permission))
  assert_true(
    permission_step.commands[0] is DispatchRequest(SessionRequestPermission(_)),
  )
  let update = client_state_test_update_notification()
  let update_step = client_protocol_reduce(state, Notification(update))
  assert_true(update_step.commands[0] is DispatchNotification(SessionUpdate(_)))
}

///|
test "filesystem read and write capabilities are independent" {
  let read_only_capabilities = client_state_test_capabilities(
    Value(true),
    Value(false),
    Omitted,
    Omitted,
    Omitted,
  )
  let read_only = client_protocol_state_ready(
    capabilities=Value(read_only_capabilities),
  )
  let read_only_before = read_only
  let read = client_state_test_request(
    "fs/read_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
  )
  assert_true(
    client_protocol_reduce(read_only, Request(read)).commands[0]
    is DispatchRequest(FsReadTextFile(_)),
  )
  let write = client_state_test_request(
    "fs/write_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}",
  )
  try client_protocol_reduce(read_only, Request(write)) catch {
    CapabilityDenied(
      method_name="fs/write_text_file",
      capability="fs.writeTextFile"
    ) => ()
    _ => fail("expected independent write gate")
  } noraise {
    _ => fail("expected independent write gate")
  }
  assert_eq(read_only, read_only_before)

  let write_only_capabilities = client_state_test_capabilities(
    Value(false),
    Value(true),
    Omitted,
    Omitted,
    Omitted,
  )
  let write_only = client_protocol_state_ready(
    capabilities=Value(write_only_capabilities),
  )
  let write_only_before = write_only
  assert_true(
    client_protocol_reduce(write_only, Request(write)).commands[0]
    is DispatchRequest(FsWriteTextFile(_)),
  )
  try client_protocol_reduce(write_only, Request(read)) catch {
    CapabilityDenied(
      method_name="fs/read_text_file",
      capability="fs.readTextFile"
    ) => ()
    _ => fail("expected independent read gate")
  } noraise {
    _ => fail("expected independent read gate")
  }
  assert_eq(write_only, write_only_before)
}

///|
test "one terminal capability gates all terminal requests" {
  let capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Value(false),
    Omitted,
    Omitted,
  )
  let state = client_protocol_state_ready(capabilities=Value(capabilities))
  let state_before = state
  let requests : Array[ClientRequest] = [
    client_state_test_request(
      "terminal/create", "{\"sessionId\":\"s\",\"command\":\"echo\"}",
    ),
    client_state_test_request(
      "terminal/output", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
    ),
    client_state_test_request(
      "terminal/wait_for_exit", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
    ),
    client_state_test_request(
      "terminal/kill", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
    ),
    client_state_test_request(
      "terminal/release", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
    ),
  ]
  for request in requests {
    try client_protocol_reduce(state, Request(request)) catch {
      CapabilityDenied(method_name=_, capability="terminal") => ()
      _ => fail("expected terminal capability gate")
    } noraise {
      _ => fail("expected terminal capability gate")
    }
    assert_eq(state, state_before)
  }

  let enabled_capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Value(true),
    Omitted,
    Omitted,
  )
  let enabled = client_protocol_state_ready(
    capabilities=Value(enabled_capabilities),
  )
  for request in requests {
    assert_true(
      client_protocol_reduce(enabled, Request(request)).commands[0]
      is DispatchRequest(_),
    )
  }
}

///|
test "elicitation form and URL gates are payload-specific and empty outer objects deny both" {
  let form_only_capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Omitted,
    Value(client_state_test_marker()),
    Omitted,
  )
  let form_only = client_protocol_state_ready(
    capabilities=Value(form_only_capabilities),
  )
  let form = client_state_test_form_request()
  let url = client_state_test_url_request()
  let complete = client_state_test_complete_notification()
  assert_true(
    client_protocol_reduce(form_only, Request(form)).commands[0]
    is DispatchRequest(ElicitationCreate(Form(_))),
  )
  try client_protocol_reduce(form_only, Request(url)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected URL-specific gate")
  } noraise {
    _ => fail("expected URL-specific gate")
  }
  try client_protocol_reduce(form_only, Notification(complete)) catch {
    CapabilityDenied(
      method_name="elicitation/complete",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected URL-specific completion gate")
  } noraise {
    _ => fail("expected URL-specific completion gate")
  }

  let url_only_capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Omitted,
    Omitted,
    Value(client_state_test_marker()),
  )
  let url_only = client_protocol_state_ready(
    capabilities=Value(url_only_capabilities),
  )
  assert_true(
    client_protocol_reduce(url_only, Request(url)).commands[0]
    is DispatchRequest(ElicitationCreate(Url(_))),
  )
  assert_true(
    client_protocol_reduce(url_only, Notification(complete)).commands[0]
    is DispatchNotification(ElicitationComplete(_)),
  )
  try client_protocol_reduce(url_only, Request(form)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.form"
    ) => ()
    _ => fail("expected form-specific gate")
  } noraise {
    _ => fail("expected form-specific gate")
  }

  let empty_outer_capabilities = client_state_test_capabilities(
    Omitted,
    Omitted,
    Omitted,
    Omitted,
    Omitted,
  )
  let empty_outer = client_protocol_state_ready(
    capabilities=Value(empty_outer_capabilities),
  )
  try client_protocol_reduce(empty_outer, Request(form)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.form"
    ) => ()
    _ => fail("expected empty elicitation object to deny form")
  } noraise {
    _ => fail("expected empty elicitation object to deny form")
  }
  try client_protocol_reduce(empty_outer, Request(url)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected empty elicitation object to deny URL")
  } noraise {
    _ => fail("expected empty elicitation object to deny URL")
  }

  let omitted_state = client_protocol_state_ready(capabilities=Omitted)
  try client_protocol_reduce(omitted_state, Notification(complete)) catch {
    CapabilityDenied(
      method_name="elicitation/complete",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected omitted capabilities to deny completion")
  } noraise {
    _ => fail("expected omitted capabilities to deny completion")
  }

  let null_state = client_protocol_state_ready(capabilities=Null)
  try client_protocol_reduce(null_state, Request(form)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.form"
    ) => ()
    _ => fail("expected null capabilities to deny form")
  } noraise {
    _ => fail("expected null capabilities to deny form")
  }
  try client_protocol_reduce(null_state, Notification(complete)) catch {
    CapabilityDenied(
      method_name="elicitation/complete",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected null capabilities to deny completion")
  } noraise {
    _ => fail("expected null capabilities to deny completion")
  }
}

///|
test "cancellation notifications become pure commands for string and integer ids" {
  let state = client_protocol_state_ready(capabilities=Omitted)
  let unready = client_protocol_state_new(capabilities=Omitted)
  let string_cancel = client_state_test_notification(
    "$/cancel_request", "{\"requestId\":\"request-1\"}",
  )
  let unready_step = client_protocol_reduce(
    unready,
    Notification(string_cancel),
  )
  assert_true(
    unready_step.commands[0] is CancelRequest(request_id=String("request-1")),
  )
  let string_step = client_protocol_reduce(state, Notification(string_cancel))
  assert_true(
    string_step.commands[0] is CancelRequest(request_id=String("request-1")),
  )

  let integer_cancel = client_state_test_notification(
    "$/cancel_request", "{\"requestId\":42}",
  )
  let integer_step = client_protocol_reduce(state, Notification(integer_cancel))
  assert_true(integer_step.commands[0] is CancelRequest(request_id=Number(42)))
}
