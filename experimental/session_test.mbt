///|
test "v2 session new params round-trip the full shape" {
  let decoded = model_test_round_trip(
    "{\"cwd\":\"/work\",\"additionalDirectories\":[\"/a\",\"/b\"],\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"n\",\"command\":\"/bin/n\"},{\"type\":\"http\",\"name\":\"h\",\"url\":\"https://x/mcp\"}],\"_meta\":{}}",
    value => experimental_v2_decode_new_session_params(value),
    experimental_v2_encode_new_session_params,
  )
  assert_eq(decoded.cwd, "/work")
  assert_eq(decoded.additional_directories, Some(["/a", "/b"]))
  assert_true(decoded.mcp_servers is Some([_, _]))
  let bare = model_test_round_trip(
    "{\"cwd\":\"/work\"}",
    value => experimental_v2_decode_new_session_params(value),
    experimental_v2_encode_new_session_params,
  )
  assert_true(bare.additional_directories is None)
  assert_true(bare.mcp_servers is None)
}

///|
test "v2 session new params reject relative cwd and v1-only fields" {
  try
    experimental_v2_decode_new_session_params(
      experimental_v2_parse_json("{\"cwd\":\"relative\"}"),
    )
  catch {
    InvalidPath(path="session/new.cwd", value="relative") => ()
    _ => fail("expected InvalidPath for a relative cwd")
  } noraise {
    _ => fail("expected InvalidPath for a relative cwd")
  }
  try
    experimental_v2_decode_new_session_params(
      experimental_v2_parse_json("{\"cwd\":\"/w\",\"modes\":[]}"),
    )
  catch {
    UnknownField(path="session/new.modes") => ()
    _ => fail("expected UnknownField for the removed v1 modes field")
  } noraise {
    _ => fail("expected UnknownField for the removed v1 modes field")
  }
}

///|
test "v2 session new result round-trips config options and requires sessionId" {
  let decoded = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"configOptions\":[{\"type\":\"boolean\",\"configId\":\"verbose\",\"name\":\"Verbose\",\"currentValue\":true}],\"_meta\":{}}",
    value => experimental_v2_decode_new_session_result(value),
    experimental_v2_encode_new_session_result,
  )
  assert_eq(decoded.session_id, "s1")
  assert_true(decoded.config_options is Some([Known(_)]))
  try
    experimental_v2_decode_new_session_result(
      experimental_v2_parse_json("{\"configOptions\":[]}"),
    )
  catch {
    MissingField(path="session/new.sessionId") => ()
    _ => fail("expected MissingField for an absent sessionId")
  } noraise {
    _ => fail("expected MissingField for an absent sessionId")
  }
}

///|
test "v2 session resume params round-trip replayFrom start" {
  let decoded = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"cwd\":\"/work\",\"additionalDirectories\":[],\"replayFrom\":{\"type\":\"start\",\"_meta\":{\"k\":1}}}",
    value => experimental_v2_decode_resume_session_params(value),
    experimental_v2_encode_resume_session_params,
  )
  assert_true(decoded.replay_from is Some(Known({ meta: Some(Object(_)), })))
  let omitted = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"cwd\":\"/work\"}",
    value => experimental_v2_decode_resume_session_params(value),
    experimental_v2_encode_resume_session_params,
  )
  assert_true(omitted.replay_from is None)
  assert_true(
    experimental_v2_decode_resume_session_params(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s1\",\"cwd\":\"/work\",\"replayFrom\":null}",
      ),
    ).replay_from
    is None,
  )
}

///|
test "v2 session resume replayFrom unknown cursor stays raw" {
  let source = "{\"type\":\"future-cursor\",\"after\":\"m1\"}"
  let decoded = experimental_v2_decode_replay_from(
    experimental_v2_parse_json(source),
  )
  assert_true(decoded is Future(tag="future-cursor", ..))
  assert_eq(
    experimental_v2_stringify_json(experimental_v2_encode_replay_from(decoded)),
    source,
  )
  let extension_source = "{\"type\":\"_resume\",\"mark\":7}"
  let extension = experimental_v2_decode_replay_from(
    experimental_v2_parse_json(extension_source),
  )
  assert_true(extension is Extension(tag="_resume", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_replay_from(extension),
    ),
    extension_source,
  )
}

///|
test "v2 session resume params require sessionId and absolute cwd" {
  try
    experimental_v2_decode_resume_session_params(
      experimental_v2_parse_json("{\"cwd\":\"/work\"}"),
    )
  catch {
    MissingField(path="session/resume.sessionId") => ()
    _ => fail("expected MissingField for an absent sessionId")
  } noraise {
    _ => fail("expected MissingField for an absent sessionId")
  }
  try
    experimental_v2_decode_resume_session_params(
      experimental_v2_parse_json("{\"sessionId\":\"s\",\"cwd\":\"w\"}"),
    )
  catch {
    InvalidPath(path="session/resume.cwd", value="w") => ()
    _ => fail("expected InvalidPath for a relative cwd")
  } noraise {
    _ => fail("expected InvalidPath for a relative cwd")
  }
}

///|
test "v2 session list params and result round-trip pagination" {
  let decoded = model_test_round_trip(
    "{\"cwd\":\"/work\",\"cursor\":\"opaque-1\",\"_meta\":{}}",
    value => experimental_v2_decode_list_sessions_params(value),
    experimental_v2_encode_list_sessions_params,
  )
  assert_eq(decoded.cwd, Some("/work"))
  assert_eq(decoded.cursor, Some("opaque-1"))
  assert_true(
    experimental_v2_decode_list_sessions_params(
      experimental_v2_parse_json("{\"cwd\":null}"),
    ).cwd
    is None,
  )
  try
    experimental_v2_decode_list_sessions_params(
      experimental_v2_parse_json("{\"cwd\":\"relative\"}"),
    )
  catch {
    InvalidPath(path="session/list.cwd", value="relative") => ()
    _ => fail("expected InvalidPath for a relative list cwd")
  } noraise {
    _ => fail("expected InvalidPath for a relative list cwd")
  }
  let result = model_test_round_trip(
    "{\"sessions\":[{\"sessionId\":\"s1\",\"cwd\":\"/work\",\"title\":\"T\",\"updatedAt\":\"2026-01-01T00:00:00Z\",\"additionalDirectories\":[\"/a\"]}],\"nextCursor\":\"opaque-2\"}",
    value => experimental_v2_decode_list_sessions_result(value),
    experimental_v2_encode_list_sessions_result,
  )
  assert_true(result.sessions is [_])
  assert_eq(result.next_cursor, Some("opaque-2"))
  try
    experimental_v2_decode_list_sessions_result(
      experimental_v2_parse_json("{}"),
    )
  catch {
    MissingField(path="session/list.sessions") => ()
    _ => fail("expected MissingField for absent sessions")
  } noraise {
    _ => fail("expected MissingField for absent sessions")
  }
}

///|
test "v2 session info validates additional directories per item" {
  try
    experimental_v2_decode_session_info(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s\",\"cwd\":\"/w\",\"additionalDirectories\":[\"relative\"]}",
      ),
    )
  catch {
    InvalidPath(path="sessionInfo.additionalDirectories[0]", value="relative") =>
      ()
    _ => fail("expected InvalidPath for a relative additional directory")
  } noraise {
    _ => fail("expected InvalidPath for a relative additional directory")
  }
}

///|
test "v2 session delete and close params validate the session id" {
  let deleted = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_delete_session_params(value),
    experimental_v2_encode_delete_session_params,
  )
  assert_eq(deleted.session_id, "s1")
  let closed = model_test_round_trip(
    "{\"sessionId\":\"s1\"}",
    value => experimental_v2_decode_close_session_params(value),
    experimental_v2_encode_close_session_params,
  )
  assert_eq(closed.session_id, "s1")
  try
    experimental_v2_decode_close_session_params(
      experimental_v2_parse_json("{\"sessionId\":\"\"}"),
    )
  catch {
    InvalidField(path="session/close.sessionId", reason="id must not be empty") =>
      ()
    _ => fail("expected InvalidField for an empty sessionId")
  } noraise {
    _ => fail("expected InvalidField for an empty sessionId")
  }
}

///|
test "v2 session fork params round-trip the unstable overlay shape" {
  let decoded = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"cwd\":\"/work\",\"additionalDirectories\":[\"/a\"],\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"n\",\"command\":\"/bin/n\"}],\"_meta\":{}}",
    value => experimental_v2_decode_fork_session_params(value),
    experimental_v2_encode_fork_session_params,
  )
  assert_eq(decoded.session_id, "s1")
  assert_eq(decoded.cwd, "/work")
  assert_eq(decoded.additional_directories, Some(["/a"]))
  assert_true(decoded.mcp_servers is Some([Known(_)]))
  let bare = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"cwd\":\"/work\"}",
    value => experimental_v2_decode_fork_session_params(value),
    experimental_v2_encode_fork_session_params,
  )
  assert_true(bare.additional_directories is None)
  assert_true(bare.mcp_servers is None)
  // Omitted and null mcpServers are the same "no servers" value (v2 unstable
  // overlay convention).
  assert_true(
    experimental_v2_decode_fork_session_params(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s1\",\"cwd\":\"/work\",\"mcpServers\":null}",
      ),
    ).mcp_servers
    is None,
  )
}

///|
test "v2 session fork params require sessionId and absolute cwd and reject modes" {
  try
    experimental_v2_decode_fork_session_params(
      experimental_v2_parse_json("{\"cwd\":\"/work\"}"),
    )
  catch {
    MissingField(path="session/fork.sessionId") => ()
    _ => fail("expected MissingField for an absent fork sessionId")
  } noraise {
    _ => fail("expected MissingField for an absent fork sessionId")
  }
  try
    experimental_v2_decode_fork_session_params(
      experimental_v2_parse_json("{\"sessionId\":\"s\",\"cwd\":\"w\"}"),
    )
  catch {
    InvalidPath(path="session/fork.cwd", value="w") => ()
    _ => fail("expected InvalidPath for a relative fork cwd")
  } noraise {
    _ => fail("expected InvalidPath for a relative fork cwd")
  }
  try
    experimental_v2_decode_fork_session_params(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s\",\"cwd\":\"/w\",\"modes\":[]}",
      ),
    )
  catch {
    UnknownField(path="session/fork.modes") => ()
    _ => fail("expected UnknownField for the v1-only modes field")
  } noraise {
    _ => fail("expected UnknownField for the v1-only modes field")
  }
}

///|
test "v2 session fork result round-trips and requires sessionId" {
  let decoded = model_test_round_trip(
    "{\"sessionId\":\"fork-1\",\"configOptions\":[{\"type\":\"boolean\",\"configId\":\"verbose\",\"name\":\"Verbose\",\"currentValue\":true}]}",
    value => experimental_v2_decode_fork_session_result(value),
    experimental_v2_encode_fork_session_result,
  )
  assert_eq(decoded.session_id, "fork-1")
  assert_true(decoded.config_options is Some([Known(_)]))
  try
    experimental_v2_decode_fork_session_result(
      experimental_v2_parse_json("{\"configOptions\":[]}"),
    )
  catch {
    MissingField(path="session/fork.sessionId") => ()
    _ => fail("expected MissingField for an absent fork result sessionId")
  } noraise {
    _ => fail("expected MissingField for an absent fork result sessionId")
  }
}

///|
test "v2 session delete and close results are meta-only" {
  assert_true(
    model_test_round_trip(
      "{}",
      value => experimental_v2_decode_delete_session_result(value),
      experimental_v2_encode_delete_session_result,
    ).meta
    is None,
  )
  assert_true(
    model_test_round_trip(
      "{\"_meta\":{\"k\":1}}",
      value => experimental_v2_decode_close_session_result(value),
      experimental_v2_encode_close_session_result,
    ).meta
    is Some(Object(_)),
  )
  try
    experimental_v2_decode_delete_session_result(
      experimental_v2_parse_json("{\"extra\":1}"),
    )
  catch {
    UnknownField(path="session/delete.extra") => ()
    _ => fail("expected UnknownField for a foreign delete result field")
  } noraise {
    _ => fail("expected UnknownField for a foreign delete result field")
  }
}
