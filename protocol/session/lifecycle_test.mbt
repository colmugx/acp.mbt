///|
fn session_lifecycle_test_meta() -> ProtocolNullable[Json] {
  Omitted
}

///|
fn session_lifecycle_test_info() -> SessionInfo {
  {
    session_id: "s-1",
    cwd: "/workspace",
    additional_directories: Value(["/workspace/shared"]),
    title: Null,
    updated_at: Value("2026-08-11T12:00:00Z"),
    meta: session_lifecycle_test_meta(),
  }
}

///|
fn session_lifecycle_test_update() -> SessionUpdate {
  UserMessageChunk({
    content: Text({
      annotations: Omitted,
      text: "hello",
      meta: session_lifecycle_test_meta(),
    }),
    message_id: Value("message-1"),
    meta: session_lifecycle_test_meta(),
  })
}

///|
test "session list delete close cancel and update envelopes round trip" {
  let list_params : ListSessionsParams = {
    cwd: Null,
    cursor: Value("cursor-1"),
    meta: Null,
  }
  assert_eq(
    list_sessions_params_from_json(list_sessions_params_to_json(list_params)),
    list_params,
  )

  let list_result : ListSessionsResult = {
    sessions: [session_lifecycle_test_info()],
    next_cursor: Null,
    meta: Value({ "page": Json::number(1.0) }),
  }
  assert_eq(
    list_sessions_result_from_json(list_sessions_result_to_json(list_result)),
    list_result,
  )

  let delete_params : DeleteSessionParams = {
    session_id: "s-delete",
    meta: Omitted,
  }
  assert_eq(
    delete_session_params_from_json(
      delete_session_params_to_json(delete_params),
    ),
    delete_params,
  )
  let delete_result : DeleteSessionResult = { meta: Null, }
  assert_eq(
    delete_session_result_from_json(
      delete_session_result_to_json(delete_result),
    ),
    delete_result,
  )

  let close_params : CloseSessionParams = {
    session_id: "s-close",
    meta: Value({ "request": Json::string("close") }),
  }
  assert_eq(
    close_session_params_from_json(close_session_params_to_json(close_params)),
    close_params,
  )
  let close_result : CloseSessionResult = { meta: Omitted, }
  assert_eq(
    close_session_result_from_json(close_session_result_to_json(close_result)),
    close_result,
  )

  let cancel : CancelParams = { session_id: "s-cancel", meta: Null, }
  assert_eq(cancel_params_from_json(cancel_params_to_json(cancel)), cancel)

  let update : SessionUpdateParams = {
    session_id: "s-1",
    update: session_lifecycle_test_update(),
    meta: Null,
  }
  assert_eq(
    session_update_params_from_json(session_update_params_to_json(update)),
    update,
  )
}

///|
test "session list preserves omitted and null filters and pagination" {
  let omitted = list_sessions_params_from_json(protocol_parse_json("{}"))
  assert_eq(omitted.cwd, Omitted)
  assert_eq(omitted.cursor, Omitted)

  let nulls = list_sessions_params_from_json(
    protocol_parse_json("{\"cwd\":null,\"cursor\":null}"),
  )
  assert_eq(nulls.cwd, Null)
  assert_eq(nulls.cursor, Null)

  let result = list_sessions_result_from_json(
    protocol_parse_json("{\"sessions\":[]}"),
  )
  assert_eq(result.next_cursor, Omitted)
}

///|
test "session lifecycle rejects invalid roots required fields and unknown fields" {
  try
    list_sessions_params_from_json(
      protocol_parse_json("{\"cwd\":\"relative\"}"),
    )
  catch {
    InvalidPath(path="session/list.cwd", value="relative") => ()
    _ => fail("expected list cwd path rejection")
  } noraise {
    _ => fail("expected list cwd path rejection")
  }

  try
    list_sessions_result_from_json(
      protocol_parse_json(
        "{\"sessions\":[{\"sessionId\":\"s\",\"cwd\":\"relative\"}]}",
      ),
    )
  catch {
    InvalidPath(path="session/list.sessions[0].cwd", value="relative") => ()
    _ => fail("expected session info cwd path rejection")
  } noraise {
    _ => fail("expected session info cwd path rejection")
  }

  try list_sessions_result_from_json(protocol_parse_json("{}")) catch {
    MissingField(path="session/list.sessions") => ()
    _ => fail("expected missing sessions")
  } noraise {
    _ => fail("expected missing sessions")
  }

  try
    cancel_params_from_json(
      protocol_parse_json("{\"sessionId\":\"s\",\"extra\":true}"),
    )
  catch {
    UnknownField(path="session/cancel.extra") => ()
    _ => fail("expected cancel unknown field rejection")
  } noraise {
    _ => fail("expected cancel unknown field rejection")
  }
}

///|
test "session update envelope delegates update discriminator and rejects malformed fields" {
  try
    session_update_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"update\":{\"sessionUpdate\":\"future\"}}",
      ),
    )
  catch {
    InvalidDiscriminator(
      path="session/update.update.sessionUpdate",
      value="future"
    ) => ()
    _ => fail("expected unknown session update discriminator")
  } noraise {
    _ => fail("expected unknown session update discriminator")
  }

  try
    session_info_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"cwd\":\"/workspace\",\"additionalDirectories\":null}",
      ),
      path="sessionInfo",
    )
  catch {
    InvalidField(path="sessionInfo.additionalDirectories", reason=_) => ()
    _ => fail("expected null additional directory rejection")
  } noraise {
    _ => fail("expected null additional directory rejection")
  }
}
