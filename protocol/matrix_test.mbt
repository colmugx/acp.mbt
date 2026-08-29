///|
/// SDK-scope acceptance tests for the data-plane rows of
/// docs/implementation-plan/04-v1-completeness-matrix.md that live in the
/// pure protocol codecs: A08 (camelCase/discriminator strictness sweep over
/// the remaining codecs), F01-F04 (content block baselines and negatives),
/// F07/F11/F12 (tool kind/status, terminal tool content, permission options),
/// G01 (workspace root ordering at the wire surface), G03 (transport union
/// never falls back across discriminators), and G06 (terminal output/truncated
/// codec flags).
///
/// Every negative asserts the exact typed `ProtocolDecodeError` so failures
/// stay diagnosable; no decoder silently repairs a malformed payload.

///|
/// Row F02/A08: a resource link is addressable only through both required
/// string fields, and the wire keeps camelCase field names only.
test "matrix F02 A08 resource link requires uri and name with camelCase fields" {
  try
    content_block_from_json(
      protocol_parse_json("{\"type\":\"resource_link\",\"name\":\"notes\"}"),
    )
  catch {
    MissingField(path="content.uri") => ()
    _ => fail("expected missing resource link uri rejection")
  } noraise {
    _ => fail("expected resource link decoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json(
        "{\"type\":\"resource_link\",\"uri\":\"file:///tmp\"}",
      ),
    )
  catch {
    MissingField(path="content.name") => ()
    _ => fail("expected missing resource link name rejection")
  } noraise {
    _ => fail("expected resource link decoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json(
        "{\"type\":\"resource_link\",\"name\":\"notes\",\"uri\":\"file:///tmp\",\"mime_type\":\"text/plain\"}",
      ),
    )
  catch {
    UnknownField(path="content.mime_type") => ()
    _ => fail("expected snake_case field rejection in camelCase position")
  } noraise {
    _ => fail("expected resource link decoding to fail")
  }
  try
    resource_link_from_json(protocol_parse_json("{\"name\":\"notes\"}"))
  catch {
    MissingField(path="resource_link.uri") => ()
    _ => fail("expected bare codec missing uri rejection")
  } noraise {
    _ => fail("expected bare resource link decoding to fail")
  }
}

///|
/// Rows F03/F04: image and audio blocks are only decodable with both the
/// base64 payload and the mimeType present; the base64 negatives themselves
/// are proven in content_test.mbt.
test "matrix F03 F04 image and audio require data and mimeType" {
  try
    content_block_from_json(
      protocol_parse_json("{\"type\":\"image\",\"mimeType\":\"image/png\"}"),
    )
  catch {
    MissingField(path="content.data") => ()
    _ => fail("expected missing image data rejection")
  } noraise {
    _ => fail("expected image decoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json(
        "{\"type\":\"image\",\"data\":\"aA==\",\"mimeType\":7}",
      ),
    )
  catch {
    ExpectedString(path="content.mimeType") => ()
    _ => fail("expected non-string image mimeType rejection")
  } noraise {
    _ => fail("expected image decoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json("{\"type\":\"audio\",\"data\":\"aA==\"}"),
    )
  catch {
    MissingField(path="content.mimeType") => ()
    _ => fail("expected missing audio mimeType rejection")
  } noraise {
    _ => fail("expected audio decoding to fail")
  }
  try
    audio_content_from_json(protocol_parse_json("{\"mimeType\":\"a/w\"}"))
  catch {
    MissingField(path="audio.data") => ()
    _ => fail("expected bare codec missing audio data rejection")
  } noraise {
    _ => fail("expected bare audio decoding to fail")
  }
}

///|
/// Row A08/G03: the MCP transport union is discriminated strictly.  A wrong
/// case or an unknown discriminator never decodes, an HTTP/SSE entry never
/// decodes as stdio, and a stdio entry carrying HTTP-only fields is rejected
/// so no transport can be silently reinterpreted as another one.
test "matrix A08 G03 MCP transports stay discriminated without fallback" {
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"HTTP\",\"name\":\"x\",\"url\":\"https://e.test\",\"headers\":[]}",
      ),
    )
  catch {
    InvalidDiscriminator(path="mcpServer.type", value="HTTP") => ()
    _ => fail("expected wrong-case transport discriminator rejection")
  } noraise {
    _ => fail("expected MCP decoding to fail")
  }
  try
    mcp_server_from_json(
      protocol_parse_json("{\"type\":\"http\",\"name\":\"x\",\"headers\":[]}"),
    )
  catch {
    MissingField(path="mcpServer.url") => ()
    _ => fail("expected missing HTTP url rejection")
  } noraise {
    _ => fail("expected MCP decoding to fail")
  }
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"sse\",\"name\":\"x\",\"url\":\"https://e.test\"}",
      ),
    )
  catch {
    MissingField(path="mcpServer.headers") => ()
    _ => fail("expected missing SSE headers rejection")
  } noraise {
    _ => fail("expected MCP decoding to fail")
  }
  let http = mcp_server_from_json(
    protocol_parse_json(
      "{\"type\":\"http\",\"name\":\"x\",\"url\":\"https://e.test\",\"headers\":[]}",
    ),
  )
  assert_true(http is Http(_))
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"stdio\",\"name\":\"x\",\"command\":\"/bin/tool\",\"args\":[],\"env\":[],\"url\":\"https://e.test\"}",
      ),
    )
  catch {
    UnknownField(path="mcpServer.url") => ()
    _ => fail("expected HTTP-only field rejection on a stdio entry")
  } noraise {
    _ => fail("expected stdio entry with url to fail")
  }
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"http\",\"name\":\"x\",\"url\":\"https://e.test\",\"headers\":[],\"command\":\"/bin/tool\"}",
      ),
    )
  catch {
    UnknownField(path="mcpServer.command") => ()
    _ => fail("expected stdio-only field rejection on an HTTP entry")
  } noraise {
    _ => fail("expected HTTP entry with command to fail")
  }
}

///|
/// Row A08 (plan sweep): plan entries keep their snake_case value space; an
/// unknown priority or status is a typed discriminator failure with the exact
/// indexed wire path, never a default severity.
test "matrix A08 plan entries reject unknown priority and status values" {
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"plan\",\"entries\":[{\"content\":\"x\",\"priority\":\"urgent\",\"status\":\"pending\"}]}",
      ),
    )
  catch {
    InvalidDiscriminator(
      path="sessionUpdate.entries[0].priority",
      value="urgent"
    ) => ()
    _ => fail("expected unknown plan priority rejection")
  } noraise {
    _ => fail("expected plan decoding to fail")
  }
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"plan\",\"entries\":[{\"content\":\"x\",\"priority\":\"high\",\"status\":\"cancelled\"}]}",
      ),
    )
  catch {
    InvalidDiscriminator(
      path="sessionUpdate.entries[0].status",
      value="cancelled"
    ) => ()
    _ => fail("expected unknown plan status rejection")
  } noraise {
    _ => fail("expected plan decoding to fail")
  }
  try
    session_update_from_json(
      protocol_parse_json(
        "{\"sessionUpdate\":\"plan\",\"entries\":[{\"priority\":\"high\",\"status\":\"pending\"}]}",
      ),
    )
  catch {
    MissingField(path="sessionUpdate.entries[0].content") => ()
    _ => fail("expected missing plan content rejection")
  } noraise {
    _ => fail("expected plan decoding to fail")
  }
}

///|
/// Row F07: the tool kind and status value spaces are closed for replacement
/// updates too, not only for the initial tool call fixtures in tool_test.mbt.
test "matrix F07 tool update kinds and statuses reject unknown discriminators" {
  try
    tool_call_update_from_json(
      protocol_parse_json("{\"toolCallId\":\"call\",\"kind\":\"switchMode\"}"),
    )
  catch {
    InvalidDiscriminator(path="toolCallUpdate.kind", value="switchMode") => ()
    _ => fail("expected camelCase tool kind rejection")
  } noraise {
    _ => fail("expected tool update decoding to fail")
  }
  try
    tool_call_update_from_json(
      protocol_parse_json("{\"toolCallId\":\"call\",\"status\":\"done\"}"),
    )
  catch {
    InvalidDiscriminator(path="toolCallUpdate.status", value="done") => ()
    _ => fail("expected unknown tool update status rejection")
  } noraise {
    _ => fail("expected tool update decoding to fail")
  }
  let switch_mode = tool_call_update_from_json(
    protocol_parse_json(
      "{\"toolCallId\":\"call\",\"kind\":\"switch_mode\",\"status\":\"in_progress\"}",
    ),
  )
  assert_true(switch_mode.kind is Value(SwitchMode))
  assert_true(switch_mode.status is Value(InProgress))
}

///|
/// Row F11: terminal tool content references a terminal through a usable id.
/// Boundary: whether the id names a created, not-yet-released terminal is
/// service-owned registry state (proven through the client terminal service
/// in client/matrix_test.mbt rows D06/D09); the codec rejects a missing or
/// degenerate empty id in both directions so a tool call can never carry a
/// terminal reference that could not address any terminal.
test "matrix F11 terminal tool content requires a usable terminal id" {
  try
    tool_call_content_from_json(protocol_parse_json("{\"type\":\"terminal\"}"))
  catch {
    MissingField(path="toolContent.terminalId") => ()
    _ => fail("expected missing terminalId rejection")
  } noraise {
    _ => fail("expected terminal content decoding to fail")
  }
  try
    tool_call_content_from_json(
      protocol_parse_json("{\"type\":\"terminal\",\"terminalId\":\"\"}"),
    )
  catch {
    InvalidField(path="toolContent.terminalId", reason=_) => ()
    _ => fail("expected empty terminalId rejection")
  } noraise {
    _ => fail("expected terminal content decoding to fail")
  }
  let degenerate : Terminal = { terminal_id: "", meta: Omitted, }
  try terminal_to_json(degenerate) catch {
    InvalidField(path="terminalId", reason=_) => ()
    _ => fail("expected empty terminalId encode rejection")
  } noraise {
    _ => fail("expected terminal encode to fail")
  }
  let referenced = tool_call_content_from_json(
    protocol_parse_json(
      "{\"type\":\"terminal\",\"terminalId\":\"matrix-terminal\"}",
    ),
  )
  match referenced {
    Terminal(value) => assert_eq(value.terminal_id, "matrix-terminal")
    _ => fail("expected a decoded terminal tool content")
  }
}

///|
/// Row F12 remainder: permission outcomes keep a closed discriminator set.
/// Selecting an option requires an optionId, and an unknown outcome never
/// decodes into a default allow.
test "matrix F12 permission outcomes reject unknown discriminators" {
  try
    request_permission_outcome_from_json(
      protocol_parse_json("{\"outcome\":\"deferred\"}"),
    )
  catch {
    InvalidDiscriminator(path="outcome.outcome", value="deferred") => ()
    _ => fail("expected unknown permission outcome rejection")
  } noraise {
    _ => fail("expected permission outcome decoding to fail")
  }
  try
    request_permission_outcome_from_json(
      protocol_parse_json("{\"outcome\":\"selected\"}"),
    )
  catch {
    MissingField(path="outcome.optionId") => ()
    _ => fail("expected missing optionId rejection")
  } noraise {
    _ => fail("expected selected outcome decoding to fail")
  }
  try request_permission_response_from_json(protocol_parse_json("{}")) catch {
    MissingField(path="requestPermission.outcome") => ()
    _ => fail("expected missing permission outcome rejection")
  } noraise {
    _ => fail("expected permission response decoding to fail")
  }
  try
    request_permission_outcome_from_json(
      protocol_parse_json("{\"outcome\":\"cancelled\",\"extra\":true}"),
    )
  catch {
    UnknownField(path="outcome.extra") => ()
    _ => fail("expected cancelled outcome extra field rejection")
  } noraise {
    _ => fail("expected cancelled outcome decoding to fail")
  }
}

///|
/// Row G06: the terminal output result keeps the `output`/`truncated` pair
/// exactly, including multibyte UTF-8 output.  Boundary: performing the
/// outputByteLimit truncation itself is service-owned — the client terminal
/// service owns the process output buffer, truncates from the start of the
/// output, and must keep UTF-8 character boundaries; the SDK owns the wire
/// contract (exact uint64 limit parameter, lossless output string, honest
/// truncated flag) proven here in both directions.
test "matrix G06 terminal output and truncated flags round trip both ways" {
  let truncated_result : TerminalOutputResult = {
    output: "边界テスト🚀",
    truncated: true,
    exit_status: Value({
      exit_code: Value(1UL),
      signal: Omitted,
      meta: Omitted,
    }),
    meta: Omitted,
  }
  assert_eq(
    terminal_output_result_from_json(
      terminal_output_result_to_json(truncated_result),
    ),
    truncated_result,
  )
  let complete_result : TerminalOutputResult = {
    output: "",
    truncated: false,
    exit_status: Omitted,
    meta: Omitted,
  }
  assert_eq(
    terminal_output_result_from_json(
      terminal_output_result_to_json(complete_result),
    ),
    complete_result,
  )
  try
    terminal_output_result_from_json(
      protocol_parse_json("{\"output\":\"x\",\"exitStatus\":null}"),
    )
  catch {
    MissingField(path="terminal/output.truncated") => ()
    _ => fail("expected missing truncated flag rejection")
  } noraise {
    _ => fail("expected terminal output decoding to fail")
  }
}
