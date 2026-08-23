///|
fn batch_frame_test_split_frames(
  split : ExperimentalV2WireFrameSplit,
) -> Array[String] raise {
  match split {
    SplitBatchFrames(frames~, ..) => frames
    _ => fail("expected a split batch frame result")
  }
}

///|
test "v2 wire split expands a valid batch into ordered object frames" {
  let frames = batch_frame_test_split_frames(
    experimental_v2_split_wire_frame(
      "[{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"},{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"r1\"}}]",
    ),
  )
  assert_eq(frames.length(), 2)
  assert_eq(
    frames[0],
    "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"}",
  )
  assert_eq(
    frames[1],
    "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"r1\"}}",
  )
  assert_true(
    experimental_v2_split_wire_frame(
      "[{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"}]",
    )
    is SplitBatchFrames(intact=true, ..),
  )
}

///|
test "v2 wire split accepts response entries because reply batches expand too" {
  let frames = batch_frame_test_split_frames(
    experimental_v2_split_wire_frame(
      "[{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null},{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}]",
    ),
  )
  assert_eq(frames.length(), 2)
  assert_eq(frames[0], "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}")
  assert_eq(
    frames[1],
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}",
  )
}

///|
test "v2 wire split returns lone objects and non-array values unchanged" {
  assert_true(
    experimental_v2_split_wire_frame(
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"m\"}",
    )
    is SplitLoneObject(value=Object(_)),
  )
  assert_true(
    experimental_v2_split_wire_frame("42")
    is SplitLoneObject(value=Number(_, ..)),
  )
}

///|
test "v2 wire split maps an empty array to one -32600 single reply" {
  assert_eq(
    experimental_v2_split_wire_frame("[]"),
    SplitSingleErrorReply(
      frame="{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}",
    ),
  )
}

///|
test "v2 wire split maps truncated batch json to one -32700 single reply" {
  assert_eq(
    experimental_v2_split_wire_frame("[{\"jsonrpc\""),
    SplitSingleErrorReply(
      frame="{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"Parse error\"}}",
    ),
  )
  // An unparseable frame is answered -32700 whatever it would have been.
  assert_true(
    experimental_v2_split_wire_frame("{not json") is SplitSingleErrorReply(_),
  )
}

///|
test "v2 wire split keeps invalid entries' -32600 replies in place" {
  let split = experimental_v2_split_wire_frame(
    "[1,{\"jsonrpc\":\"2.0\",\"id\":\"r\",\"method\":\"session/prompt\"},\"junk\"]",
  )
  let frames = batch_frame_test_split_frames(split)
  assert_eq(frames.length(), 3)
  assert_eq(
    frames[0],
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}",
  )
  assert_eq(
    frames[1],
    "{\"jsonrpc\":\"2.0\",\"id\":\"r\",\"method\":\"session/prompt\"}",
  )
  assert_eq(
    frames[2],
    "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}",
  )
  assert_true(split is SplitBatchFrames(intact=false, ..))
}

///|
test "v2 collect replies batches single response frames into one line" {
  let line = experimental_v2_collect_replies([
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}", "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}",
  ])
  assert_eq(
    line, "[{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null},{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}]",
  )
  assert_false(line.contains("\n"))
}

///|
test "v2 collect replies fails fast on empty and non-response frames" {
  try experimental_v2_collect_replies([]) catch {
    EmptyResponsesInput => ()
    _ => fail("expected EmptyResponsesInput")
  } noraise {
    _ => fail("expected EmptyResponsesInput")
  }
  try
    experimental_v2_collect_replies([
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session/list\"}",
    ])
  catch {
    ReplyFrameDecodeFailed(index=0, cause~) =>
      assert_true(cause is InvalidRequest(_))
    _ => fail("expected ReplyFrameDecodeFailed")
  } noraise {
    _ => fail("expected ReplyFrameDecodeFailed")
  }
  try experimental_v2_collect_replies(["{not json"]) catch {
    ReplyFrameDecodeFailed(index~, ..) => assert_eq(index, 0)
    _ => fail("expected ReplyFrameDecodeFailed")
  } noraise {
    _ => fail("expected ReplyFrameDecodeFailed")
  }
}
