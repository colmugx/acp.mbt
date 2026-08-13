///|
/// Parameters for the Agent -> Client `fs/read_text_file` request.
pub(all) struct ReadTextFileParams {
  session_id : SessionId
  path : String
  line : ProtocolNullable[UInt64]
  limit : ProtocolNullable[UInt64]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of the Agent -> Client `fs/read_text_file` request.
pub(all) struct ReadTextFileResult {
  content : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for the Agent -> Client `fs/write_text_file` request.
pub(all) struct WriteTextFileParams {
  session_id : SessionId
  path : String
  content : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of the Agent -> Client `fs/write_text_file` request.
pub(all) struct WriteTextFileResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn fs_require_non_empty(
  value : String,
  path~ : String,
) -> String raise ProtocolDecodeError {
  if value == "" {
    raise InvalidField(path~, reason="string must not be empty")
  }
  value
}

///|
fn fs_decode_non_empty_string(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  fs_require_non_empty(protocol_decode_string(value, path~), path~)
}

///|
fn fs_decode_nullable_uint64(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[UInt64] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(protocol_decode_wire_uint64(value, path~))
  }
}

///|
fn fs_validate_read_window(
  line : ProtocolNullable[UInt64],
  path~ : String,
) -> ProtocolNullable[UInt64] raise ProtocolDecodeError {
  match line {
    Value(value) => {
      if value == 0 {
        raise InvalidField(path~, reason="line must be 1-based")
      }
      line
    }
    _ => line
  }
}

///|
fn fs_decode_read_text_file_params_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ReadTextFileParams raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["sessionId", "path", "line", "limit", "_meta"],
    prefix=path,
  )
  let session_id = fs_decode_non_empty_string(
    protocol_required(fields, "sessionId", path=path + ".sessionId"),
    path=path + ".sessionId",
  )
  let file_path = protocol_validate_absolute_path(
    fs_decode_non_empty_string(
      protocol_required(fields, "path", path=path + ".path"),
      path=path + ".path",
    ),
    field_path=path + ".path",
  )
  let line = fs_validate_read_window(
    fs_decode_nullable_uint64(fields, "line", path=path + ".line"),
    path=path + ".line",
  )
  let limit = fs_decode_nullable_uint64(fields, "limit", path=path + ".limit")
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, path: file_path, line, limit, meta }
}

///|
/// Decode `fs/read_text_file` parameters.
pub fn read_text_file_params_from_json(
  value : Json,
  path? : String = "fs/read_text_file",
) -> ReadTextFileParams raise ProtocolDecodeError {
  fs_decode_read_text_file_params_fields(
    protocol_require_object(value, path~),
    path~,
  )
}

///|
/// Encode `fs/read_text_file` parameters.
pub fn read_text_file_params_to_json(
  value : ReadTextFileParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(
    fs_require_non_empty(value.session_id, path="sessionId"),
  )
  fields["path"] = Json::string(
    protocol_validate_absolute_path(
      fs_require_non_empty(value.path, path="path"),
      field_path="path",
    ),
  )
  let line = fs_validate_read_window(value.line, path="line")
  protocol_put_nullable(fields, "line", line, protocol_encode_uint64)
  protocol_put_nullable(fields, "limit", value.limit, protocol_encode_uint64)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `fs/read_text_file`.
pub fn read_text_file_result_from_json(
  value : Json,
  path? : String = "fs/read_text_file",
) -> ReadTextFileResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["content", "_meta"], prefix=path)
  let content = protocol_required_string(
    fields,
    "content",
    path=path + ".content",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { content, meta }
}

///|
/// Encode the result of `fs/read_text_file`.
pub fn read_text_file_result_to_json(
  value : ReadTextFileResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["content"] = Json::string(value.content)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode `fs/write_text_file` parameters.
pub fn write_text_file_params_from_json(
  value : Json,
  path? : String = "fs/write_text_file",
) -> WriteTextFileParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessionId", "path", "content", "_meta"],
    prefix=path,
  )
  let session_id = fs_decode_non_empty_string(
    protocol_required(fields, "sessionId", path=path + ".sessionId"),
    path=path + ".sessionId",
  )
  let file_path = protocol_validate_absolute_path(
    fs_decode_non_empty_string(
      protocol_required(fields, "path", path=path + ".path"),
      path=path + ".path",
    ),
    field_path=path + ".path",
  )
  let content = protocol_required_string(
    fields,
    "content",
    path=path + ".content",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, path: file_path, content, meta }
}

///|
/// Encode `fs/write_text_file` parameters.
pub fn write_text_file_params_to_json(
  value : WriteTextFileParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(
    fs_require_non_empty(value.session_id, path="sessionId"),
  )
  fields["path"] = Json::string(
    protocol_validate_absolute_path(
      fs_require_non_empty(value.path, path="path"),
      field_path="path",
    ),
  )
  fields["content"] = Json::string(value.content)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `fs/write_text_file`.
pub fn write_text_file_result_from_json(
  value : Json,
  path? : String = "fs/write_text_file",
) -> WriteTextFileResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta"], prefix=path)
  let meta = protocol_meta(fields, path=path + "._meta")
  { meta, }
}

///|
/// Encode the result of `fs/write_text_file`.
pub fn write_text_file_result_to_json(
  value : WriteTextFileResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
