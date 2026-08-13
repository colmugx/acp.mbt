///|
test "integer id boundaries are inclusive" {
  assert_eq(decode_integer(2147483647.0), 2147483647)
  assert_eq(decode_integer(-2147483648.0), -2147483648)
}

///|
test "integer id rejects fractions and values outside Int32" {
  for value in [1.5, 2147483648.0, -2147483649.0] {
    try decode_integer(value) catch {
      InvalidId(reason=_) => ()
      _ => fail("expected invalid id")
    } noraise {
      _ => fail("expected integer decoding to fail")
    }
  }
}

///|
test "error decoder accepts extensions and still requires code/message" {
  let unknown : Json = {
    "code": Json::number(-32603.0),
    "message": Json::string("Internal error"),
    "trace": Json::string("private"),
  }
  let decoded = decode_error(unknown)
  assert_eq(decoded.code, InternalError)
  assert_eq(decoded.message, "Internal error")
  let missing_message : Json = { "code": Json::number(-32603.0) }
  try decode_error(missing_message) catch {
    InvalidError(reason=_) => ()
    _ => fail("expected missing error message")
  } noraise {
    _ => fail("expected error decoding to fail")
  }
}
