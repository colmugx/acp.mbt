///|
fn batch_test_invalid(
  item : ExperimentalV2BatchItem,
) -> ExperimentalV2BatchInvalidItem raise {
  match item {
    InvalidItem(invalid) => invalid
    _ => fail("expected an invalid batch entry")
  }
}

///|
test "v2 batch decodes mixed request and notification entries" {
  let batch = experimental_v2_batch_decode(
    "[{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"},{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"r1\"}}]",
  )
  assert_eq(batch.length(), 2)
  assert_true(
    batch[0]
    is Request({ id: Number(7), method_name: "session/list", params: None, }),
  )
  assert_true(
    batch[1]
    is Notification(
      { method_name: "$/cancel_request", params: Some(Object(_)), }
    ),
  )
  assert_false(experimental_v2_batch_is_notification_only(batch))
}

///|
test "v2 batch decodes notification-only entries" {
  let batch = experimental_v2_batch_decode(
    "[{\"jsonrpc\":\"2.0\",\"method\":\"session/update\"},{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\"}]",
  )
  assert_true(experimental_v2_batch_is_notification_only(batch))
  assert_eq(experimental_v2_batch_request_ids(batch).length(), 0)
}

///|
test "v2 batch decode rejects non-array frames as not a batch" {
  try
    experimental_v2_batch_decode(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\"}",
    )
  catch {
    NotABatch(value~) => assert_true(value is Object(_))
    _ => fail("expected NotABatch for a lone object")
  } noraise {
    _ => fail("expected NotABatch for a lone object")
  }
  try experimental_v2_batch_decode("42") catch {
    NotABatch(value~) => assert_true(value is Number(_, ..))
    _ => fail("expected NotABatch for a scalar")
  } noraise {
    _ => fail("expected NotABatch for a scalar")
  }
}

///|
test "v2 batch decode maps an empty array to one -32600 id-null response" {
  try experimental_v2_batch_decode("[]") catch {
    EmptyBatch(response~) =>
      assert_eq(
        @jsonrpc.jsonrpc_encode(@jsonrpc.JsonRpcMessage::response(response)),
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}",
      )
    _ => fail("expected EmptyBatch")
  } noraise {
    _ => fail("expected EmptyBatch")
  }
}

///|
test "v2 batch decode maps invalid json to one -32700 id-null response" {
  try experimental_v2_batch_decode("[{\"jsonrpc\"") catch {
    BatchParseFailed(message~, response~) => {
      assert_true(message != "")
      assert_eq(
        @jsonrpc.jsonrpc_encode(@jsonrpc.JsonRpcMessage::response(response)),
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}",
      )
    }
    _ => fail("expected BatchParseFailed")
  } noraise {
    _ => fail("expected BatchParseFailed")
  }
}

///|
test "v2 batch tags invalid entries individually and keeps siblings" {
  let batch = experimental_v2_batch_decode(
    "[1,{\"jsonrpc\":\"2.0\",\"id\":\"r\",\"method\":\"session/prompt\"},\"junk\"]",
  )
  assert_eq(batch.length(), 3)
  let first = batch_test_invalid(batch[0])
  assert_true(
    first.cause is InvalidRequest(reason="JSON-RPC envelope must be an object"),
  )
  assert_true(batch[1] is Request({ id: String("r"), .. }))
  let last = batch_test_invalid(batch[2])
  assert_true(
    last.cause is InvalidRequest(reason="JSON-RPC envelope must be an object"),
  )
  assert_eq(
    experimental_v2_batch_responses_encode([first.response, last.response]),
    "[{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}},{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}]",
  )
  assert_eq(
    experimental_v2_batch_encode(batch),
    "[{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}},{\"jsonrpc\":\"2.0\",\"id\":\"r\",\"method\":\"session/prompt\"},{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}]",
  )
  assert_false(experimental_v2_batch_is_notification_only(batch))
}

///|
test "v2 batch maps a response entry to an invalid item" {
  let batch = experimental_v2_batch_decode(
    "[{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}]",
  )
  let invalid = batch_test_invalid(batch[0])
  assert_true(
    invalid.cause
    is InvalidRequest(reason="batch entries must be requests or notifications"),
  )
}

///|
test "v2 batch tolerates unknown envelope fields per jsonrpc rules" {
  let batch = experimental_v2_batch_decode(
    "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\",\"futureField\":true}]",
  )
  assert_true(batch[0] is Request({ method_name: "m", .. }))
}

///|
test "v2 batch encode round-trips decoded items as one line" {
  let source = "[{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"},{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"r1\"}}]"
  let encoded = experimental_v2_batch_encode(
    experimental_v2_batch_decode(source),
  )
  assert_eq(encoded, source)
  assert_false(encoded.contains("\n"))
}

///|
test "v2 batch request ids keep wire order" {
  let ids = experimental_v2_batch_request_ids(
    experimental_v2_batch_decode(
      "[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"a\"},{\"jsonrpc\":\"2.0\",\"method\":\"n\"},{\"jsonrpc\":\"2.0\",\"id\":\"two\",\"method\":\"b\"}]",
    ),
  )
  assert_eq(ids.length(), 2)
  assert_true(ids[0] is Number(1))
  assert_true(ids[1] is String("two"))
}

///|
test "v2 batch responses encode as one array line and empty inputs fail fast" {
  let responses : Array[@jsonrpc.JsonRpcResponse] = [
    @jsonrpc.JsonRpcResponse::success(id=Number(2), result=Json::null()),
    @jsonrpc.JsonRpcResponse::error(
      id=Number(1),
      error=@jsonrpc.JsonRpcError::method_not_found(),
    ),
  ]
  let encoded = experimental_v2_batch_responses_encode(responses)
  assert_eq(
    encoded, "[{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null},{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}]",
  )
  assert_false(encoded.contains("\n"))
  try experimental_v2_batch_responses_encode([]) catch {
    EmptyResponsesInput => ()
    _ => fail("expected EmptyResponsesInput")
  } noraise {
    _ => fail("expected EmptyResponsesInput")
  }
  try experimental_v2_batch_encode([]) catch {
    EmptyBatchInput => ()
    _ => fail("expected EmptyBatchInput")
  } noraise {
    _ => fail("expected EmptyBatchInput")
  }
}

///|
test "v1 jsonrpc_decode_json still rejects array input" {
  try @jsonrpc.jsonrpc_decode_json(Json::array([Json::null()])) catch {
    InvalidRequest(reason="JSON-RPC envelope must be an object") => ()
    _ => fail("expected the unchanged v1 array rejection")
  } noraise {
    _ => fail("expected the unchanged v1 array rejection")
  }
}
