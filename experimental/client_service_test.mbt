///|
fn experimental_v2_client_test_info(
  name : String,
) -> ExperimentalV2Implementation {
  { name, title: None, version: "1", meta: None }
}

///|
fn experimental_v2_client_test_capabilities(
  form? : Bool = false,
  url? : Bool = false,
) -> ExperimentalV2ClientCapabilities {
  {
    elicitation: MarkerSupported({
      form: if form {
        MarkerSupported({ meta: None })
      } else {
        MarkerUnsupported
      },
      url: if url {
        MarkerSupported({ meta: None })
      } else {
        MarkerUnsupported
      },
      meta: None,
    }),
    meta: None,
  }
}

///|
/// One minimal agent advertisement for feeding the Client reducer's
/// `InitializeResult` event.
fn experimental_v2_client_test_initialize_result(
  version? : Int = experimental_v2_protocol_version,
) -> ExperimentalV2InitializeResult {
  {
    protocol_version: version,
    info: experimental_v2_client_test_info("agent"),
    capabilities: {
      session: MarkerSupported({
        prompt: MarkerUnsupported,
        mcp: MarkerUnsupported,
        delete: MarkerUnsupported,
        additional_directories: MarkerUnsupported,
        meta: None,
      }),
      auth: MarkerUnsupported,
      meta: None,
    },
    auth_methods: None,
    meta: None,
  }
}

///|
/// One Client protocol state that has already accepted the pinned
/// initialize result, the state every post-initialize admission needs.
fn experimental_v2_client_test_ready_state(
  capabilities? : ExperimentalV2ClientCapabilities = experimental_v2_client_test_capabilities(),
) -> ExperimentalV2ClientState {
  let step = try! experimental_v2_client_reduce(
    experimental_v2_client_state_new(capabilities~),
    InitializeResult(experimental_v2_client_test_initialize_result()),
  )
  step.state
}

///|
fn experimental_v2_client_test_permission_request() -> ExperimentalV2RequestPermissionRequest {
  {
    session_id: "session",
    title: "proceed?",
    description: None,
    subject: None,
    options: [
      {
        option_id: "allow",
        name: "Allow",
        kind: OptionKindAllowOnce,
        meta: None,
      },
    ],
    meta: None,
  }
}

///|
fn experimental_v2_client_test_selected_response() -> ExperimentalV2RequestPermissionResponse {
  {
    outcome: Known(OutcomeSelected({ option_id: "allow", meta: None })),
    meta: None,
  }
}

///|
fn experimental_v2_client_test_elicitation_form_request() -> ExperimentalV2ElicitationCreateRequest {
  Known({
    message: "name?",
    mode: ElicitationForm({
      requested_schema: {
        title: None,
        properties: Map([]),
        required: None,
        description: None,
        meta: None,
      },
      scope: ScopeSession({ session_id: "session", tool_call_id: None }),
    }),
    meta: None,
  })
}

///|
fn experimental_v2_client_test_decline_response() -> ExperimentalV2ElicitationCreateResponse {
  Known({ action: ActionDecline, meta: None })
}

///|
fn experimental_v2_client_test_update_notification(
  update : ExperimentalV2SessionUpdate,
) -> ExperimentalV2UpdateSessionNotification {
  { session_id: "session", update, meta: None }
}

///|
/// One v2 Client endpoint with the baseline session service and optional
/// elicitation handlers, all recording into caller-owned arrays so inbound
/// paths stay observable without real I/O.
#warnings("-unused_async")
fn experimental_v2_client_test_endpoint(
  updates : Array[ExperimentalV2UpdateSessionNotification],
  permissions : Array[ExperimentalV2RequestPermissionRequest],
  form_replies : Array[String],
  with_form? : Bool = false,
  with_url? : Bool = false,
  with_complete? : Bool = false,
) -> ExperimentalV2ClientEndpoint {
  let form : ExperimentalV2ClientElicitationFormHandler? = if with_form {
    Some(async fn(message, _mode) {
      form_replies.push(message)
      experimental_v2_client_test_decline_response()
    })
  } else {
    None
  }
  let url : ExperimentalV2ClientElicitationUrlHandler? = if with_url {
    Some(async fn(_message, _mode) {
      experimental_v2_client_test_decline_response()
    })
  } else {
    None
  }
  let complete : ExperimentalV2ClientElicitationCompleteHandler? = if with_complete {
    Some(async fn(_notification) { () })
  } else {
    None
  }
  let elicitation : ExperimentalV2ClientElicitationService? = match
    (form, url, complete) {
    (None, None, None) => None
    _ =>
      Some(
        try! experimental_v2_client_elicitation_service(form?, url?, complete?),
      )
  }
  let spec = try! experimental_v2_client_spec(
    info=experimental_v2_client_test_info("client"),
    session=experimental_v2_client_session_service(
      session_update=async fn(notification) {
        updates.push(notification)
        ()
      },
      request_permission=async fn(request) {
        permissions.push(request)
        experimental_v2_client_test_selected_response()
      },
    ),
    elicitation?,
  )
  experimental_v2_client_endpoint_from_spec(spec)
}

///|
fn experimental_v2_client_test_adapter_state(
  endpoint : ExperimentalV2ClientEndpoint,
) -> ExperimentalV2ClientAdapterState {
  experimental_v2_client_adapter_state_new(
    protocol=experimental_v2_client_test_ready_state(
      capabilities=endpoint.capabilities(),
    ),
  )
}

///|
test "v2 client spec rejects empty identity and freezes the baseline" {
  let session = experimental_v2_client_session_service(
    session_update=async fn(_notification) {
      @async.pause()
      ()
    },
    request_permission=async fn(_request) {
      @async.pause()
      experimental_v2_client_test_selected_response()
    },
  )
  try
    experimental_v2_client_spec(
      info={ name: "", title: None, version: "1", meta: None },
      session~,
    )
  catch {
    InvalidImplementation(reason~) =>
      assert_eq(reason, "client name must not be empty")
    _ => fail("expected an implementation composition failure")
  } noraise {
    _ => fail("an empty client name must fail composition")
  }
  try
    experimental_v2_client_spec(
      info={ name: "client", title: None, version: "", meta: None },
      session~,
    )
  catch {
    InvalidImplementation(reason~) =>
      assert_eq(reason, "client version must not be empty")
    _ => fail("expected an implementation composition failure")
  } noraise {
    _ => fail("an empty client version must fail composition")
  }
  let spec = try! experimental_v2_client_spec(
    info=experimental_v2_client_test_info("client"),
    session~,
  )
  let endpoint = experimental_v2_client_endpoint_from_spec(spec)
  assert_eq(endpoint.info(), experimental_v2_client_test_info("client"))
}

///|
test "v2 client elicitation service validates its handler shape" {
  try experimental_v2_client_elicitation_service() catch {
    MissingElicitationHandler => ()
    _ => fail("expected a missing-handler composition failure")
  } noraise {
    _ => fail("an elicitation service with no handler must fail composition")
  }
  try
    experimental_v2_client_elicitation_service(url=async fn(_message, _mode) {
      @async.pause()
      experimental_v2_client_test_decline_response()
    })
  catch {
    ElicitationUrlRequiresComplete(reason~) =>
      assert_eq(
        reason, "elicitation/url requires the elicitation/complete sink",
      )
    _ => fail("expected a url-without-complete composition failure")
  } noraise {
    _ => fail("url support without the completion sink must fail composition")
  }
  let complete_only = try! experimental_v2_client_elicitation_service(complete=async fn(
    _notification,
  ) {
    @async.pause()
    ()
  })
  let paired = try! experimental_v2_client_elicitation_service(
    url=async fn(_message, _mode) {
      @async.pause()
      experimental_v2_client_test_decline_response()
    },
    complete=async fn(_notification) {
      @async.pause()
      ()
    },
  )
  assert_true(complete_only.form_handler is None)
  assert_true(paired.url_handler is Some(_))
}

///|
test "v2 client endpoint derives elicitation markers from service presence" {
  let plain = experimental_v2_client_test_endpoint([], [], [])
  assert_true(plain.capabilities().elicitation is MarkerUnsupported)
  let form_only = experimental_v2_client_test_endpoint(
    [],
    [],
    [],
    with_form=true,
  )
  assert_true(
    form_only.capabilities().elicitation
    is MarkerSupported({ form: MarkerSupported(_), url: MarkerUnsupported, .. }),
  )
  let url_only = experimental_v2_client_test_endpoint(
    [],
    [],
    [],
    with_url=true,
    with_complete=true,
  )
  assert_true(
    url_only.capabilities().elicitation
    is MarkerSupported({ form: MarkerUnsupported, url: MarkerSupported(_), .. }),
  )
  // A completion-sink-only service advertises no create capability.
  let sink_only = experimental_v2_client_test_endpoint(
    [],
    [],
    [],
    with_complete=true,
  )
  assert_true(sink_only.capabilities().elicitation is MarkerUnsupported)
}
