///|
fn experimental_v2_decode_absolute_paths(
  value : Json,
  path~ : String,
) -> Array[String] raise ExperimentalV2DecodeError {
  experimental_v2_decode_array(value, path~, (item, item_path) => {
    experimental_v2_validate_absolute_path(
      experimental_v2_decode_string(item, path=item_path),
      field_path=item_path,
    )
  })
}

///|
fn experimental_v2_encode_absolute_paths(
  values : Array[String],
  key~ : String,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_array(values, value => {
    Json::string(experimental_v2_validate_absolute_path(value, field_path=key))
  })
}

///|
/// Known payload of a `ReplayFrom` cursor with the `type: "start"`
/// discriminator: replay the whole conversation.
pub(all) struct ExperimentalV2ReplayFromStart {
  meta : Json?
} derive(Eq, Debug)

///|
/// Inclusive replay cursor of `session/resume`.  The schema has an open
/// fallback: unknown cursors stay as `Extension`/`Future` raw payloads so a
/// receiver can reject rather than guess.
pub type ExperimentalV2ReplayFrom = ExperimentalV2Open[
  ExperimentalV2ReplayFromStart,
]

///|
pub fn experimental_v2_decode_replay_from(
  value : Json,
  path? : String = "replayFrom",
) -> ExperimentalV2ReplayFrom raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["start"],
    (_, payload) => {
      let fields = experimental_v2_require_object(payload, path~)
      experimental_v2_reject_unknown(fields, ["type", "_meta"], prefix=path)
      { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_replay_from(
  value : ExperimentalV2ReplayFrom,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    let fields : Map[String, Json] = Map([])
    fields["type"] = Json::string("start")
    experimental_v2_put_meta(fields, known.meta)
    Json::object(fields)
  })
}

///|
/// Parameters of `session/new`.  `additional_directories` is the complete
/// additional-root list; omitted or empty activates none.
pub(all) struct ExperimentalV2NewSessionParams {
  cwd : String
  additional_directories : Array[String]?
  mcp_servers : Array[ExperimentalV2McpServer]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_new_session_params(
  value : Json,
  path? : String = "session/new",
) -> ExperimentalV2NewSessionParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "cwd", "additionalDirectories", "mcpServers"],
    prefix=path,
  )
  let cwd = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "cwd", path=path + ".cwd"),
      path=path + ".cwd",
    ),
    field_path=path + ".cwd",
  )
  let additional_directories = experimental_v2_decode_optional(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
    (value, path) => experimental_v2_decode_absolute_paths(value, path~),
  )
  let mcp_servers = experimental_v2_decode_optional(
    fields,
    "mcpServers",
    path=path + ".mcpServers",
    (value, path) => experimental_v2_decode_mcp_servers(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { cwd, additional_directories, mcp_servers, meta }
}

///|
pub fn experimental_v2_encode_new_session_params(
  value : ExperimentalV2NewSessionParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["cwd"] = Json::string(
    experimental_v2_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  experimental_v2_put_optional(
    fields,
    "additionalDirectories",
    value.additional_directories,
    values => {
      experimental_v2_encode_absolute_paths(values, key="additionalDirectories")
    },
  )
  experimental_v2_put_optional(
    fields,
    "mcpServers",
    value.mcp_servers,
    experimental_v2_encode_mcp_servers,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `session/new`.
pub(all) struct ExperimentalV2NewSessionResult {
  session_id : String
  config_options : Array[ExperimentalV2SessionConfigOption]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_new_session_result(
  value : Json,
  path? : String = "session/new",
) -> ExperimentalV2NewSessionResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "sessionId", "configOptions"],
    prefix=path,
  )
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let config_options = experimental_v2_decode_optional(
    fields,
    "configOptions",
    path=path + ".configOptions",
    (value, path) => experimental_v2_decode_config_options(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, config_options, meta }
}

///|
pub fn experimental_v2_encode_new_session_result(
  value : ExperimentalV2NewSessionResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  experimental_v2_put_optional(
    fields,
    "configOptions",
    value.config_options,
    experimental_v2_encode_config_options,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of `session/resume`.  `additional_directories` is the complete
/// resulting additional-root list and may differ from any previously reported
/// list as long as `cwd` matches the session's.
pub(all) struct ExperimentalV2ResumeSessionParams {
  session_id : String
  cwd : String
  additional_directories : Array[String]?
  mcp_servers : Array[ExperimentalV2McpServer]?
  replay_from : ExperimentalV2ReplayFrom?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_resume_session_params(
  value : Json,
  path? : String = "session/resume",
) -> ExperimentalV2ResumeSessionParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    [
      "_meta", "sessionId", "cwd", "additionalDirectories", "mcpServers", "replayFrom",
    ],
    prefix=path,
  )
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let cwd = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "cwd", path=path + ".cwd"),
      path=path + ".cwd",
    ),
    field_path=path + ".cwd",
  )
  let additional_directories = experimental_v2_decode_optional(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
    (value, path) => experimental_v2_decode_absolute_paths(value, path~),
  )
  let mcp_servers = experimental_v2_decode_optional(
    fields,
    "mcpServers",
    path=path + ".mcpServers",
    (value, path) => experimental_v2_decode_mcp_servers(value, path~),
  )
  let replay_from = experimental_v2_decode_optional(
    fields,
    "replayFrom",
    path=path + ".replayFrom",
    (value, path) => experimental_v2_decode_replay_from(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, cwd, additional_directories, mcp_servers, replay_from, meta }
}

///|
pub fn experimental_v2_encode_resume_session_params(
  value : ExperimentalV2ResumeSessionParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["cwd"] = Json::string(
    experimental_v2_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  experimental_v2_put_optional(
    fields,
    "additionalDirectories",
    value.additional_directories,
    values => {
      experimental_v2_encode_absolute_paths(values, key="additionalDirectories")
    },
  )
  experimental_v2_put_optional(
    fields,
    "mcpServers",
    value.mcp_servers,
    experimental_v2_encode_mcp_servers,
  )
  experimental_v2_put_optional(
    fields,
    "replayFrom",
    value.replay_from,
    experimental_v2_encode_replay_from,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `session/resume`.  Accepting it must not replay history; replay
/// is requested by `replayFrom` in the params.
pub(all) struct ExperimentalV2ResumeSessionResult {
  config_options : Array[ExperimentalV2SessionConfigOption]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_resume_session_result(
  value : Json,
  path? : String = "session/resume",
) -> ExperimentalV2ResumeSessionResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "configOptions"],
    prefix=path,
  )
  let config_options = experimental_v2_decode_optional(
    fields,
    "configOptions",
    path=path + ".configOptions",
    (value, path) => experimental_v2_decode_config_options(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { config_options, meta }
}

///|
pub fn experimental_v2_encode_resume_session_result(
  value : ExperimentalV2ResumeSessionResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(
    fields,
    "configOptions",
    value.config_options,
    experimental_v2_encode_config_options,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// One session entry returned by `session/list`.
pub(all) struct ExperimentalV2SessionInfo {
  session_id : String
  cwd : String
  additional_directories : Array[String]?
  title : String?
  updated_at : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_session_info(
  value : Json,
  path? : String = "sessionInfo",
) -> ExperimentalV2SessionInfo raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "sessionId", "cwd", "additionalDirectories", "title", "updatedAt"],
    prefix=path,
  )
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let cwd = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "cwd", path=path + ".cwd"),
      path=path + ".cwd",
    ),
    field_path=path + ".cwd",
  )
  let additional_directories = experimental_v2_decode_optional(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
    (value, path) => experimental_v2_decode_absolute_paths(value, path~),
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let updated_at = experimental_v2_decode_optional(
    fields,
    "updatedAt",
    path=path + ".updatedAt",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, cwd, additional_directories, title, updated_at, meta }
}

///|
pub fn experimental_v2_encode_session_info(
  value : ExperimentalV2SessionInfo,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["cwd"] = Json::string(
    experimental_v2_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  experimental_v2_put_optional(
    fields,
    "additionalDirectories",
    value.additional_directories,
    values => {
      experimental_v2_encode_absolute_paths(values, key="additionalDirectories")
    },
  )
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "updatedAt", value.updated_at, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of `session/list`.
pub(all) struct ExperimentalV2ListSessionsParams {
  cwd : String?
  cursor : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_list_sessions_params(
  value : Json,
  path? : String = "session/list",
) -> ExperimentalV2ListSessionsParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "cwd", "cursor"],
    prefix=path,
  )
  let cwd = experimental_v2_decode_optional(fields, "cwd", path=path + ".cwd", (
    value,
    path,
  ) => {
    experimental_v2_validate_absolute_path(
      experimental_v2_decode_string(value, path~),
      field_path=path,
    )
  })
  let cursor = experimental_v2_decode_optional(
    fields,
    "cursor",
    path=path + ".cursor",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { cwd, cursor, meta }
}

///|
pub fn experimental_v2_encode_list_sessions_params(
  value : ExperimentalV2ListSessionsParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "cwd", value.cwd, cwd => {
    Json::string(experimental_v2_validate_absolute_path(cwd, field_path="cwd"))
  })
  experimental_v2_put_optional(fields, "cursor", value.cursor, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `session/list`.
pub(all) struct ExperimentalV2ListSessionsResult {
  sessions : Array[ExperimentalV2SessionInfo]
  next_cursor : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_list_sessions_result(
  value : Json,
  path? : String = "session/list",
) -> ExperimentalV2ListSessionsResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "sessions", "nextCursor"],
    prefix=path,
  )
  let sessions = experimental_v2_decode_array(
    experimental_v2_required(fields, "sessions", path=path + ".sessions"),
    path=path + ".sessions",
    (item, item_path) => {
      experimental_v2_decode_session_info(item, path=item_path)
    },
  )
  let next_cursor = experimental_v2_decode_optional(
    fields,
    "nextCursor",
    path=path + ".nextCursor",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { sessions, next_cursor, meta }
}

///|
pub fn experimental_v2_encode_list_sessions_result(
  value : ExperimentalV2ListSessionsResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessions"] = experimental_v2_encode_array(
    value.sessions,
    experimental_v2_encode_session_info,
  )
  experimental_v2_put_optional(fields, "nextCursor", value.next_cursor, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of `session/delete`; gated by the `session.delete` capability.
pub(all) struct ExperimentalV2DeleteSessionParams {
  session_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_delete_session_params(
  value : Json,
  path? : String = "session/delete",
) -> ExperimentalV2DeleteSessionParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta", "sessionId"], prefix=path)
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, meta }
}

///|
pub fn experimental_v2_encode_delete_session_params(
  value : ExperimentalV2DeleteSessionParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `session/delete`; it carries only protocol metadata.
pub(all) struct ExperimentalV2DeleteSessionResult {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_delete_session_result(
  value : Json,
  path? : String = "session/delete",
) -> ExperimentalV2DeleteSessionResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
}

///|
pub fn experimental_v2_encode_delete_session_result(
  value : ExperimentalV2DeleteSessionResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of `session/close`; the Agent must cancel ongoing work for the
/// session before freeing its resources.
pub(all) struct ExperimentalV2CloseSessionParams {
  session_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_close_session_params(
  value : Json,
  path? : String = "session/close",
) -> ExperimentalV2CloseSessionParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta", "sessionId"], prefix=path)
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, meta }
}

///|
pub fn experimental_v2_encode_close_session_params(
  value : ExperimentalV2CloseSessionParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of `session/prompt`.  The baseline blocks `text` and
/// `resource_link` are always acceptable; the other block kinds are gated by
/// the agent's prompt capability markers at the endpoint layer.
pub(all) struct ExperimentalV2PromptParams {
  session_id : String
  prompt : Array[ExperimentalV2ContentBlock]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_prompt_params(
  value : Json,
  path? : String = "session/prompt",
) -> ExperimentalV2PromptParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "sessionId", "prompt"],
    prefix=path,
  )
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let prompt = experimental_v2_decode_array(
    experimental_v2_required(fields, "prompt", path=path + ".prompt"),
    path=path + ".prompt",
    (item, item_path) => {
      experimental_v2_decode_content_block(item, path=item_path)
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, prompt, meta }
}

///|
pub fn experimental_v2_encode_prompt_params(
  value : ExperimentalV2PromptParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["prompt"] = experimental_v2_encode_array(
    value.prompt,
    experimental_v2_encode_content_block,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Parameters of the `session/cancel` notification.
pub(all) struct ExperimentalV2CancelSessionParams {
  session_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_cancel_session_params(
  value : Json,
  path? : String = "session/cancel",
) -> ExperimentalV2CancelSessionParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta", "sessionId"], prefix=path)
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, meta }
}

///|
pub fn experimental_v2_encode_cancel_session_params(
  value : ExperimentalV2CancelSessionParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `session/close`; it carries only protocol metadata.
pub(all) struct ExperimentalV2CloseSessionResult {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_close_session_result(
  value : Json,
  path? : String = "session/close",
) -> ExperimentalV2CloseSessionResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
}

///|
pub fn experimental_v2_encode_close_session_result(
  value : ExperimentalV2CloseSessionResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
