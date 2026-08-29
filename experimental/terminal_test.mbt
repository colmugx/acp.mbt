///|
test "v2 terminal content block and output chunk round-trip base64" {
  let terminal = model_test_round_trip(
    "{\"type\":\"terminal\",\"terminalId\":\"t1\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_tool_call_content(value),
    experimental_v2_encode_tool_call_content,
  )
  assert_true(
    terminal is Known(ToolCallContentTerminal({ terminal_id: "t1", .. })),
  )
  let chunk = model_test_round_trip(
    "{\"terminalId\":\"t1\",\"data\":\"aGVsbG8=\",\"_meta\":{\"c\":2}}",
    value => experimental_v2_decode_terminal_output_chunk(value),
    experimental_v2_encode_terminal_output_chunk,
  )
  assert_eq(chunk.data, "aGVsbG8=")
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"terminalId\":\"t1\",\"data\":\"%%%\"}",
      InvalidBase64(path="terminalOutputChunk.data"),
    ),
    (
      "{\"terminalId\":\"\",\"data\":\"AA==\"}",
      InvalidField(
        path="terminalOutputChunk.terminalId",
        reason="id must not be empty",
      ),
    ),
    ("{\"terminalId\":\"t1\"}", MissingField(path="terminalOutputChunk.data")),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_terminal_output_chunk(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed terminal chunk")
    }
  }
}

///|
test "v2 terminal update applies patch tri-state beyond the id" {
  let bare = model_test_round_trip(
    "{\"terminalId\":\"t1\"}",
    value => experimental_v2_decode_terminal_update(value),
    experimental_v2_encode_terminal_update,
  )
  assert_eq(bare, {
    terminal_id: "t1",
    command: PatchOmitted,
    cwd: PatchOmitted,
    output: PatchOmitted,
    exit_status: PatchOmitted,
    meta: PatchOmitted,
  })
  let full = model_test_round_trip(
    "{\"terminalId\":\"t1\",\"command\":\"cargo test\",\"cwd\":\"/repo\",\"output\":{\"data\":\"aGVsbG8=\"},\"exitStatus\":{\"exitCode\":0,\"signal\":null,\"_meta\":{\"e\":1}},\"_meta\":{\"u\":2}}",
    value => experimental_v2_decode_terminal_update(value),
    experimental_v2_encode_terminal_update,
  )
  guard full.command is PatchValue(command) else {
    fail("expected a replaced command")
  }
  assert_eq(command, "cargo test")
  guard full.cwd is PatchValue(cwd) else { fail("expected a replaced cwd") }
  assert_eq(cwd, "/repo")
  guard full.exit_status is PatchValue(exit_status) else {
    fail("expected a replaced exit status")
  }
  assert_eq(exit_status.exit_code, Some(0))
  assert_eq(exit_status.signal, None)
  let cleared = model_test_round_trip(
    "{\"terminalId\":\"t1\",\"command\":null,\"cwd\":null,\"output\":null,\"exitStatus\":null,\"_meta\":null}",
    value => experimental_v2_decode_terminal_update(value),
    experimental_v2_encode_terminal_update,
  )
  assert_true(
    cleared.command is PatchNull &&
    cleared.cwd is PatchNull &&
    cleared.output is PatchNull &&
    cleared.exit_status is PatchNull &&
    cleared.meta is PatchNull,
  )
}

///|
test "v2 terminal update enforces absolute cwd and base64 output" {
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"terminalId\":\"t1\",\"cwd\":\"repo\"}",
      InvalidPath(path="terminal.cwd", value="repo"),
    ),
    (
      "{\"terminalId\":\"t1\",\"output\":{\"data\":\"nope!\"}}",
      InvalidBase64(path="terminal.output.data"),
    ),
    (
      "{\"terminalId\":\"t1\",\"exitStatus\":{\"exitCode\":-1}}",
      InvalidField(
        path="terminal.exitStatus.exitCode",
        reason="expected a uint32 integer",
      ),
    ),
    (
      "{\"terminalId\":\"t1\",\"exitStatus\":{\"exitCode\":4294967296}}",
      InvalidField(
        path="terminal.exitStatus.exitCode",
        reason="expected a uint32 integer",
      ),
    ),
    (
      "{\"terminalId\":\"\",\"command\":\"x\"}",
      InvalidField(path="terminal.terminalId", reason="id must not be empty"),
    ),
    ("{\"command\":\"x\"}", MissingField(path="terminal.terminalId")),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_terminal_update(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed terminal update")
    }
  }
  try
    experimental_v2_encode_terminal_update({
      terminal_id: "t1",
      command: PatchOmitted,
      cwd: PatchValue("relative"),
      output: PatchOmitted,
      exit_status: PatchOmitted,
      meta: PatchOmitted,
    })
  catch {
    error => assert_eq(error, InvalidPath(path="cwd", value="relative"))
  } noraise {
    _ => fail("expected InvalidPath for a relative cwd on encode")
  }
}

///|
test "v2 terminal exit status boundaries and nullable equivalence" {
  for exit_code in [0U, 4294967295U] {
    let decoded = experimental_v2_decode_terminal_update(
      experimental_v2_parse_json(
        "{\"terminalId\":\"t1\",\"exitStatus\":{\"exitCode\":\{exit_code}}}",
      ),
    )
    assert_true(decoded.exit_status is PatchValue({ exit_code: Some(_), .. }))
  }
  let null_fields = model_test_round_trip(
    "{\"terminalId\":\"t1\",\"exitStatus\":{\"exitCode\":null,\"signal\":null,\"_meta\":null}}",
    value => experimental_v2_decode_terminal_update(value),
    experimental_v2_encode_terminal_update,
  )
  assert_true(
    null_fields.exit_status
    is PatchValue({ exit_code: None, signal: None, meta: None, }),
  )
}
