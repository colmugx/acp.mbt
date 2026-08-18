///|
test "v2 tool call update tri-state omits nulls and replaces values" {
  let bare = model_test_round_trip(
    "{\"toolCallId\":\"tc1\"}",
    value => experimental_v2_decode_tool_call_update(value),
    experimental_v2_encode_tool_call_update,
  )
  assert_eq(bare, {
    tool_call_id: "tc1",
    title: PatchOmitted,
    kind: PatchOmitted,
    status: PatchOmitted,
    content: PatchOmitted,
    locations: PatchOmitted,
    raw_input: PatchOmitted,
    raw_output: PatchOmitted,
    meta: PatchOmitted,
  })
  let full = model_test_round_trip(
    "{\"toolCallId\":\"tc1\",\"title\":\"Read config\",\"kind\":\"read\",\"status\":\"in_progress\",\"content\":[{\"type\":\"content\",\"content\":{\"type\":\"text\",\"text\":\"out\"}}],\"locations\":[{\"path\":\"/repo/a.txt\",\"line\":12}],\"rawInput\":{\"path\":\"/repo/a.txt\"},\"rawOutput\":\"done\",\"_meta\":{\"t\":1}}",
    value => experimental_v2_decode_tool_call_update(value),
    experimental_v2_encode_tool_call_update,
  )
  guard full.title is PatchValue(title) else {
    fail("expected a replaced title")
  }
  assert_eq(title, "Read config")
  assert_true(full.kind is PatchValue(ToolKindRead))
  assert_true(full.status is PatchValue(ToolCallStatusInProgress))
  guard full.content is PatchValue(items) else {
    fail("expected replaced content")
  }
  assert_eq(items.length(), 1)
  assert_true(
    items[0]
    is Known(
      ToolCallContentBlock(
        { content: Known(BlockText({ text: "out", .. })), .. }
      )
    ),
  )
  guard full.raw_input is PatchValue(raw_input) else {
    fail("expected a replaced raw input")
  }
  assert_true(raw_input is Object(_))
  assert_true(full.raw_output is PatchValue(String("done")))
  let cleared = model_test_round_trip(
    "{\"toolCallId\":\"tc1\",\"title\":null,\"kind\":null,\"status\":null,\"content\":null,\"locations\":null,\"rawInput\":null,\"rawOutput\":null,\"_meta\":null}",
    value => experimental_v2_decode_tool_call_update(value),
    experimental_v2_encode_tool_call_update,
  )
  assert_true(
    cleared.title is PatchNull &&
    cleared.kind is PatchNull &&
    cleared.status is PatchNull &&
    cleared.content is PatchNull &&
    cleared.locations is PatchNull &&
    cleared.raw_input is PatchNull &&
    cleared.raw_output is PatchNull &&
    cleared.meta is PatchNull,
  )
}

///|
test "v2 tool call update collection patches replace wholesale" {
  let first = model_test_round_trip(
    "{\"toolCallId\":\"tc1\",\"locations\":[{\"path\":\"/a\"},{\"path\":\"/b\"}]}",
    value => experimental_v2_decode_tool_call_update(value),
    experimental_v2_encode_tool_call_update,
  )
  guard first.locations is PatchValue(locations) else {
    fail("expected replaced locations")
  }
  assert_eq(locations.length(), 2)
  let emptied = model_test_round_trip(
    "{\"toolCallId\":\"tc1\",\"locations\":[]}",
    value => experimental_v2_decode_tool_call_update(value),
    experimental_v2_encode_tool_call_update,
  )
  guard emptied.locations is PatchValue(locations) else {
    fail("expected a wholesale-cleared collection")
  }
  assert_eq(locations.length(), 0)
  let encoded = experimental_v2_encode_tool_call_update(emptied).stringify()
  assert_eq(encoded, "{\"toolCallId\":\"tc1\",\"locations\":[]}")
}

///|
test "v2 tool kind and status model every defined and open value" {
  let kind_cases : Array[(String, ExperimentalV2ToolKind)] = [
    ("read", ToolKindRead),
    ("edit", ToolKindEdit),
    ("delete", ToolKindDelete),
    ("move", ToolKindMove),
    ("search", ToolKindSearch),
    ("execute", ToolKindExecute),
    ("think", ToolKindThink),
    ("fetch", ToolKindFetch),
    ("switch_mode", ToolKindSwitchMode),
    ("other", ToolKindOther),
    ("_vendor", ToolKindExtension(tag="_vendor")),
    ("strange", ToolKindFuture(raw="strange")),
  ]
  for entry in kind_cases {
    let (tag, expected) = entry
    let decoded = experimental_v2_decode_tool_kind(Json::string(tag))
    assert_eq(decoded, expected)
    assert_eq(
      experimental_v2_decode_tool_kind(
        experimental_v2_encode_tool_kind(decoded),
      ),
      decoded,
    )
  }
  let status_cases : Array[(String, ExperimentalV2ToolCallStatus)] = [
    ("pending", ToolCallStatusPending),
    ("in_progress", ToolCallStatusInProgress),
    ("completed", ToolCallStatusCompleted),
    ("failed", ToolCallStatusFailed),
    ("cancelled", ToolCallStatusCancelled),
    ("_later", ToolCallStatusExtension(tag="_later")),
    ("paused", ToolCallStatusFuture(raw="paused")),
  ]
  for entry in status_cases {
    let (tag, expected) = entry
    let decoded = experimental_v2_decode_tool_call_status(Json::string(tag))
    assert_eq(decoded, expected)
    assert_eq(
      experimental_v2_decode_tool_call_status(
        experimental_v2_encode_tool_call_status(decoded),
      ),
      decoded,
    )
  }
  try experimental_v2_decode_tool_kind(Json::number(1.0)) catch {
    error => assert_eq(error, ExpectedString(path="kind"))
  } noraise {
    _ => fail("expected ExpectedString for a non-string tool kind")
  }
}

///|
test "v2 tool call location validates absolute paths and uint32 lines" {
  let decoded = model_test_round_trip(
    "{\"path\":\"/repo/src/main.mbt\",\"line\":4294967295,\"_meta\":{\"l\":1}}",
    value => experimental_v2_decode_tool_call_location(value),
    experimental_v2_encode_tool_call_location,
  )
  assert_eq(decoded.line, Some(4294967295U))
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"path\":\"src/main.mbt\"}",
      InvalidPath(path="location.path", value="src/main.mbt"),
    ),
    (
      "{\"path\":\"/a\",\"line\":-1}",
      InvalidField(path="location.line", reason="expected a uint32 integer"),
    ),
    (
      "{\"path\":\"/a\",\"line\":1.5}",
      InvalidField(path="location.line", reason="expected a uint32 integer"),
    ),
    (
      "{\"path\":\"/a\",\"line\":4294967296}",
      InvalidField(path="location.line", reason="expected a uint32 integer"),
    ),
    ("{\"line\":1}", MissingField(path="location.path")),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_tool_call_location(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed location")
    }
  }
}

///|
test "v2 tool call content union covers diff terminal and open arms" {
  let diff = model_test_round_trip(
    "{\"type\":\"diff\",\"changes\":[{\"operation\":\"modify\",\"path\":\"/a\"}],\"patch\":{\"format\":\"git_patch\",\"text\":\"p\"}}",
    value => experimental_v2_decode_tool_call_content(value),
    experimental_v2_encode_tool_call_content,
  )
  assert_true(
    diff
    is Known(ToolCallContentDiff({ changes: [Known(ChangeModify(_))], .. })),
  )
  let terminal = model_test_round_trip(
    "{\"type\":\"terminal\",\"terminalId\":\"t9\"}",
    value => experimental_v2_decode_tool_call_content(value),
    experimental_v2_encode_tool_call_content,
  )
  assert_true(
    terminal is Known(ToolCallContentTerminal({ terminal_id: "t9", .. })),
  )
  let extension = model_test_round_trip(
    "{\"type\":\"_chart\",\"points\":[1,2,3]}",
    value => experimental_v2_decode_tool_call_content(value),
    experimental_v2_encode_tool_call_content,
  )
  assert_true(extension is Extension(tag="_chart", ..))
  let future = model_test_round_trip(
    "{\"type\":\"video\",\"src\":\"file:///v\"}",
    value => experimental_v2_decode_tool_call_content(value),
    experimental_v2_encode_tool_call_content,
  )
  assert_true(future is Future(tag="video", ..))
}

///|
test "v2 tool call content chunk requires id and single content item" {
  let chunk = model_test_round_trip(
    "{\"toolCallId\":\"tc1\",\"content\":{\"type\":\"content\",\"content\":{\"type\":\"text\",\"text\":\"part\"}},\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_tool_call_content_chunk(value),
    experimental_v2_encode_tool_call_content_chunk,
  )
  assert_eq(chunk.tool_call_id, "tc1")
  assert_true(
    chunk.content
    is Known(
      ToolCallContentBlock(
        { content: Known(BlockText({ text: "part", .. })), .. }
      )
    ),
  )
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"content\":{\"type\":\"terminal\",\"terminalId\":\"t\"}}",
      MissingField(path="toolCallContentChunk.toolCallId"),
    ),
    (
      "{\"toolCallId\":\"\",\"content\":{\"type\":\"terminal\",\"terminalId\":\"t\"}}",
      InvalidField(
        path="toolCallContentChunk.toolCallId",
        reason="id must not be empty",
      ),
    ),
    (
      "{\"toolCallId\":\"tc1\"}",
      MissingField(path="toolCallContentChunk.content"),
    ),
    (
      "{\"toolCallId\":\"tc1\",\"content\":{\"terminalId\":\"t\"}}",
      MissingField(path="toolCallContentChunk.content.type"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_tool_call_content_chunk(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed tool-call chunk")
    }
  }
}
