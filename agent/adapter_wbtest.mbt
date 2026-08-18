///|
/// White-box tests for adapter error forwarding: handler-authored
/// messages must reach the wire verbatim (message + data), not a generic
/// "Internal error".

///|
test "handler errors forward their message and data onto the wire" {
  let application = agent_adapter_handler_error(
    Application(message="agent exploded while summarizing"),
  )
  assert_eq(application.code.to_int(), -32603)
  assert_eq(application.message, "agent exploded while summarizing")
  assert_eq(
    application.data,
    Some(Json::string("agent exploded while summarizing")),
  )
  let invalid = agent_adapter_handler_error(
    InvalidParams(message="unknown model slot: test/missing"),
  )
  assert_eq(invalid.code.to_int(), -32602)
  assert_eq(invalid.message, "unknown model slot: test/missing")
  assert_eq(
    invalid.data,
    Some(Json::string("unknown model slot: test/missing")),
  )
  let unavailable = agent_adapter_handler_error(
    UnavailableOperation(method_name="session/load"),
  )
  assert_eq(unavailable.code.to_int(), -32002)
  assert_true(unavailable.message.contains("session/load"))
  assert_true(unavailable.data is Some(_))
  // Cancellation stays the payload-free standard shape.
  let cancelled = agent_adapter_handler_error(Cancelled)
  assert_eq(cancelled.code.to_int(), -32800)
  assert_eq(cancelled.message, "Request cancelled")
}

///|
test "protocol errors forward their payload as the wire message" {
  let not_initialized = agent_adapter_protocol_error(
    NotInitialized(method_name="session/new"),
  )
  assert_eq(not_initialized.code.to_int(), -32600)
  assert_true(not_initialized.message.contains("session/new"))
  let denied = agent_adapter_protocol_error(
    CapabilityDenied(method_name="fs/read_text_file", capability="fs_ro"),
  )
  assert_eq(denied.code.to_int(), -32002)
  assert_true(denied.message.contains("fs_ro"))
}
