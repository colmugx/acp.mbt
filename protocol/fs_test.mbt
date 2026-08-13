///|
fn fs_test_meta() -> ProtocolNullable[Json] {
  Value({ "source": Json::string("test") })
}

///|
test "filesystem host methods preserve nullable fields and round trip" {
  let read : ReadTextFileParams = {
    session_id: "session-1",
    path: "/workspace/notes.txt",
    line: Value(2UL),
    limit: Null,
    meta: fs_test_meta(),
  }
  let encoded_read = read_text_file_params_to_json(read)
  let decoded_read = read_text_file_params_from_json(encoded_read) catch {
    InvalidField(path~, reason~) =>
      fail(
        path + ":" + reason + " wire=" + protocol_stringify_json(encoded_read),
      )
    _ => fail("unexpected filesystem integer decode error")
  }
  assert_eq(decoded_read, read)

  let read_result : ReadTextFileResult = { content: "héllo\n", meta: Omitted }
  assert_eq(
    read_text_file_result_from_json(read_text_file_result_to_json(read_result)),
    read_result,
  )

  let write : WriteTextFileParams = {
    session_id: "session-1",
    path: "/workspace/notes.txt",
    content: "updated",
    meta: Null,
  }
  assert_eq(
    write_text_file_params_from_json(write_text_file_params_to_json(write)),
    write,
  )

  let write_result : WriteTextFileResult = { meta: fs_test_meta() }
  assert_eq(
    write_text_file_result_from_json(
      write_text_file_result_to_json(write_result),
    ),
    write_result,
  )
}

///|
test "filesystem host validation rejects unsafe paths and invalid windows" {
  try
    read_text_file_params_from_json(
      protocol_parse_json("{\"sessionId\":\"s\",\"path\":\"relative.txt\"}"),
    )
  catch {
    InvalidPath(path="fs/read_text_file.path", value="relative.txt") => ()
    _ => fail("expected absolute path rejection")
  } noraise {
    _ => fail("expected absolute path rejection")
  }

  try
    read_text_file_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"path\":\"/tmp/x\",\"line\":0}",
      ),
    )
  catch {
    InvalidField(path="fs/read_text_file.line", reason=_) => ()
    _ => fail("expected one-based line rejection")
  } noraise {
    _ => fail("expected one-based line rejection")
  }

  try
    write_text_file_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"\",\"path\":\"/tmp/x\",\"content\":\"x\"}",
      ),
    )
  catch {
    InvalidField(path="fs/write_text_file.sessionId", reason=_) => ()
    _ => fail("expected empty session rejection")
  } noraise {
    _ => fail("expected empty session rejection")
  }

  try
    read_text_file_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"path\":\"/tmp/x\",\"unknown\":true}",
      ),
    )
  catch {
    UnknownField(path="fs/read_text_file.unknown") => ()
    _ => fail("expected unknown field rejection")
  } noraise {
    _ => fail("expected unknown field rejection")
  }
}
