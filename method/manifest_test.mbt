///|
using @protocol {protocol_parse_json}

///|
using @agent_message {decode_agent_request, decode_agent_notification}

///|
using @client_message {decode_client_request, decode_client_notification}

///|
fn manifest_method_names(methods : Array[AcpV1Method]) -> Array[String] {
  let names : Array[String] = []
  for entry in methods {
    names.push(entry.method_name)
  }
  names
}

///|
fn manifest_has_name(methods : Array[AcpV1Method], wanted : String) -> Bool {
  for entry in methods {
    if entry.method_name == wanted {
      return true
    }
  }
  false
}

///|
fn manifest_test_params(method_name : String) -> Json {
  let source = match method_name {
    "initialize" => "{\"protocolVersion\":1}"
    "authenticate" => "{\"methodId\":\"token\"}"
    "logout" => "{}"
    "session/new" => "{\"cwd\":\"/\",\"mcpServers\":[]}"
    "session/load" => "{\"mcpServers\":[],\"cwd\":\"/\",\"sessionId\":\"s\"}"
    "session/resume" => "{\"sessionId\":\"s\",\"cwd\":\"/\"}"
    "session/list" => "{}"
    "session/delete" => "{\"sessionId\":\"s\"}"
    "session/close" => "{\"sessionId\":\"s\"}"
    "session/set_mode" => "{\"sessionId\":\"s\",\"modeId\":\"code\"}"
    "session/set_config_option" =>
      "{\"sessionId\":\"s\",\"configId\":\"confirm\",\"type\":\"boolean\",\"value\":true}"
    "session/prompt" => "{\"sessionId\":\"s\",\"prompt\":[]}"
    "session/cancel" => "{\"sessionId\":\"s\"}"
    "session/request_permission" =>
      "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"call\"},\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}"
    "fs/read_text_file" => "{\"sessionId\":\"s\",\"path\":\"/tmp/a\"}"
    "fs/write_text_file" =>
      "{\"sessionId\":\"s\",\"path\":\"/tmp/a\",\"content\":\"body\"}"
    "terminal/create" => "{\"sessionId\":\"s\",\"command\":\"echo\"}"
    "terminal/output" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "terminal/wait_for_exit" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "terminal/kill" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "terminal/release" => "{\"sessionId\":\"s\",\"terminalId\":\"t\"}"
    "elicitation/create" =>
      "{\"mode\":\"form\",\"message\":\"Choose\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}},\"requestId\":1}"
    "session/update" =>
      "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"current_mode_update\",\"currentModeId\":\"code\"}}"
    "elicitation/complete" => "{\"elicitationId\":\"e\"}"
    "$/cancel_request" => "{\"requestId\":1}"
    _ => abort("missing stable manifest fixture for " + method_name)
  }
  protocol_parse_json(source) catch {
    _ => abort("invalid stable manifest fixture for " + method_name)
  }
}

///|
test "stable v1 manifest has the exact fixed method names" {
  let methods = acp_v1_method_manifest()
  assert_eq(manifest_method_names(methods), [
    "initialize", "authenticate", "logout", "session/new", "session/load", "session/resume",
    "session/list", "session/delete", "session/close", "session/set_mode", "session/set_config_option",
    "session/prompt", "session/cancel", "session/request_permission", "fs/read_text_file",
    "fs/write_text_file", "terminal/create", "terminal/output", "terminal/wait_for_exit",
    "terminal/kill", "terminal/release", "elicitation/create", "session/update",
    "elicitation/complete", "$/cancel_request",
  ])
}

///|
test "stable v1 manifest records request and notification directions" {
  let methods = acp_v1_method_manifest()
  let mut client_requests = 0
  let mut client_notifications = 0
  let mut agent_requests = 0
  let mut agent_notifications = 0
  let mut bidirectional_notifications = 0
  for entry in methods {
    match (entry.direction, entry.kind) {
      (ClientToAgent, Request) => client_requests += 1
      (ClientToAgent, Notification) => client_notifications += 1
      (AgentToClient, Request) => agent_requests += 1
      (AgentToClient, Notification) => agent_notifications += 1
      (Bidirectional, Notification) => bidirectional_notifications += 1
      _ =>
        fail("manifest contains an impossible request/notification direction")
    }
  }
  assert_eq(client_requests, 12)
  assert_eq(client_notifications, 1)
  assert_eq(agent_requests, 9)
  assert_eq(agent_notifications, 2)
  assert_eq(bidirectional_notifications, 1)
}

///|
test "unstable and v2 overlay names are outside the stable manifest" {
  let methods = acp_v1_method_manifest()
  // Exact-set equality above is the exclusion proof for every name absent from
  // the pinned v1 stable table.  Keep the named v2-only overlay checks here as
  // readable regression guards for the most likely version mix-ups.
  assert_false(manifest_has_name(methods, "auth/login"))
  assert_false(manifest_has_name(methods, "auth/logout"))
}

///|
test "manifest calls return independent arrays" {
  let first = acp_v1_method_manifest()
  let second = acp_v1_method_manifest()
  first.push({
    method_name: "test-only",
    direction: ClientToAgent,
    kind: Request,
  })
  assert_eq(first.length(), second.length() + 1)
  assert_true(manifest_has_name(second, "$/cancel_request"))
}

///|
test "stable manifest cross-checks every direction and kind with closed unions" {
  let methods = acp_v1_method_manifest()
  let mut agent_requests = 0
  let mut agent_notifications = 0
  let mut client_requests = 0
  let mut client_notifications = 0
  let mut bidirectional_notifications = 0
  for entry in methods {
    let params = Some(manifest_test_params(entry.method_name))
    match (entry.direction, entry.kind) {
      (ClientToAgent, Request) => {
        let value = decode_agent_request(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        agent_requests += 1
      }
      (ClientToAgent, Notification) => {
        let value = decode_agent_notification(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        agent_notifications += 1
      }
      (AgentToClient, Request) => {
        let value = decode_client_request(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        client_requests += 1
      }
      (AgentToClient, Notification) => {
        let value = decode_client_notification(entry.method_name, params)
        assert_eq(value.method_name(), entry.method_name)
        client_notifications += 1
      }
      (Bidirectional, Notification) => {
        let agent_value = decode_agent_notification(entry.method_name, params)
        let client_value = decode_client_notification(entry.method_name, params)
        assert_eq(agent_value.method_name(), entry.method_name)
        assert_eq(client_value.method_name(), entry.method_name)
        bidirectional_notifications += 1
      }
      _ => fail("manifest direction/kind combination is not supported")
    }
  }
  assert_eq(agent_requests, 12)
  assert_eq(agent_notifications, 1)
  assert_eq(client_requests, 9)
  assert_eq(client_notifications, 2)
  assert_eq(bidirectional_notifications, 1)
}
