///|
/// Parameters for `session/list`.
pub(all) struct ListSessionsParams {
  cwd : ProtocolNullable[String]
  cursor : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/list`.
pub(all) struct ListSessionsResult {
  sessions : Array[SessionInfo]
  next_cursor : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `session/delete`.
pub(all) struct DeleteSessionParams {
  session_id : SessionId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/delete`.
pub(all) struct DeleteSessionResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `session/close`.
pub(all) struct CloseSessionParams {
  session_id : SessionId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/close`.
pub(all) struct CloseSessionResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for the `session/cancel` notification.
pub(all) struct CancelParams {
  session_id : SessionId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for the `session/update` notification.
pub(all) struct SessionUpdateParams {
  session_id : SessionId
  update : SessionUpdate
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn session_lifecycle_decode_nullable_cwd(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[String] raise ProtocolDecodeError {
  match protocol_field(fields, "cwd") {
    Omitted => Omitted
    Null => Null
    Value(value) => {
      let cwd = protocol_decode_string(value, path~)
      Value(protocol_validate_absolute_path(cwd, field_path=path))
    }
  }
}

///|
fn session_lifecycle_put_nullable_cwd(
  fields : Map[String, Json],
  value : ProtocolNullable[String],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields["cwd"] = Json::null()
    Value(value) =>
      fields["cwd"] = Json::string(
        protocol_validate_absolute_path(value, field_path="cwd"),
      )
  }
}

///|
fn session_lifecycle_decode_sessions(
  value : Json,
  path~ : String,
) -> Array[SessionInfo] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[SessionInfo] = []
  for index, value in values {
    result.push(
      session_info_from_json(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn session_lifecycle_encode_sessions(
  values : Array[SessionInfo],
) -> Json raise ProtocolDecodeError {
  let result : Array[Json] = []
  for value in values {
    result.push(session_info_to_json(value))
  }
  Json::array(result)
}

///|
fn session_lifecycle_decode_meta_only(
  value : Json,
  path~ : String,
) -> ProtocolNullable[Json] raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta"], prefix=path)
  protocol_meta(fields, path=path + "._meta")
}

///|
/// Decode `session/list` parameters.
pub fn list_sessions_params_from_json(
  value : Json,
  path? : String = "session/list",
) -> ListSessionsParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["cwd", "cursor", "_meta"], prefix=path)
  let cwd = session_lifecycle_decode_nullable_cwd(fields, path=path + ".cwd")
  let cursor = protocol_nullable_string(fields, "cursor", path=path + ".cursor")
  let meta = protocol_meta(fields, path=path + "._meta")
  { cwd, cursor, meta }
}

///|
/// Encode `session/list` parameters.
pub fn list_sessions_params_to_json(
  value : ListSessionsParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  session_lifecycle_put_nullable_cwd(fields, value.cwd)
  protocol_put_nullable(fields, "cursor", value.cursor, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/list`.
pub fn list_sessions_result_from_json(
  value : Json,
  path? : String = "session/list",
) -> ListSessionsResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessions", "nextCursor", "_meta"],
    prefix=path,
  )
  let sessions = session_lifecycle_decode_sessions(
    protocol_required(fields, "sessions", path=path + ".sessions"),
    path=path + ".sessions",
  )
  let next_cursor = protocol_nullable_string(
    fields,
    "nextCursor",
    path=path + ".nextCursor",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { sessions, next_cursor, meta }
}

///|
/// Encode the result of `session/list`.
pub fn list_sessions_result_to_json(
  value : ListSessionsResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessions"] = session_lifecycle_encode_sessions(value.sessions)
  protocol_put_nullable(fields, "nextCursor", value.next_cursor, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode `session/delete` parameters.
pub fn delete_session_params_from_json(
  value : Json,
  path? : String = "session/delete",
) -> DeleteSessionParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["sessionId", "_meta"], prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, meta }
}

///|
/// Encode `session/delete` parameters.
pub fn delete_session_params_to_json(
  value : DeleteSessionParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/delete`.
pub fn delete_session_result_from_json(
  value : Json,
  path? : String = "session/delete",
) -> DeleteSessionResult raise ProtocolDecodeError {
  { meta: session_lifecycle_decode_meta_only(value, path~) }
}

///|
/// Encode the result of `session/delete`.
pub fn delete_session_result_to_json(
  value : DeleteSessionResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode `session/close` parameters.
pub fn close_session_params_from_json(
  value : Json,
  path? : String = "session/close",
) -> CloseSessionParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["sessionId", "_meta"], prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, meta }
}

///|
/// Encode `session/close` parameters.
pub fn close_session_params_to_json(
  value : CloseSessionParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/close`.
pub fn close_session_result_from_json(
  value : Json,
  path? : String = "session/close",
) -> CloseSessionResult raise ProtocolDecodeError {
  { meta: session_lifecycle_decode_meta_only(value, path~) }
}

///|
/// Encode the result of `session/close`.
pub fn close_session_result_to_json(
  value : CloseSessionResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode `session/cancel` notification parameters.
pub fn cancel_params_from_json(
  value : Json,
  path? : String = "session/cancel",
) -> CancelParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["sessionId", "_meta"], prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, meta }
}

///|
/// Encode `session/cancel` notification parameters.
pub fn cancel_params_to_json(
  value : CancelParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode `session/update` notification parameters.
pub fn session_update_params_from_json(
  value : Json,
  path? : String = "session/update",
) -> SessionUpdateParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["sessionId", "update", "_meta"], prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let update = session_update_from_json(
    protocol_required(fields, "update", path=path + ".update"),
    path=path + ".update",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, update, meta }
}

///|
/// Encode `session/update` notification parameters.
pub fn session_update_params_to_json(
  value : SessionUpdateParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["update"] = session_update_to_json(value.update)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
