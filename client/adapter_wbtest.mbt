///|
/// White-box tests for adapter error forwarding: handler-authored
/// messages must reach the wire verbatim (message + data), not a generic
/// "Internal error".

///|
test "handler errors forward their message and data onto the wire" {
  let application = client_adapter_handler_error(
    Application(message="client permission UI crashed"),
  )
  assert_eq(application.code.to_int(), -32603)
  assert_eq(application.message, "client permission UI crashed")
  assert_eq(
    application.data,
    Some(Json::string("client permission UI crashed")),
  )
  let invalid = client_adapter_handler_error(
    InvalidParams(message="session id must be a string"),
  )
  assert_eq(invalid.code.to_int(), -32602)
  assert_eq(invalid.message, "session id must be a string")
}

///|
async test "unexpected handler exceptions name themselves" {
  let outcome : Result[Unit, HandlerError] = client_adapter_call(() => {
    raise ProtocolDecodeError::InvalidField(
      path="test",
      reason="unexpected failure",
    )
  })
  match outcome {
    Err(Application(message~)) => {
      assert_true(message.contains("client handler failed:"))
      assert_true(message.length() > "client handler failed:".length())
    }
    _ => fail("unexpected exception must surface as a detailed Application")
  }
}
