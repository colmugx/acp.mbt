///|
/// SDK-scope acceptance tests for row B06 of
/// docs/implementation-plan/04-v1-completeness-matrix.md at the pure Client
/// protocol-state layer: the form/url elicitation gates treat an explicit
/// null mode marker exactly like an absent one, mirroring the explicit-false
/// policy rows B03/B04 use for boolean capabilities.  The `{}` empty outer
/// object, omitted, and null outer-object cases are proven in
/// client/protocol/state_test.mbt; the adapter-level half (service-derived
/// capabilities gating `elicitation/create` per mode and
/// `elicitation/complete` on the URL marker) is proven in
/// client/matrix_test.mbt row D10.

///|
test "matrix B06 explicit null mode markers deny their elicitation mode" {
  let both_null = client_protocol_state_ready(
    capabilities=Value(
      client_state_test_capabilities(Omitted, Omitted, Omitted, Null, Null),
    ),
  )
  let form = client_state_test_form_request()
  let url = client_state_test_url_request()
  let complete = client_state_test_complete_notification()
  try client_protocol_reduce(both_null, Request(form)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.form"
    ) => ()
    _ => fail("expected a null form marker to deny form elicitation")
  } noraise {
    _ => fail("expected form elicitation to be denied")
  }
  try client_protocol_reduce(both_null, Request(url)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected a null url marker to deny URL elicitation")
  } noraise {
    _ => fail("expected URL elicitation to be denied")
  }
  try client_protocol_reduce(both_null, Notification(complete)) catch {
    CapabilityDenied(
      method_name="elicitation/complete",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected a null url marker to deny completion")
  } noraise {
    _ => fail("expected completion to be denied")
  }

  // A null marker only denies its own mode: the sibling marker keeps
  // dispatching, so the two gates stay independently negotiable.
  let null_form_only = client_protocol_state_ready(
    capabilities=Value(
      client_state_test_capabilities(
        Omitted,
        Omitted,
        Omitted,
        Null,
        Value(client_state_test_marker()),
      ),
    ),
  )
  try client_protocol_reduce(null_form_only, Request(form)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.form"
    ) => ()
    _ => fail("expected a lone null form marker to deny form elicitation")
  } noraise {
    _ => fail("expected form elicitation to be denied")
  }
  assert_true(
    client_protocol_reduce(null_form_only, Request(url)).commands[0]
    is DispatchRequest(ElicitationCreate(Url(_))),
  )
  assert_true(
    client_protocol_reduce(null_form_only, Notification(complete)).commands[0]
    is DispatchNotification(ElicitationComplete(_)),
  )

  let null_url_only = client_protocol_state_ready(
    capabilities=Value(
      client_state_test_capabilities(
        Omitted,
        Omitted,
        Omitted,
        Value(client_state_test_marker()),
        Null,
      ),
    ),
  )
  assert_true(
    client_protocol_reduce(null_url_only, Request(form)).commands[0]
    is DispatchRequest(ElicitationCreate(Form(_))),
  )
  try client_protocol_reduce(null_url_only, Request(url)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected a lone null url marker to deny URL elicitation")
  } noraise {
    _ => fail("expected URL elicitation to be denied")
  }
  try client_protocol_reduce(null_url_only, Notification(complete)) catch {
    CapabilityDenied(
      method_name="elicitation/complete",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected a lone null url marker to deny completion")
  } noraise {
    _ => fail("expected completion to be denied")
  }

  // A null elicitation outer object denies both modes as well.
  let null_outer = client_protocol_state_ready(
    capabilities=Value({
      fs: Omitted,
      terminal: Omitted,
      elicitation: Null,
      session: Omitted,
      meta: Omitted,
    }),
  )
  try client_protocol_reduce(null_outer, Request(url)) catch {
    CapabilityDenied(
      method_name="elicitation/create",
      capability="elicitation.url"
    ) => ()
    _ => fail("expected a null elicitation object to deny URL elicitation")
  } noraise {
    _ => fail("expected URL elicitation to be denied")
  }
}
