///|
test "request with string id and structured params round trips" {
  let message = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":\"req-1\",\"method\":\"initialize\",\"params\":{\"version\":1}}",
  )
  match message {
    Request(request) => {
      assert_eq(request.id, String("req-1"))
      assert_eq(request.method_name, "initialize")
      assert_true(request.params is Some(Object(_)))
    }
    _ => fail("expected a request")
  }
  assert_eq(
    jsonrpc_encode(message),
    "{\"jsonrpc\":\"2.0\",\"id\":\"req-1\",\"method\":\"initialize\",\"params\":{\"version\":1}}",
  )
}

///|
test "notification has no id and never becomes a request" {
  let message = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\"}",
  )
  match message {
    Notification(notification) => {
      assert_eq(notification.method_name, "$/cancel_request")
      assert_eq(notification.params, None)
    }
    _ => fail("expected a notification")
  }
  assert_eq(
    jsonrpc_encode(message),
    "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\"}",
  )
}

///|
test "integer and null request ids remain distinct from notifications" {
  let integer = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":2147483647,\"method\":\"m\"}",
  )
  match integer {
    Request(request) => assert_eq(request.id, Number(2147483647))
    _ => fail("expected integer-id request")
  }
  assert_eq(
    jsonrpc_encode(integer),
    "{\"jsonrpc\":\"2.0\",\"id\":2147483647,\"method\":\"m\"}",
  )
  let null_request = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"m\"}",
  )
  match null_request {
    Request(request) => assert_eq(request.id, Null)
    _ => fail("expected null-id request")
  }
  assert_eq(
    jsonrpc_encode(null_request),
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"m\"}",
  )
  let null_response = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}",
  )
  match null_response {
    Response(Error(failure)) => {
      assert_eq(failure.id, Null)
      assert_eq(failure.error.code, InvalidRequest)
    }
    _ => fail("expected a null-id response")
  }
  assert_eq(
    jsonrpc_encode(null_response),
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}",
  )
}

///|
test "request ids preserve exact signed int64 boundaries and large values" {
  let max_source = "{\"jsonrpc\":\"2.0\",\"id\":9223372036854775807,\"method\":\"m\"}"
  let parsed_max = @json.parse(max_source)
  match parsed_max {
    Object(fields) =>
      match fields["id"] {
        Number(_, repr~) => assert_eq(repr, Some("9223372036854775807"))
        _ => fail("expected parsed maximum int64 number")
      }
    _ => fail("expected parsed maximum int64 object")
  }
  let max_message = jsonrpc_decode(max_source)
  match max_message {
    Request(request) => assert_eq(request.id, Number(9223372036854775807L))
    _ => fail("expected maximum int64 request id")
  }
  assert_eq(jsonrpc_encode(max_message), max_source)

  let min_source = "{\"jsonrpc\":\"2.0\",\"id\":-9223372036854775808,\"method\":\"m\"}"
  let min_message = jsonrpc_decode(min_source)
  match min_message {
    Request(request) => assert_eq(request.id, Number(-9223372036854775808L))
    _ => fail("expected minimum int64 request id")
  }
  assert_eq(jsonrpc_encode(min_message), min_source)

  let large_source = "{\"jsonrpc\":\"2.0\",\"id\":9007199254740993,\"method\":\"m\"}"
  let large_message = jsonrpc_decode(large_source)
  match large_message {
    Request(request) => assert_eq(request.id, Number(9007199254740993L))
    _ => fail("expected exact request id above the binary-safe range")
  }
  assert_eq(jsonrpc_encode(large_message), large_source)

  let response = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":9007199254740993,\"result\":null}",
  )
  match response {
    Response(Success(success)) =>
      assert_eq(success.id, Number(9007199254740993L))
    _ => fail("expected exact large response id")
  }
}

///|
test "integer-valued decimal and exponent ids are exact, fractions fail" {
  let positive_exponent = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":1e+3,\"method\":\"m\"}",
  )
  match positive_exponent {
    Request(request) => assert_eq(request.id, Number(1000L))
    _ => fail("expected positive exponent request id")
  }

  let negative_exponent = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":1000e-3,\"method\":\"m\"}",
  )
  match negative_exponent {
    Request(request) => assert_eq(request.id, Number(1L))
    _ => fail("expected negative exponent request id")
  }

  let decimal = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":-1.0,\"method\":\"m\"}",
  )
  match decimal {
    Request(request) => assert_eq(request.id, Number(-1L))
    _ => fail("expected integer-valued decimal request id")
  }

  for
    source in [
      "{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"m\"}", "{\"jsonrpc\":\"2.0\",\"id\":1e-3,\"method\":\"m\"}",
      "{\"jsonrpc\":\"2.0\",\"id\":9223372036854775808,\"method\":\"m\"}", "{\"jsonrpc\":\"2.0\",\"id\":-9223372036854775809,\"method\":\"m\"}",
    ] {
    try jsonrpc_decode(source) catch {
      InvalidId(reason=_) => ()
      _ => fail("expected invalid int64 request id")
    } noraise {
      _ => fail("expected invalid int64 request id to fail")
    }
  }
}

///|
test "public int64 decoder rejects malformed number representations" {
  for
    repr in [
      "", "1e", "1e+", "1e-", "+1", "01", "1.", ".1", "--1", "NaN", "Infinity",
    ] {
    try jsonrpc_decode_int64(1.0, Some(repr), path="id") catch {
      InvalidInteger(path="id", reason="must be a valid JSON number") => ()
      _ => fail("expected malformed JSON number representation to be rejected")
    } noraise {
      _ => fail("expected malformed JSON number representation to fail")
    }
  }
}

///|
test "public int64 decoder keeps exact valid representations" {
  assert_eq(
    jsonrpc_decode_int64(0.0, Some("9223372036854775807"), path="id"),
    9223372036854775807L,
  )
  assert_eq(
    jsonrpc_decode_int64(0.0, Some("-9223372036854775808"), path="id"),
    -9223372036854775808L,
  )
  assert_eq(
    jsonrpc_decode_int64(0.0, Some("9007199254740993"), path="id"),
    9007199254740993L,
  )
  assert_eq(jsonrpc_decode_int64(0.0, Some("1e+3"), path="id"), 1000L)
  assert_eq(jsonrpc_decode_int64(0.0, Some("1000e-3"), path="id"), 1L)
  assert_eq(jsonrpc_decode_int64(0.0, Some("-1.0"), path="id"), -1L)
  try jsonrpc_decode_int64(0.0, Some("1e-3"), path="id") catch {
    InvalidInteger(path="id", reason="must be an integer") => ()
    _ => fail("expected fractional exponent to be rejected")
  } noraise {
    _ => fail("expected fractional exponent to fail")
  }
}

///|
test "success response contains result and round trips null result" {
  let message = jsonrpc_decode("{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":null}")
  match message {
    Response(Success(success)) => {
      assert_eq(success.id, Number(7))
      assert_eq(success.result, Json::null())
    }
    _ => fail("expected a success response")
  }
  assert_eq(
    jsonrpc_encode(message),
    "{\"jsonrpc\":\"2.0\",\"id\":7,\"result\":null}",
  )
  let null_id = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":null}",
  )
  match null_id {
    Response(Success(success)) => assert_eq(success.id, Null)
    _ => fail("expected a null-id success response")
  }
  assert_eq(
    jsonrpc_encode(null_id),
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"result\":null}",
  )
}

///|
test "error response preserves standard code and data" {
  let message = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":\"x\",\"error\":{\"code\":-32002,\"message\":\"Resource not found\",\"data\":{\"path\":\"/tmp/x\"}}}",
  )
  match message {
    Response(Error(failure)) => {
      assert_eq(failure.id, String("x"))
      assert_eq(failure.error.code, ResourceNotFound)
      assert_eq(failure.error.message, "Resource not found")
      assert_true(failure.error.data is Some(Object(_)))
    }
    _ => fail("expected an error response")
  }
  assert_eq(
    jsonrpc_encode(message),
    "{\"jsonrpc\":\"2.0\",\"id\":\"x\",\"error\":{\"code\":-32002,\"message\":\"Resource not found\",\"data\":{\"path\":\"/tmp/x\"}}}",
  )
}

///|
test "all standard error codes map to their wire integers" {
  assert_eq(JsonRpcErrorCode::ParseError.to_int(), -32700)
  assert_eq(JsonRpcErrorCode::InvalidRequest.to_int(), -32600)
  assert_eq(JsonRpcErrorCode::MethodNotFound.to_int(), -32601)
  assert_eq(JsonRpcErrorCode::InvalidParams.to_int(), -32602)
  assert_eq(JsonRpcErrorCode::InternalError.to_int(), -32603)
  assert_eq(JsonRpcErrorCode::RequestCancelled.to_int(), -32800)
  assert_eq(JsonRpcErrorCode::AuthRequired.to_int(), -32000)
  assert_eq(JsonRpcErrorCode::ResourceNotFound.to_int(), -32002)
  assert_eq(JsonRpcErrorCode::from_int(-32601), MethodNotFound)
  assert_eq(JsonRpcErrorCode::from_int(1234), Custom(1234))
}

///|
test "standard error constructors produce structured wire errors" {
  let errors = [
    JsonRpcError::parse_error(),
    JsonRpcError::invalid_request(),
    JsonRpcError::method_not_found(),
    JsonRpcError::invalid_params(),
    JsonRpcError::internal_error(),
    JsonRpcError::request_cancelled(),
    JsonRpcError::auth_required(),
    JsonRpcError::resource_not_found(),
  ]
  let codes = [-32700, -32600, -32601, -32602, -32603, -32800, -32000, -32002]
  for i, error in errors {
    assert_eq(error.code.to_int(), codes[i])
    assert_eq(error.data, None)
  }
}

///|
test "custom error data round trips without interpretation" {
  let error = JsonRpcError::new(
    code=Custom(-32077),
    message="custom failure",
    data=Json::array([Json::string("a"), Json::boolean(true)]),
  )
  let response = JsonRpcResponse::error(id=Number(3), error~)
  let message = JsonRpcMessage::response(response)
  let encoded = jsonrpc_encode(message)
  assert_eq(
    encoded, "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32077,\"message\":\"custom failure\",\"data\":[\"a\",true]}}",
  )
  let decoded = jsonrpc_decode(encoded)
  assert_eq(decoded, message)
}

///|
test "parse errors are explicit" {
  try jsonrpc_decode("{\"jsonrpc\":") catch {
    ParseError(message=_) => ()
    _ => fail("expected parse error")
  } noraise {
    _ => fail("expected decoding to fail")
  }
}

///|
test "invalid jsonrpc version is rejected" {
  try jsonrpc_decode("{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"m\"}") catch {
    InvalidField(path="jsonrpc", reason=_) => ()
    _ => fail("expected invalid jsonrpc field")
  } noraise {
    _ => fail("expected decoding to fail")
  }
}

///|
test "unknown envelope fields are accepted and not given ACP meaning" {
  let request = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\",\"extra\":true}",
  )
  assert_true(request is Request(_))
  assert_eq(
    jsonrpc_encode(request),
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\"}",
  )
  let notification = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"method\":\"m\",\"extra\":true}",
  )
  assert_true(notification is Notification(_))
  assert_eq(
    jsonrpc_encode(notification),
    "{\"jsonrpc\":\"2.0\",\"method\":\"m\"}",
  )
  let success = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null,\"extra\":true}",
  )
  assert_true(success is Response(Success(_)))
  assert_eq(
    jsonrpc_encode(success),
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}",
  )
  let error = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\",\"trace\":\"private\"},\"extra\":true}",
  )
  assert_true(error is Response(Error(_)))
  assert_eq(
    jsonrpc_encode(error),
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}",
  )
}

///|
test "response result and error are mutually exclusive" {
  try
    jsonrpc_decode(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null,\"error\":{\"code\":-32603,\"message\":\"Internal error\"}}",
    )
  catch {
    ConflictingFields(path="result,error") => ()
    _ => fail("expected conflicting response fields")
  } noraise {
    _ => fail("expected decoding to fail")
  }
}

///|
test "null params stay at the envelope and scalar params are rejected" {
  let null_params = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\",\"params\":null}",
  )
  match null_params {
    Request(request) => assert_eq(request.params, Some(Json::null()))
    _ => fail("expected request with explicit null params")
  }
  try
    jsonrpc_decode(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\",\"params\":true}",
    )
  catch {
    InvalidParams(reason=_) => ()
    _ => fail("expected scalar params to fail at the envelope")
  } noraise {
    _ => fail("expected scalar params decoding to fail")
  }
  try
    jsonrpc_decode("{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"m\"}")
  catch {
    InvalidId(reason=_) => ()
    _ => fail("expected invalid id")
  } noraise {
    _ => fail("expected decoding to fail")
  }
  let large_id = jsonrpc_decode(
    "{\"jsonrpc\":\"2.0\",\"id\":2147483648,\"method\":\"m\"}",
  )
  match large_id {
    Request(request) => assert_eq(request.id, Number(2147483648L))
    _ => fail("expected int64 request id")
  }
}

///|
test "constructors reject scalar params values" {
  let null_request = JsonRpcRequest::new(
    id=Null,
    method_name="m",
    params=Json::null(),
  )
  assert_eq(null_request.params, Some(Json::null()))
  try
    JsonRpcRequest::new(
      id=Number(1),
      method_name="m",
      params=Json::string("not structured"),
    )
  catch {
    InvalidParams(reason=_) => ()
    _ => fail("expected request constructor to reject scalar params")
  } noraise {
    _ => fail("expected request construction to fail")
  }
  try
    JsonRpcNotification::new(method_name="m", params=Json::boolean(true))
  catch {
    InvalidParams(reason=_) => ()
    _ => fail("expected notification constructor to reject scalar params")
  } noraise {
    _ => fail("expected notification construction to fail")
  }
}

///|
test "error decoder rejects non-int32 codes" {
  try
    jsonrpc_decode(
      "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":2147483648,\"message\":\"invalid\"}}",
    )
  catch {
    InvalidError(reason=_) => ()
    _ => fail("expected non-int32 error code to be rejected")
  } noraise {
    _ => fail("expected decoding to fail")
  }
}

///|
test "ACP single-frame profile rejects JSON-RPC batches" {
  try jsonrpc_decode("[]") catch {
    InvalidRequest(reason=_) => ()
    _ => fail("expected batch frame rejection")
  } noraise {
    _ => fail("expected batch frame to be rejected")
  }
}
