///|
fn client_state_test_info(name : String) -> ExperimentalV2Implementation {
  { name, title: None, version: "1.0.0", meta: None, }
}

///|
fn client_state_test_marker() -> ExperimentalV2MarkerPayload {
  { meta: None, }
}

///|
fn client_state_test_capabilities(
  form : Bool,
  url : Bool,
) -> ExperimentalV2ClientCapabilities {
  {
    elicitation: if form || url {
      MarkerSupported({
        form: if form {
          MarkerSupported(client_state_test_marker())
        } else {
          MarkerUnsupported
        },
        url: if url {
          MarkerSupported(client_state_test_marker())
        } else {
          MarkerUnsupported
        },
        meta: None,
      })
    } else {
      MarkerUnsupported
    },
    meta: None,
  }
}

///|
fn client_state_test_initialize_result(
  protocol_version : Int,
) -> ExperimentalV2InitializeResult raise {
  experimental_v2_decode_initialize_result(
    experimental_v2_parse_json(
      "{\"protocolVersion\":\{protocol_version},\"info\":{\"name\":\"agent\",\"version\":\"1\"},\"capabilities\":{}}",
    ),
  )
}

///|
fn client_state_test_ready(
  capabilities : ExperimentalV2ClientCapabilities,
) -> ExperimentalV2ClientState raise {
  let state = experimental_v2_client_state_new(capabilities~)
  experimental_v2_client_reduce(
    state,
    InitializeResult(client_state_test_initialize_result(2)),
  ).state
}

///|
fn client_state_test_permission_request() -> ExperimentalV2ClientRequest raise {
  SessionRequestPermission(
    experimental_v2_decode_request_permission_request(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s\",\"title\":\"Run\",\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      ),
    ),
  )
}

///|
fn client_state_test_elicitation_request(
  source : String,
) -> ExperimentalV2ClientRequest raise {
  ElicitationCreate(
    experimental_v2_decode_elicitation_create_request(
      experimental_v2_parse_json(source),
    ),
  )
}

///|
fn client_state_test_update_notification() -> ExperimentalV2ClientNotification raise {
  SessionUpdate(
    experimental_v2_decode_update_session_notification(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"running\"}}",
      ),
    ),
  )
}

///|
fn client_state_test_complete_notification() -> ExperimentalV2ClientNotification raise {
  ElicitationComplete(
    experimental_v2_decode_complete_elicitation_notification(
      experimental_v2_parse_json("{\"elicitationId\":\"e\"}"),
    ),
  )
}

///|
fn client_state_test_error(
  state : ExperimentalV2ClientState,
  event : ExperimentalV2ClientEvent,
  expected : ExperimentalV2ClientProtocolError,
) -> Unit raise {
  let before = state
  try experimental_v2_client_reduce(state, event) catch {
    error => assert_eq(error, expected)
  } noraise {
    _ => fail("expected a typed rejection")
  }
  assert_eq(state, before)
}

///|
fn client_state_test_dispatched_request(
  state : ExperimentalV2ClientState,
  request : ExperimentalV2ClientRequest,
) -> Unit raise {
  let step = experimental_v2_client_reduce(state, AgentRequest(request))
  assert_eq(step.commands.length(), 1)
  match step.commands[0] {
    DispatchRequest(_) => ()
    _ => fail("expected the request to dispatch")
  }
}

///|
fn client_state_test_dispatched_notification(
  state : ExperimentalV2ClientState,
  notification : ExperimentalV2ClientNotification,
) -> Unit raise {
  let step = experimental_v2_client_reduce(
    state,
    AgentNotification(notification),
  )
  assert_eq(step.commands.length(), 1)
  match step.commands[0] {
    DispatchNotification(_) => ()
    _ => fail("expected the notification to dispatch")
  }
}

///|
fn client_state_test_denied(
  state : ExperimentalV2ClientState,
  request : ExperimentalV2ClientRequest,
  capability : String,
) -> Unit raise {
  try experimental_v2_client_reduce(state, AgentRequest(request)) catch {
    CapabilityDenied(method_name="elicitation/create", capability=actual) =>
      assert_eq(actual, capability)
    _ => fail("expected elicitation/create to deny " + capability)
  } noraise {
    _ => fail("expected elicitation/create to deny " + capability)
  }
}

///|
test "v2 client sends version two and readies on a version two result" {
  let capabilities = client_state_test_capabilities(false, false)
  let params = experimental_v2_client_initialize_params(
    info=client_state_test_info("client"),
    capabilities~,
  )
  assert_eq(params.protocol_version, 2)

  let state = experimental_v2_client_state_new(capabilities~)
  assert_eq(state.phase, ClientAwaitingInitialize)
  let ready = experimental_v2_client_reduce(
    state,
    InitializeResult(client_state_test_initialize_result(2)),
  )
  assert_eq(ready.state.phase, ClientReady)
  assert_true(ready.state.agent is Some({ protocol_version: 2, .. }))
  client_state_test_error(
    ready.state,
    InitializeResult(client_state_test_initialize_result(2)),
    AlreadyReady,
  )
}

///|
test "v2 client fails terminally on a mismatched negotiate result" {
  let state = experimental_v2_client_state_new(
    capabilities=client_state_test_capabilities(false, false),
  )
  let failed = experimental_v2_client_reduce(
    state,
    InitializeResult(client_state_test_initialize_result(1)),
  )
  assert_eq(failed.state.phase, ClientFailed(UnsupportedVersion(offered=1)))
  assert_eq(failed.commands.length(), 1)
  assert_true(failed.commands[0] is CloseConnection)

  // Terminal: no recovery through a second result and no traffic processing;
  // the original typed failure is re-raised.
  client_state_test_error(
    failed.state,
    InitializeResult(client_state_test_initialize_result(2)),
    UnsupportedVersion(offered=1),
  )
  client_state_test_error(
    failed.state,
    AgentNotification(client_state_test_update_notification()),
    UnsupportedVersion(offered=1),
  )
}

///|
test "v2 client gates inbound traffic on readiness" {
  let state = experimental_v2_client_state_new(
    capabilities=client_state_test_capabilities(true, true),
  )
  client_state_test_error(
    state,
    AgentRequest(client_state_test_permission_request()),
    NotReady(method_name="session/request_permission"),
  )
  client_state_test_error(
    state,
    AgentNotification(client_state_test_update_notification()),
    NotReady(method_name="session/update"),
  )
  client_state_test_error(
    state,
    AgentNotification(client_state_test_complete_notification()),
    NotReady(method_name="elicitation/complete"),
  )

  // Protocol-level cancellation is live before readiness.
  let step = experimental_v2_client_reduce(
    state,
    AgentNotification(CancelRequest(RequestIdNumber(3L))),
  )
  assert_true(step.commands[0] is CancelRequest(request_id=RequestIdNumber(3L)))
}

///|
test "v2 client accepts permission requests without a capability marker" {
  let state = client_state_test_ready(
    client_state_test_capabilities(false, false),
  )
  client_state_test_dispatched_request(
    state,
    client_state_test_permission_request(),
  )
}

///|
test "v2 client elicitation modes gate on their own markers" {
  let none = client_state_test_ready(
    client_state_test_capabilities(false, false),
  )
  let form = client_state_test_elicitation_request(
    "{\"mode\":\"form\",\"message\":\"m\",\"sessionId\":\"s\",\"requestedSchema\":{\"type\":\"object\"}}",
  )
  let url = client_state_test_elicitation_request(
    "{\"mode\":\"url\",\"message\":\"m\",\"sessionId\":\"s\",\"elicitationId\":\"e\",\"url\":\"https://example.test\"}",
  )
  client_state_test_denied(none, form, "elicitation.form")
  client_state_test_denied(none, url, "elicitation.url")

  let form_only = client_state_test_ready(
    client_state_test_capabilities(true, false),
  )
  client_state_test_dispatched_request(form_only, form)
  client_state_test_denied(form_only, url, "elicitation.url")

  let url_only = client_state_test_ready(
    client_state_test_capabilities(false, true),
  )
  client_state_test_dispatched_request(url_only, url)
  client_state_test_denied(url_only, form, "elicitation.form")

  let both = client_state_test_ready(client_state_test_capabilities(true, true))
  client_state_test_dispatched_request(both, form)
  client_state_test_dispatched_request(both, url)

  let extension = client_state_test_elicitation_request(
    "{\"mode\":\"_custom\",\"message\":\"m\",\"sessionId\":\"s\"}",
  )
  client_state_test_denied(both, extension, "elicitation._custom")
  let future = client_state_test_elicitation_request(
    "{\"mode\":\"external\",\"message\":\"m\",\"sessionId\":\"s\"}",
  )
  client_state_test_denied(both, future, "elicitation.external")
}

///|
test "v2 client updates and completions always dispatch once ready" {
  let state = client_state_test_ready(
    client_state_test_capabilities(false, false),
  )
  client_state_test_dispatched_notification(
    state,
    client_state_test_update_notification(),
  )
  client_state_test_dispatched_notification(
    state,
    client_state_test_complete_notification(),
  )
}

///|
test "v2 client rejects unknown agent methods typed" {
  let state = client_state_test_ready(
    client_state_test_capabilities(true, true),
  )
  client_state_test_error(
    state,
    UnknownAgentMethod(method_name="fs/read_text_file"),
    UnknownMethod(method_name="fs/read_text_file"),
  )
  client_state_test_error(
    state,
    UnknownAgentMethod(method_name="session/set_mode"),
    UnknownMethod(method_name="session/set_mode"),
  )
}
