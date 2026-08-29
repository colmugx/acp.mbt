///|
fn agent_messages_test_json(source : String) -> Json {
  @protocol.protocol_parse_json(source) catch {
    _ => abort("test fixture must be valid JSON")
  }
}

///|
test "every stable Client-to-Agent request decodes to its closed variant" {
  let initialize = decode_agent_request(
    "initialize",
    Some(agent_messages_test_json("{\"protocolVersion\":1}")),
  )
  assert_true(initialize is Initialize(_))
  let authenticate = decode_agent_request(
    "authenticate",
    Some(agent_messages_test_json("{\"methodId\":\"token\"}")),
  )
  assert_true(authenticate is Authenticate(_))
  let logout = decode_agent_request(
    "logout",
    Some(agent_messages_test_json("{}")),
  )
  assert_true(logout is Logout(_))
  let new_session = decode_agent_request(
    "session/new",
    Some(agent_messages_test_json("{\"cwd\":\"/\",\"mcpServers\":[]}")),
  )
  assert_true(new_session is SessionNew(_))
  let load = decode_agent_request(
    "session/load",
    Some(
      agent_messages_test_json(
        "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
      ),
    ),
  )
  assert_true(load is SessionLoad(_))
  let resumed_request = decode_agent_request(
    "session/resume",
    Some(agent_messages_test_json("{\"sessionId\":\"s\",\"cwd\":\"/\"}")),
  )
  assert_true(resumed_request is SessionResume(_))
  let fork = decode_agent_request(
    "session/fork",
    Some(agent_messages_test_json("{\"sessionId\":\"s\",\"cwd\":\"/\"}")),
  )
  assert_true(fork is SessionFork(_))
  assert_eq(fork.method_name(), "session/fork")
  let list = decode_agent_request(
    "session/list",
    Some(agent_messages_test_json("{}")),
  )
  assert_true(list is SessionList(_))
  let delete = decode_agent_request(
    "session/delete",
    Some(agent_messages_test_json("{\"sessionId\":\"s\"}")),
  )
  assert_true(delete is SessionDelete(_))
  let close = decode_agent_request(
    "session/close",
    Some(agent_messages_test_json("{\"sessionId\":\"s\"}")),
  )
  assert_true(close is SessionClose(_))
  let set_mode = decode_agent_request(
    "session/set_mode",
    Some(agent_messages_test_json("{\"sessionId\":\"s\",\"modeId\":\"code\"}")),
  )
  assert_true(set_mode is SessionSetMode(_))
  let set_config = decode_agent_request(
    "session/set_config_option",
    Some(
      agent_messages_test_json(
        "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
      ),
    ),
  )
  assert_true(set_config is SessionSetConfigOption(_))
  let prompt = decode_agent_request(
    "session/prompt",
    Some(agent_messages_test_json("{\"sessionId\":\"s\",\"prompt\":[]}")),
  )
  assert_true(prompt is SessionPrompt(_))
}

///|
test "notifications decode and preserve string, integer, or null ids" {
  let session_cancel = decode_agent_notification(
    "session/cancel",
    Some(agent_messages_test_json("{\"sessionId\":\"s\"}")),
  )
  assert_true(session_cancel is SessionCancel(_))
  let string_cancel = decode_agent_notification(
    "$/cancel_request",
    Some(agent_messages_test_json("{\"requestId\":\"request-1\"}")),
  )
  match string_cancel {
    CancelRequest(String(value)) => assert_eq(value, "request-1")
    _ => fail("expected string cancellation id")
  }
  let integer_cancel = decode_agent_notification(
    "$/cancel_request",
    Some(agent_messages_test_json("{\"requestId\":42}")),
  )
  match integer_cancel {
    CancelRequest(Number(value)) => assert_eq(value, 42L)
    _ => fail("expected integer cancellation id")
  }
}

///|
test "dispatch errors distinguish malformed params unknown methods and direction" {
  try decode_agent_request("initialize", None) catch {
    InvalidParams(method_name="initialize", cause=MissingField(path=_)) => ()
    _ => fail("expected structured invalid params")
  } noraise {
    _ => fail("expected missing params to fail")
  }
  try decode_agent_request("vendor/unknown", None) catch {
    UnknownMethod(method_name="vendor/unknown") => ()
    _ => fail("expected unknown method")
  } noraise {
    _ => fail("expected unknown method to fail")
  }
  try decode_agent_request("fs/read_text_file", None) catch {
    WrongDirection(method_name="fs/read_text_file") => ()
    _ => fail("expected wrong direction")
  } noraise {
    _ => fail("expected wrong direction to fail")
  }
  try decode_agent_request("session/cancel", None) catch {
    WrongKind(method_name="session/cancel") => ()
    _ => fail("expected request/notification kind error")
  } noraise {
    _ => fail("expected wrong kind to fail")
  }
  try decode_agent_notification("session/fork", None) catch {
    WrongKind(method_name="session/fork") => ()
    _ => fail("expected fork notification kind error")
  } noraise {
    _ => fail("expected fork notification to fail")
  }
  let null_cancel = decode_agent_notification(
    "$/cancel_request",
    Some(agent_messages_test_json("{\"requestId\":null}")),
  )
  match null_cancel {
    CancelRequest(Null) => ()
    _ => fail("expected null cancellation id")
  }
}

///|
test "accepted union reports the fixed method name" {
  let request = decode_agent_request(
    "session/set_mode",
    Some(agent_messages_test_json("{\"sessionId\":\"s\",\"modeId\":\"code\"}")),
  )
  assert_eq(request.method_name(), "session/set_mode")
  let notification = decode_agent_notification(
    "$/cancel_request",
    Some(agent_messages_test_json("{\"requestId\":1}")),
  )
  assert_eq(notification.method_name(), "$/cancel_request")
}

///|
test "known v2 overlay methods are rejected by both Agent v1 decoders" {
  for method_name in ["auth/login", "auth/logout"] {
    try decode_agent_request(method_name, None) catch {
      UnknownMethod(method_name=actual) => assert_eq(actual, method_name)
      _ => fail("v2 overlay request must be rejected as unknown")
    } noraise {
      _ => fail("v2 overlay request must be rejected")
    }
    try decode_agent_notification(method_name, None) catch {
      UnknownMethod(method_name=actual) => assert_eq(actual, method_name)
      _ => fail("v2 overlay notification must be rejected as unknown")
    } noraise {
      _ => fail("v2 overlay notification must be rejected")
    }
  }
}
