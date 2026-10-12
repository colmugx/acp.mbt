///|
fn tool_test_omitted_json() -> @protocol.ProtocolNullable[Json] {
  Omitted
}

///|
fn tool_test_content() -> @protocol.Content {
  {
    content: Text({
      annotations: Omitted,
      text: "tool output",
      meta: tool_test_omitted_json(),
    }),
    meta: tool_test_omitted_json(),
  }
}

///|
fn tool_test_location() -> @protocol.ToolCallLocation {
  { path: "/tmp/acp.txt", line: Value(1), meta: tool_test_omitted_json(), }
}

///|
fn tool_test_diff() -> @protocol.Diff {
  {
    path: "/tmp/acp.txt",
    old_text: Value("before"),
    new_text: "after",
    meta: tool_test_omitted_json(),
  }
}

///|
fn tool_test_call(kind : @protocol.ToolKind) -> @protocol.ToolCall {
  {
    tool_call_id: "call-1",
    title: "Read file",
    kind: Value(kind),
    status: Value(Pending),
    content: Value([
      Content(tool_test_content()),
      Diff(tool_test_diff()),
      Terminal({ terminal_id: "term-1", meta: tool_test_omitted_json(), }),
    ]),
    locations: Value([tool_test_location()]),
    raw_input: Value({ "path": Json::string("/tmp/acp.txt") }),
    raw_output: Null,
    meta: tool_test_omitted_json(),
  }
}

///|
test "tool call content and all tool kinds round trip" {
  let base : @protocol.ToolCall = tool_test_call(Read)
  assert_eq(
    @protocol.tool_call_from_json(@protocol.tool_call_to_json(base)),
    base,
  )
  let kinds : Array[@protocol.ToolKind] = [
    Read,
    Edit,
    Delete,
    Move,
    Search,
    Execute,
    Think,
    Fetch,
    SwitchMode,
    Other,
  ]
  for kind in kinds {
    let value = tool_test_call(kind)
    assert_eq(
      @protocol.tool_call_from_json(@protocol.tool_call_to_json(value)),
      value,
    )
  }
  let statuses : Array[@protocol.ToolCallStatus] = [
    Pending,
    InProgress,
    Completed,
    Failed,
  ]
  for status in statuses {
    let value : @protocol.ToolCallUpdate = {
      tool_call_id: "call-1",
      kind: Omitted,
      status: Value(status),
      title: Omitted,
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Omitted,
      meta: Omitted,
    }
    assert_eq(
      @protocol.tool_call_update_from_json(
        @protocol.tool_call_update_to_json(value),
      ),
      value,
    )
  }
}

///|
test "tool update preserves omitted and null patch fields" {
  let update : @protocol.ToolCallUpdate = {
    tool_call_id: "call-1",
    kind: Null,
    status: Null,
    title: Null,
    content: Null,
    locations: Null,
    raw_input: Null,
    raw_output: Null,
    meta: Null,
  }
  assert_eq(
    @protocol.tool_call_update_from_json(
      @protocol.tool_call_update_to_json(update),
    ),
    update,
  )
  let omitted : @protocol.ToolCallUpdate = {
    tool_call_id: "call-1",
    kind: Omitted,
    status: Omitted,
    title: Omitted,
    content: Omitted,
    locations: Omitted,
    raw_input: Omitted,
    raw_output: Omitted,
    meta: Omitted,
  }
  assert_eq(
    @protocol.tool_call_update_from_json(
      @protocol.tool_call_update_to_json(omitted),
    ),
    omitted,
  )
}

///|
test "tool locations and diffs enforce absolute paths and one-based lines" {
  let location = tool_test_location()
  assert_eq(
    @protocol.tool_call_location_from_json(
      @protocol.tool_call_location_to_json(location),
    ),
    location,
  )
  let diff : @protocol.Diff = {
    path: "/tmp/acp.txt",
    old_text: Null,
    new_text: "after",
    meta: tool_test_omitted_json(),
  }
  assert_eq(@protocol.diff_from_json(@protocol.diff_to_json(diff)), diff)
  try
    @protocol.tool_call_location_from_json(
      @protocol.protocol_parse_json("{\"path\":\"relative.txt\"}"),
    )
  catch {
    InvalidPath(path="location.path", value="relative.txt") => ()
    _ => fail("expected absolute path error")
  } noraise {
    _ => fail("expected location decoding to fail")
  }
  try
    @protocol.tool_call_location_from_json(
      @protocol.protocol_parse_json("{\"path\":\"/tmp/x\",\"line\":0}"),
    )
  catch {
    InvalidField(path="location.line", reason=_) => ()
    _ => fail("expected one-based line error")
  } noraise {
    _ => fail("expected location decoding to fail")
  }
  try
    @protocol.diff_from_json(
      @protocol.protocol_parse_json("{\"path\":\"/tmp/x\"}"),
    )
  catch {
    MissingField(path="diff.newText") => ()
    _ => fail("expected missing newText error")
  } noraise {
    _ => fail("expected diff decoding to fail")
  }
}

///|
test "tool location uint64 lines preserve exact values and reject invalid numbers" {
  for line in [9007199254740993UL, 18446744073709551615UL] {
    let location : @protocol.ToolCallLocation = {
      path: "/tmp/acp.txt",
      line: Value(line),
      meta: tool_test_omitted_json(),
    }
    assert_eq(
      @protocol.tool_call_location_from_json(
        @protocol.tool_call_location_to_json(location),
      ),
      location,
    )
  }

  let invalid : Array[(String, String)] = [
    ("{\"path\":\"/tmp/x\",\"line\":1.5}", "location.line"),
    ("{\"path\":\"/tmp/x\",\"line\":18446744073709551616}", "location.line"),
  ]
  for pair in invalid {
    let (source, expected_path) = pair
    try
      @protocol.tool_call_location_from_json(
        @protocol.protocol_parse_json(source),
      )
    catch {
      InvalidField(path=actual_path, reason=_) =>
        assert_eq(actual_path, expected_path)
      _ => fail("expected invalid tool location uint64 value")
    } noraise {
      _ => fail("expected invalid tool location uint64 value to fail")
    }
  }
}

///|
test "permission options outcomes and request payload round trip" {
  let permission_kinds : Array[@protocol.PermissionOptionKind] = [
    AllowOnce,
    AllowAlways,
    RejectOnce,
    RejectAlways,
  ]
  let option : @protocol.PermissionOption = {
    option_id: "allow",
    name: "Allow once",
    kind: AllowOnce,
    meta: Null,
  }
  for kind in permission_kinds {
    let value : @protocol.PermissionOption = { ..option, kind, }
    assert_eq(
      @protocol.permission_option_from_json(
        @protocol.permission_option_to_json(value),
      ),
      value,
    )
  }
  let selected : @protocol.RequestPermissionOutcome = Selected({
    option_id: "allow",
    meta: Omitted,
  })
  assert_eq(
    @protocol.request_permission_outcome_from_json(
      @protocol.request_permission_outcome_to_json(selected),
    ),
    selected,
  )
  let cancelled : @protocol.RequestPermissionOutcome = Cancelled
  assert_eq(
    @protocol.request_permission_outcome_from_json(
      @protocol.request_permission_outcome_to_json(cancelled),
    ),
    cancelled,
  )
  let request : @protocol.RequestPermissionRequest = {
    session_id: "session-1",
    tool_call: {
      tool_call_id: "call-1",
      kind: Value(Execute),
      status: Value(Pending),
      title: Omitted,
      content: Omitted,
      locations: Omitted,
      raw_input: Omitted,
      raw_output: Omitted,
      meta: Omitted,
    },
    options: [option],
    meta: Omitted,
  }
  assert_eq(
    @protocol.request_permission_request_from_json(
      @protocol.request_permission_request_to_json(request),
    ),
    request,
  )
  let response : @protocol.RequestPermissionResponse = {
    outcome: cancelled,
    meta: Null,
  }
  assert_eq(
    @protocol.request_permission_response_from_json(
      @protocol.request_permission_response_to_json(response),
    ),
    response,
  )
}

///|
test "tool discriminators and required fields fail explicitly" {
  try
    @protocol.tool_call_content_from_json(
      @protocol.protocol_parse_json("{\"type\":\"unknown\"}"),
    )
  catch {
    InvalidDiscriminator(path="toolContent.type", value="unknown") => ()
    _ => fail("expected unknown tool content discriminator")
  } noraise {
    _ => fail("expected tool content decoding to fail")
  }
  try
    @protocol.tool_call_from_json(
      @protocol.protocol_parse_json("{\"toolCallId\":\"call-1\"}"),
    )
  catch {
    MissingField(path="toolCall.title") => ()
    _ => fail("expected missing title error")
  } noraise {
    _ => fail("expected tool call decoding to fail")
  }
  try
    @protocol.request_permission_request_from_json(
      @protocol.protocol_parse_json(
        "{\"sessionId\":\"s\",\"toolCall\":{\"toolCallId\":\"c\"},\"options\":[]}",
      ),
    )
  catch {
    InvalidField(path="requestPermission.options", reason=_) => ()
    _ => fail("expected non-empty permission options error")
  } noraise {
    _ => fail("expected permission request decoding to fail")
  }

  try
    @protocol.tool_call_from_json(
      @protocol.protocol_parse_json(
        "{\"toolCallId\":\"call\",\"title\":\"Run\",\"kind\":\"future\"}",
      ),
    )
  catch {
    InvalidDiscriminator(path="toolCall.kind", value="future") => ()
    _ => fail("expected unknown tool kind rejection")
  } noraise {
    _ => fail("expected unknown tool kind to fail")
  }

  try
    @protocol.tool_call_from_json(
      @protocol.protocol_parse_json(
        "{\"toolCallId\":\"call\",\"title\":\"Run\",\"status\":\"future\"}",
      ),
    )
  catch {
    InvalidDiscriminator(path="toolCall.status", value="future") => ()
    _ => fail("expected unknown tool status rejection")
  } noraise {
    _ => fail("expected unknown tool status to fail")
  }

  try
    @protocol.permission_option_from_json(
      @protocol.protocol_parse_json(
        "{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"future\"}",
      ),
    )
  catch {
    InvalidDiscriminator(path="permissionOption.kind", value="future") => ()
    _ => fail("expected unknown permission option kind rejection")
  } noraise {
    _ => fail("expected unknown permission option kind to fail")
  }
}
