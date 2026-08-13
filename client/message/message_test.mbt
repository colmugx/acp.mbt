///|
using @protocol_data {type ProtocolDecodeError, protocol_parse_json}

///|
fn client_messages_test_json(source : String) -> Json {
  protocol_parse_json(source) catch {
    _ => abort("test fixture must be valid JSON")
  }
}

///|
fn client_messages_test_protocol_error_detail(
  error : ProtocolDecodeError,
) -> String {
  match error {
    JsonParse(message~) => "JsonParse: " + message
    ExpectedObject(path~) => "ExpectedObject: " + path
    ExpectedArray(path~) => "ExpectedArray: " + path
    ExpectedString(path~) => "ExpectedString: " + path
    ExpectedBoolean(path~) => "ExpectedBoolean: " + path
    ExpectedNumber(path~) => "ExpectedNumber: " + path
    MissingField(path~) => "MissingField: " + path
    UnknownField(path~) => "UnknownField: " + path
    InvalidField(path~, reason~) => "InvalidField: " + path + ": " + reason
    InvalidDiscriminator(path~, value~) =>
      "InvalidDiscriminator: " + path + ": " + value
    InvalidPath(path~, value~) => "InvalidPath: " + path + ": " + value
    InvalidBase64(path~) => "InvalidBase64: " + path
  }
}

///|
fn client_messages_test_request(
  method_name : String,
  source : String,
) -> ClientRequest {
  let params = Some(client_messages_test_json(source))
  decode_client_request(method_name, params) catch {
    InvalidParams(method_name~, cause~) =>
      abort(
        "invalid params for " +
        method_name +
        ": " +
        client_messages_test_protocol_error_detail(cause),
      )
    UnknownMethod(method_name~) => abort("unknown method: " + method_name)
    WrongDirection(method_name~) => abort("wrong direction: " + method_name)
    WrongKind(method_name~) => abort("wrong kind: " + method_name)
  }
}

///|
test "every stable Agent-to-Client request decodes to its closed variant" {
  let permission = client_messages_test_request(
    "session/request_permission", "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call-1\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
  )
  assert_true(permission is SessionRequestPermission(_))

  let read = client_messages_test_request(
    "fs/read_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
  )
  assert_true(read is FsReadTextFile(_))

  let write = client_messages_test_request(
    "fs/write_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}",
  )
  assert_true(write is FsWriteTextFile(_))

  let create = client_messages_test_request(
    "terminal/create", "{\"sessionId\":\"s\",\"command\":\"echo\"}",
  )
  assert_true(create is TerminalCreate(_))

  let output = client_messages_test_request(
    "terminal/output", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(output is TerminalOutput(_))

  let wait_for_exit = client_messages_test_request(
    "terminal/wait_for_exit", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(wait_for_exit is TerminalWaitForExit(_))

  let kill = client_messages_test_request(
    "terminal/kill", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(kill is TerminalKill(_))

  let release = client_messages_test_request(
    "terminal/release", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(release is TerminalRelease(_))

  let form = client_messages_test_request(
    "elicitation/create", "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}",
  )
  assert_true(form is ElicitationCreate(Form(_)))

  let url = client_messages_test_request(
    "elicitation/create", "{\"mode\":\"url\",\"message\":\"Continue\",\"elicitationId\":\"e\",\"url\":\"https://example.test\",\"requestId\":1}",
  )
  assert_true(url is ElicitationCreate(Url(_)))
}

///|
test "notifications and cancellation decode with strict kinds" {
  let update = decode_client_notification(
    "session/update",
    Some(
      client_messages_test_json(
        "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
      ),
    ),
  )
  assert_true(update is SessionUpdate(_))

  let complete = decode_client_notification(
    "elicitation/complete",
    Some(client_messages_test_json("{\"elicitationId\":\"e\"}")),
  )
  assert_true(complete is ElicitationComplete(_))

  let string_cancel = decode_client_notification(
    "$/cancel_request",
    Some(client_messages_test_json("{\"requestId\":\"r-1\"}")),
  )
  match string_cancel {
    CancelRequest(String(value)) => assert_eq(value, "r-1")
    _ => fail("expected string cancellation id")
  }

  let integer_cancel = decode_client_notification(
    "$/cancel_request",
    Some(client_messages_test_json("{\"requestId\":7}")),
  )
  match integer_cancel {
    CancelRequest(Number(value)) => assert_eq(value, 7)
    _ => fail("expected integer cancellation id")
  }
}

///|
test "client dispatch errors are structured and direction-aware" {
  try decode_client_request("fs/read_text_file", None) catch {
    InvalidParams(method_name="fs/read_text_file", cause=MissingField(path=_)) =>
      ()
    _ => fail("expected structured invalid params")
  } noraise {
    _ => fail("expected missing params failure")
  }

  try
    decode_client_request(
      "fs/read_text_file",
      Some(
        client_messages_test_json("{\"sessionId\":\"s\",\"path\":\"relative\"}"),
      ),
    )
  catch {
    InvalidParams(
      method_name="fs/read_text_file",
      cause=InvalidPath(path=_, value=_)
    ) => ()
    _ => fail("expected nested params failure")
  } noraise {
    _ => fail("expected invalid path failure")
  }

  try decode_client_request("initialize", None) catch {
    WrongDirection(method_name="initialize") => ()
    _ => fail("expected wrong request direction")
  } noraise {
    _ => fail("expected wrong request direction failure")
  }

  try decode_client_request("session/update", None) catch {
    WrongDirection(method_name="session/update") => ()
    _ => fail("expected notification direction failure")
  } noraise {
    _ => fail("expected notification direction failure")
  }

  try decode_client_notification("session/cancel", None) catch {
    WrongDirection(method_name="session/cancel") => ()
    _ => fail("expected Client-to-Agent notification rejection")
  } noraise {
    _ => fail("expected Client-to-Agent notification rejection")
  }

  try decode_client_request("$/cancel_request", None) catch {
    WrongKind(method_name="$/cancel_request") => ()
    _ => fail("expected cancellation kind rejection")
  } noraise {
    _ => fail("expected cancellation kind rejection")
  }

  try decode_client_request("vendor/unknown", None) catch {
    UnknownMethod(method_name="vendor/unknown") => ()
    _ => fail("expected unknown method rejection")
  } noraise {
    _ => fail("expected unknown method rejection")
  }

  let null_cancel = decode_client_notification(
    "$/cancel_request",
    Some(client_messages_test_json("{\"requestId\":null}")),
  )
  match null_cancel {
    CancelRequest(Null) => ()
    _ => fail("expected null cancellation identifier")
  }
}

///|
test "client unions report their exact wire method" {
  let request = decode_client_request(
    "terminal/kill",
    Some(
      client_messages_test_json("{\"sessionId\":\"s\",\"terminalId\":\"t\"}"),
    ),
  )
  assert_eq(request.method_name(), "terminal/kill")
  let notification = decode_client_notification(
    "$/cancel_request",
    Some(client_messages_test_json("{\"requestId\":1}")),
  )
  assert_eq(notification.method_name(), "$/cancel_request")
}

///|
test "known v2 overlay methods are rejected by both Client v1 decoders" {
  for method_name in ["auth/login", "auth/logout"] {
    try decode_client_request(method_name, None) catch {
      UnknownMethod(method_name=actual) => assert_eq(actual, method_name)
      _ => fail("v2 overlay request must be rejected as unknown")
    } noraise {
      _ => fail("v2 overlay request must be rejected")
    }
    try decode_client_notification(method_name, None) catch {
      UnknownMethod(method_name=actual) => assert_eq(actual, method_name)
      _ => fail("v2 overlay notification must be rejected as unknown")
    } noraise {
      _ => fail("v2 overlay notification must be rejected")
    }
  }
}
