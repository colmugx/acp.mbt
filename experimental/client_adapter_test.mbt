///|
fn experimental_v2_client_test_message(
  frame : String,
) -> @jsonrpc.JsonRpcMessage raise {
  try @jsonrpc.jsonrpc_decode(frame) catch {
    _ => fail("expected one decodable JSON-RPC frame")
  } noraise {
    message => message
  }
}

///|
fn experimental_v2_client_test_permission_frame(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"session\",\"title\":\"proceed?\",\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}}\n"
}

///|
fn experimental_v2_client_test_elicitation_frame(
  id : String,
  mode : String,
) -> String {
  let mode_payload = match mode {
    "url" => "\"elicitationId\":\"elicitation\",\"url\":\"https://example\""
    _ => "\"requestedSchema\":{\"type\":\"object\",\"properties\":{}}"
  }
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"elicitation/create\",\"params\":{\"message\":\"name?\",\"mode\":\"" +
  mode +
  "\",\"sessionId\":\"session\"," +
  mode_payload +
  "}}\n"
}

///|
fn experimental_v2_client_test_update_frame(update : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"session\",\"update\":" +
  update +
  "}}\n"
}

///|
fn experimental_v2_client_test_complete_frame() -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"elicitation/complete\",\"params\":{\"elicitationId\":\"elicitation\"}}\n"
}

///|
fn experimental_v2_client_test_cancel_frame(victim : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"" +
  victim +
  "\"}}\n"
}

///|
fn experimental_v2_client_test_success(
  step : ExperimentalV2ClientAdapterStep,
) -> (@jsonrpc.RequestId, Json) raise {
  match step.outputs {
    [Response(Success(success))] => (success.id, success.result)
    _ => fail("expected exactly one success response output")
  }
}

///|
fn experimental_v2_client_test_error_code(
  step : ExperimentalV2ClientAdapterStep,
) -> (@jsonrpc.JsonRpcId, @jsonrpc.JsonRpcErrorCode) raise {
  match step.outputs {
    [Response(Error(failure))] => (failure.id, failure.error.code)
    _ => fail("expected exactly one error response output")
  }
}

///|
test "v2 client adapter answers permission before initialize" {
  let endpoint = experimental_v2_client_test_endpoint([], [], [])
  let awaiting = experimental_v2_client_adapter_state_new(
    protocol=experimental_v2_client_state_new(
      capabilities=endpoint.capabilities(),
    ),
  )
  let admission = try! experimental_v2_client_adapter_admit(
    awaiting,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_permission_frame("early"),
    ),
  )
  match admission {
    Immediate(step) => {
      let (id, code) = experimental_v2_client_test_error_code(step)
      assert_eq(id, String("early"))
      assert_eq(code, InvalidRequest)
    }
    _ => fail("a pre-initialize permission request must be immediate")
  }
}

///|
async test "v2 client adapter settles a selected permission outcome" {
  let updates : Array[ExperimentalV2UpdateSessionNotification] = []
  let permissions : Array[ExperimentalV2RequestPermissionRequest] = []
  let endpoint = experimental_v2_client_test_endpoint(updates, permissions, [])
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let admission = try! experimental_v2_client_adapter_admit(
    state,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_permission_frame("perm"),
    ),
  )
  let invocation = match admission {
    Invoke(state~, invocation~) => {
      assert_eq(state.protocol.phase, ClientReady)
      invocation
    }
    _ => fail("a ready permission request must invoke the handler")
  }
  match invocation {
    RequestPermissionInvocation(id~, params~) => {
      assert_eq(id, String("perm"))
      assert_eq(params, experimental_v2_client_test_permission_request())
    }
    _ => fail("expected a typed permission invocation")
  }
  let completion = experimental_v2_client_execute(invocation, endpoint)
  let step = try! experimental_v2_client_adapter_complete(
    state, invocation, completion,
  )
  assert_eq(permissions.length(), 1)
  let (_, result) = experimental_v2_client_test_success(step)
  guard result is Object(fields) else { fail("expected an outcome object") }
  guard fields.get("outcome") is Some(Object(outcome)) else {
    fail("expected a permission outcome")
  }
  guard outcome.get("outcome") is Some(String("selected")) else {
    fail("expected a selected outcome")
  }
  guard outcome.get("optionId") is Some(String("allow")) else {
    fail("expected the selected option id")
  }
}

///|
test "v2 client adapter rejects an unoffered selected permission option" {
  let endpoint = experimental_v2_client_test_endpoint([], [], [])
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let invocation : ExperimentalV2ClientInvocation = RequestPermissionInvocation(
    id=String("perm"),
    params=experimental_v2_client_test_permission_request(),
  )
  let step = try! experimental_v2_client_adapter_complete(
    state,
    invocation,
    RequestPermissionCompleted(
      id=String("perm"),
      result=Ok({
        outcome: Known(OutcomeSelected({ option_id: "deny", meta: None })),
        meta: None,
      }),
    ),
  )
  let (_, code) = experimental_v2_client_test_error_code(step)
  assert_eq(code, InvalidParams)
}

///|
test "v2 client adapter settles a cancelled permission handler" {
  let endpoint = experimental_v2_client_test_endpoint([], [], [])
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let invocation : ExperimentalV2ClientInvocation = RequestPermissionInvocation(
    id=String("perm"),
    params=experimental_v2_client_test_permission_request(),
  )
  let step = try! experimental_v2_client_adapter_complete(
    state,
    invocation,
    RequestPermissionCompleted(id=String("perm"), result=Err(Cancelled)),
  )
  let (_, result) = experimental_v2_client_test_success(step)
  guard result is Object(fields) else { fail("expected an outcome object") }
  guard fields.get("outcome") is Some(Object(outcome)) else {
    fail("expected a permission outcome")
  }
  guard outcome.get("outcome") is Some(String("cancelled")) else {
    fail("expected a cancelled outcome")
  }
}

///|
async test "v2 client adapter dispatches form elicitation and gates url" {
  let form_replies : Array[String] = []
  let endpoint = experimental_v2_client_test_endpoint(
    [],
    [],
    form_replies,
    with_form=true,
  )
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let admission = try! experimental_v2_client_adapter_admit(
    state,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_elicitation_frame("form", "form"),
    ),
  )
  let invocation = match admission {
    Invoke(invocation~, ..) => invocation
    _ => fail("an advertised form elicitation must invoke the handler")
  }
  match invocation {
    ElicitationCreateInvocation(id~, params~) => {
      assert_eq(id, String("form"))
      assert_eq(params, experimental_v2_client_test_elicitation_form_request())
    }
    _ => fail("expected a typed elicitation invocation")
  }
  let completion = experimental_v2_client_execute(invocation, endpoint)
  let step = try! experimental_v2_client_adapter_complete(
    state, invocation, completion,
  )
  assert_eq(form_replies, ["name?"])
  let (_, result) = experimental_v2_client_test_success(step)
  guard result is Object(fields) else { fail("expected an action object") }
  guard fields.get("action") is Some(String("decline")) else {
    fail("expected a decline action")
  }
  // The url marker is absent, so a url-mode create is denied by capability
  // before any handler runs.
  let denied = try! experimental_v2_client_adapter_admit(
    state,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_elicitation_frame("url", "url"),
    ),
  )
  match denied {
    Immediate(step) => {
      let (_, code) = experimental_v2_client_test_error_code(step)
      assert_eq(code, ResourceNotFound)
    }
    _ => fail("an unadvertised url elicitation must be immediate")
  }
  // Extension modes are denied by capability with their tag named.
  let extension = try! experimental_v2_client_adapter_admit(
    state,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_elicitation_frame("ext", "_custom"),
    ),
  )
  match extension {
    Immediate(step) => {
      let (_, code) = experimental_v2_client_test_error_code(step)
      assert_eq(code, ResourceNotFound)
    }
    _ => fail("an extension-mode elicitation must be immediate")
  }
}

///|
async test "v2 client adapter streams notifications through the sinks" {
  let updates : Array[ExperimentalV2UpdateSessionNotification] = []
  let endpoint = experimental_v2_client_test_endpoint(updates, [], [])
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let update = experimental_v2_client_test_update_notification(
    Known(UpdateState(Known(StateRunning({ meta: None })))),
  )
  let admission = try! experimental_v2_client_adapter_admit(
    state,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_update_frame(
        "{\"sessionUpdate\":\"state_update\",\"state\":\"running\"}",
      ),
    ),
  )
  let invocation = match admission {
    Invoke(invocation~, ..) => invocation
    _ => fail("a ready session/update must invoke the sink")
  }
  match invocation {
    SessionUpdateInvocation(params~) => assert_eq(params, update)
    _ => fail("expected a typed session/update invocation")
  }
  let completion = experimental_v2_client_execute(invocation, endpoint)
  let step = try! experimental_v2_client_adapter_complete(
    state, invocation, completion,
  )
  assert_eq(step.outputs, [])
  assert_eq(step.state, state)
  assert_eq(updates, [update])
  // A failing sink produces one trace command and no response.
  let failing = try! experimental_v2_client_adapter_complete(
    state,
    invocation,
    SessionUpdateCompleted(result=Err(Application(message="sink failed"))),
  )
  assert_eq(failing.outputs, [
    Command(
      TraceError(
        method_name="session/update",
        error=@jsonrpc.JsonRpcError::new(
          code=InternalError,
          message="sink failed",
          data=Json::string("sink failed"),
        ),
      ),
    ),
  ])
  // elicitation/complete reaches its sink the same way.
  let complete_admission = try! experimental_v2_client_adapter_admit(
    experimental_v2_client_test_adapter_state(
      experimental_v2_client_test_endpoint([], [], [], with_complete=true),
    ),
    experimental_v2_client_test_endpoint([], [], [], with_complete=true),
    experimental_v2_client_test_message(
      experimental_v2_client_test_complete_frame(),
    ),
  )
  match complete_admission {
    Invoke(invocation~, ..) =>
      match invocation {
        ElicitationCompleteInvocation(params~) =>
          assert_eq(params.elicitation_id, "elicitation")
        _ => fail("expected a typed elicitation/complete invocation")
      }
    _ => fail("a ready elicitation/complete must invoke the sink")
  }
}

///|
test "v2 client adapter plans typed cancel for dollar-cancel-request" {
  let endpoint = experimental_v2_client_test_endpoint([], [], [])
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let admission = try! experimental_v2_client_adapter_admit(
    state,
    endpoint,
    experimental_v2_client_test_message(
      experimental_v2_client_test_cancel_frame("victim"),
    ),
  )
  match admission {
    Immediate(step) =>
      assert_eq(step.outputs, [
        Command(CancelRequest(request_id=RequestIdStr("victim"))),
      ])
    _ => fail("$/cancel_request must stay immediate")
  }
}

///|
test "v2 client adapter rejects late and mismatched completions" {
  let endpoint = experimental_v2_client_test_endpoint([], [], [])
  let state = experimental_v2_client_test_adapter_state(endpoint)
  let invocation : ExperimentalV2ClientInvocation = RequestPermissionInvocation(
    id=String("perm"),
    params=experimental_v2_client_test_permission_request(),
  )
  try
    experimental_v2_client_adapter_complete(
      state,
      invocation,
      RequestPermissionCompleted(
        id=String("other"),
        result=Ok(experimental_v2_client_test_selected_response()),
      ),
    )
  catch {
    LateCompletion(request_id~) => assert_eq(request_id, String("other"))
    _ => fail("expected a late completion failure")
  } noraise {
    _ => fail("expected a late completion failure")
  }
  try
    experimental_v2_client_adapter_complete(
      state,
      invocation,
      ElicitationCreateCompleted(
        id=String("perm"),
        result=Ok(experimental_v2_client_test_decline_response()),
      ),
    )
  catch {
    CompletionMismatch(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected a completion mismatch failure")
  } noraise {
    _ => fail("expected a completion mismatch failure")
  }
}

///|
test "v2 client adapter rejects drifted endpoint capabilities" {
  let endpoint = experimental_v2_client_test_endpoint([], [], [])
  let drifted = experimental_v2_client_adapter_state_new(
    protocol=experimental_v2_client_test_ready_state(
      capabilities=experimental_v2_client_test_capabilities(form=true),
    ),
  )
  try
    experimental_v2_client_adapter_admit(
      drifted,
      endpoint,
      experimental_v2_client_test_message(
        experimental_v2_client_test_permission_frame("perm"),
      ),
    )
  catch {
    ExperimentalV2ClientAdapterError::EndpointMismatch(reason~) =>
      assert_eq(reason, "state capabilities do not match endpoint")
    _ => fail("expected an endpoint mismatch failure")
  } noraise {
    _ => fail("expected an endpoint mismatch failure")
  }
}
