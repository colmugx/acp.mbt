///|
using @agent_message {decode_agent_notification, decode_agent_request}

///|
using @client_message {decode_client_notification, decode_client_request}

///|
using @protocol_data {protocol_parse_json}

///|
fn broker_codec_test_json(source : String) -> Json {
  protocol_parse_json(source) catch {
    _ => abort("broker codec fixture must be valid JSON")
  }
}

///|
fn broker_codec_test_client_request(
  method_name : String,
  source : String,
) -> ClientRequest {
  decode_client_request(method_name, Some(broker_codec_test_json(source))) catch {
    _ => abort("invalid ClientRequest fixture for " + method_name)
  }
}

///|
fn broker_codec_test_agent_request(
  method_name : String,
  source : String,
) -> AgentRequest {
  decode_agent_request(method_name, Some(broker_codec_test_json(source))) catch {
    _ => abort("invalid AgentRequest fixture for " + method_name)
  }
}

///|
fn broker_codec_test_client_notification(
  method_name : String,
  source : String,
) -> ClientNotification {
  decode_client_notification(method_name, Some(broker_codec_test_json(source))) catch {
    _ => abort("invalid ClientNotification fixture for " + method_name)
  }
}

///|
fn broker_codec_test_agent_notification(
  method_name : String,
  source : String,
) -> AgentNotification {
  decode_agent_notification(method_name, Some(broker_codec_test_json(source))) catch {
    _ => abort("invalid AgentNotification fixture for " + method_name)
  }
}

///|
fn broker_codec_test_assert_payload(
  payload : BrokerWirePayload,
  method_name : String,
  expected_params : String,
) -> Unit raise {
  assert_eq(payload.method_name, method_name)
  assert_eq(payload.params, broker_codec_test_json(expected_params))
}

///|
test "broker encodes every Agent-to-Client request with exact method and params" {
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "session/request_permission", "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      ),
    ),
    "session/request_permission",
    "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "fs/read_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
      ),
    ),
    "fs/read_text_file",
    "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "fs/write_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}",
      ),
    ),
    "fs/write_text_file",
    "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "terminal/create", "{\"sessionId\":\"s\",\"command\":\"echo\"}",
      ),
    ),
    "terminal/create",
    "{\"sessionId\":\"s\",\"command\":\"echo\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "terminal/output", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
      ),
    ),
    "terminal/output",
    "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "terminal/wait_for_exit", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
      ),
    ),
    "terminal/wait_for_exit",
    "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "terminal/kill", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
      ),
    ),
    "terminal/kill",
    "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "terminal/release", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
      ),
    ),
    "terminal/release",
    "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_request_payload(
      broker_codec_test_client_request(
        "elicitation/create", "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}",
      ),
    ),
    "elicitation/create",
    "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}",
  )
}

///|
test "broker encodes every Client notification including cancellation" {
  broker_codec_test_assert_payload(
    broker_client_notification_payload(
      broker_codec_test_client_notification(
        "session/update", "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
      ),
    ),
    "session/update",
    "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}",
  )
  broker_codec_test_assert_payload(
    broker_client_notification_payload(
      broker_codec_test_client_notification(
        "elicitation/complete", "{\"elicitationId\":\"e\"}",
      ),
    ),
    "elicitation/complete",
    "{\"elicitationId\":\"e\"}",
  )
  broker_codec_test_assert_payload(
    broker_client_notification_payload(
      broker_codec_test_client_notification(
        "$/cancel_request", "{\"requestId\":42}",
      ),
    ),
    "$/cancel_request",
    "{\"requestId\":42}",
  )
}

///|
test "broker encodes every Client-to-Agent request with exact method and params" {
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request("initialize", "{\"protocolVersion\":1}"),
    ),
    "initialize",
    "{\"protocolVersion\":1}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "authenticate", "{\"methodId\":\"token\"}",
      ),
    ),
    "authenticate",
    "{\"methodId\":\"token\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request("logout", "{}"),
    ),
    "logout",
    "{}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "session/new", "{\"cwd\":\"/\",\"mcpServers\":[]}",
      ),
    ),
    "session/new",
    "{\"cwd\":\"/\",\"mcpServers\":[]}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "session/load", "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
      ),
    ),
    "session/load",
    "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "session/resume", "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
      ),
    ),
    "session/resume",
    "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request("session/list", "{}"),
    ),
    "session/list",
    "{}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request("session/delete", "{\"sessionId\":\"s\"}"),
    ),
    "session/delete",
    "{\"sessionId\":\"s\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request("session/close", "{\"sessionId\":\"s\"}"),
    ),
    "session/close",
    "{\"sessionId\":\"s\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "session/set_mode", "{\"sessionId\":\"s\",\"modeId\":\"code\"}",
      ),
    ),
    "session/set_mode",
    "{\"sessionId\":\"s\",\"modeId\":\"code\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "session/set_config_option", "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
      ),
    ),
    "session/set_config_option",
    "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
  )
  broker_codec_test_assert_payload(
    broker_agent_request_payload(
      broker_codec_test_agent_request(
        "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[]}",
      ),
    ),
    "session/prompt",
    "{\"sessionId\":\"s\",\"prompt\":[]}",
  )
}

///|
test "broker encodes every Agent notification including cancellation" {
  broker_codec_test_assert_payload(
    broker_agent_notification_payload(
      broker_codec_test_agent_notification(
        "session/cancel", "{\"sessionId\":\"s\"}",
      ),
    ),
    "session/cancel",
    "{\"sessionId\":\"s\"}",
  )
  broker_codec_test_assert_payload(
    broker_agent_notification_payload(
      broker_codec_test_agent_notification(
        "$/cancel_request", "{\"requestId\":42}",
      ),
    ),
    "$/cancel_request",
    "{\"requestId\":42}",
  )
}

///|
test "broker decodes every Agent-to-Client reply by originating request" {
  let permission = broker_codec_test_client_request(
    "session/request_permission", "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
  )
  assert_true(
    broker_decode_client_request_result(
      permission,
      broker_codec_test_json(
        "{\"outcome\":{\"outcome\":\"selected\",\"optionId\":\"allow\"}}",
      ),
    )
    is AgentReplyRequestPermission(_),
  )

  let read = broker_codec_test_client_request(
    "fs/read_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
  )
  assert_true(
    broker_decode_client_request_result(
      read,
      broker_codec_test_json("{\"content\":\"body\"}"),
    )
    is AgentReplyFsReadTextFile(_),
  )
  let write = broker_codec_test_client_request(
    "fs/write_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}",
  )
  assert_true(
    broker_decode_client_request_result(write, broker_codec_test_json("{}"))
    is AgentReplyFsWriteTextFile(_),
  )

  let create = broker_codec_test_client_request(
    "terminal/create", "{\"sessionId\":\"s\",\"command\":\"echo\"}",
  )
  assert_true(
    broker_decode_client_request_result(
      create,
      broker_codec_test_json("{\"terminalId\":\"t\"}"),
    )
    is AgentReplyTerminalCreate(_),
  )
  let output = broker_codec_test_client_request(
    "terminal/output", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(
    broker_decode_client_request_result(
      output,
      broker_codec_test_json("{\"output\":\"body\",\"truncated\":false}"),
    )
    is AgentReplyTerminalOutput(_),
  )
  let wait_for_exit = broker_codec_test_client_request(
    "terminal/wait_for_exit", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(
    broker_decode_client_request_result(
      wait_for_exit,
      broker_codec_test_json("{}"),
    )
    is AgentReplyTerminalWaitForExit(_),
  )
  let kill = broker_codec_test_client_request(
    "terminal/kill", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(
    broker_decode_client_request_result(kill, broker_codec_test_json("{}"))
    is AgentReplyTerminalKill(_),
  )
  let release = broker_codec_test_client_request(
    "terminal/release", "{\"sessionId\":\"s\",\"terminalId\":\"t\"}",
  )
  assert_true(
    broker_decode_client_request_result(release, broker_codec_test_json("{}"))
    is AgentReplyTerminalRelease(_),
  )
  let elicitation = broker_codec_test_client_request(
    "elicitation/create", "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}",
  )
  assert_true(
    broker_decode_client_request_result(
      elicitation,
      broker_codec_test_json("{\"action\":\"accept\"}"),
    )
    is AgentReplyElicitationCreate(_),
  )
}

///|
test "broker decodes every Client-to-Agent reply by originating request" {
  let initialize = broker_codec_test_agent_request(
    "initialize", "{\"protocolVersion\":1}",
  )
  assert_true(
    broker_decode_agent_request_result(
      initialize,
      broker_codec_test_json("{\"protocolVersion\":1}"),
    )
    is ClientReplyInitialize(_),
  )
  let authenticate = broker_codec_test_agent_request(
    "authenticate", "{\"methodId\":\"token\"}",
  )
  assert_true(
    broker_decode_agent_request_result(
      authenticate,
      broker_codec_test_json("{}"),
    )
    is ClientReplyAuthenticate(_),
  )
  let logout = broker_codec_test_agent_request("logout", "{}")
  assert_true(
    broker_decode_agent_request_result(logout, broker_codec_test_json("{}"))
    is ClientReplyLogout(_),
  )
  let new_session = broker_codec_test_agent_request(
    "session/new", "{\"cwd\":\"/\",\"mcpServers\":[]}",
  )
  assert_true(
    broker_decode_agent_request_result(
      new_session,
      broker_codec_test_json("{\"sessionId\":\"s\"}"),
    )
    is ClientReplyNewSession(_),
  )
  let load = broker_codec_test_agent_request(
    "session/load", "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}",
  )
  assert_true(
    broker_decode_agent_request_result(load, broker_codec_test_json("{}"))
    is ClientReplyLoadSession(_),
  )
  let resumed = broker_codec_test_agent_request(
    "session/resume", "{\"sessionId\":\"s\",\"cwd\":\"/\"}",
  )
  assert_true(
    broker_decode_agent_request_result(resumed, broker_codec_test_json("{}"))
    is ClientReplyResumeSession(_),
  )
  let list = broker_codec_test_agent_request("session/list", "{}")
  assert_true(
    broker_decode_agent_request_result(
      list,
      broker_codec_test_json("{\"sessions\":[]}"),
    )
    is ClientReplyListSessions(_),
  )
  let delete = broker_codec_test_agent_request(
    "session/delete", "{\"sessionId\":\"s\"}",
  )
  assert_true(
    broker_decode_agent_request_result(delete, broker_codec_test_json("{}"))
    is ClientReplyDeleteSession(_),
  )
  let close = broker_codec_test_agent_request(
    "session/close", "{\"sessionId\":\"s\"}",
  )
  assert_true(
    broker_decode_agent_request_result(close, broker_codec_test_json("{}"))
    is ClientReplyCloseSession(_),
  )
  let mode = broker_codec_test_agent_request(
    "session/set_mode", "{\"sessionId\":\"s\",\"modeId\":\"code\"}",
  )
  assert_true(
    broker_decode_agent_request_result(mode, broker_codec_test_json("{}"))
    is ClientReplySetMode(_),
  )
  let config = broker_codec_test_agent_request(
    "session/set_config_option", "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}",
  )
  assert_true(
    broker_decode_agent_request_result(
      config,
      broker_codec_test_json("{\"configOptions\":[]}"),
    )
    is ClientReplySetConfigOption(_),
  )
  let prompt = broker_codec_test_agent_request(
    "session/prompt", "{\"sessionId\":\"s\",\"prompt\":[]}",
  )
  assert_true(
    broker_decode_agent_request_result(
      prompt,
      broker_codec_test_json("{\"stopReason\":\"end_turn\"}"),
    )
    is ClientReplyPrompt(_),
  )
}

///|
test "broker result failures preserve phase method and protocol cause" {
  let request = broker_codec_test_client_request(
    "fs/read_text_file", "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}",
  )
  try
    broker_decode_client_request_result(
      request,
      broker_codec_test_json("{\"content\":7}"),
    )
  catch {
    InvalidPayload(
      phase=Result,
      method_name="fs/read_text_file",
      cause=ExpectedString(path="fs/read_text_file.content")
    ) => ()
    _ => fail("expected typed result error with original cause")
  } noraise {
    _ => fail("expected malformed typed result to fail")
  }

  let initialize = broker_codec_test_agent_request(
    "initialize", "{\"protocolVersion\":1}",
  )
  try
    broker_decode_agent_request_result(
      initialize,
      broker_codec_test_json("{\"stopReason\":\"end_turn\"}"),
    )
  catch {
    InvalidPayload(
      phase=Result,
      method_name="initialize",
      cause=UnknownField(path="initialize.stopReason")
    ) => ()
    _ => fail("result decoder must be selected by request variant")
  } noraise {
    _ => fail("expected result mismatch to fail")
  }
}

///|
test "broker parameter failures preserve phase method and protocol cause" {
  let invalid : ClientRequest = FsReadTextFile({
    session_id: "s",
    path: "relative.txt",
    line: Omitted,
    limit: Omitted,
    meta: Omitted,
  })
  try broker_client_request_payload(invalid) catch {
    InvalidPayload(
      phase=Params,
      method_name="fs/read_text_file",
      cause=InvalidPath(path="path", value="relative.txt")
    ) => ()
    _ => fail("expected typed parameter error with original cause")
  } noraise {
    _ => fail("expected invalid typed parameter to fail")
  }
}
