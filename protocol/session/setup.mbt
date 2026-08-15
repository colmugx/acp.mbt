///|

///|
/// Parameters for `session/new`.
pub(all) struct NewSessionParams {
  cwd : String
  additional_directories : ProtocolNullable[Array[String]]
  mcp_servers : Array[McpServer]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/new`.
pub(all) struct NewSessionResult {
  session_id : SessionId
  modes : ProtocolNullable[SessionModeState]
  config_options : ProtocolNullable[Array[SessionConfigOption]]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `session/load`.
pub(all) struct LoadSessionParams {
  mcp_servers : Array[McpServer]
  cwd : String
  additional_directories : ProtocolNullable[Array[String]]
  session_id : SessionId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/load`.
///
/// The runtime must replay the restored history after this result is accepted.
/// The codec deliberately carries no storage or replay state.
pub(all) struct LoadSessionResult {
  modes : ProtocolNullable[SessionModeState]
  config_options : ProtocolNullable[Array[SessionConfigOption]]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `session/resume`.
pub(all) struct ResumeSessionParams {
  session_id : SessionId
  cwd : String
  additional_directories : ProtocolNullable[Array[String]]
  mcp_servers : ProtocolNullable[Array[McpServer]]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/resume`.
///
/// Unlike `LoadSessionResult`, accepting this result must not replay history.
/// The distinction is represented by the wire type and not by hidden state.
pub(all) struct ResumeSessionResult {
  modes : ProtocolNullable[SessionModeState]
  config_options : ProtocolNullable[Array[SessionConfigOption]]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Validate the session id of a `session/new` result in both directions.
/// Uniqueness is owned by the session service; the codec only rejects the
/// degenerate empty id that can never address a session.
fn session_setup_session_id(
  value : String,
  field_path~ : String,
) -> String raise ProtocolDecodeError {
  if value == "" {
    raise InvalidField(path=field_path, reason="sessionId must not be empty")
  }
  value
}

///|
fn session_setup_decode_absolute_string_array(
  value : Json,
  path~ : String,
) -> Array[String] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[String] = []
  for index, value in values {
    let item_path = path + "[" + index.to_string() + "]"
    let item = protocol_decode_string(value, path=item_path)
    result.push(protocol_validate_absolute_path(item, field_path=item_path))
  }
  result
}

///|
fn session_setup_decode_additional_directories(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[Array[String]] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null =>
      raise InvalidField(
        path~,
        reason="additionalDirectories must be an array when present",
      )
    Value(value) =>
      Value(session_setup_decode_absolute_string_array(value, path~))
  }
}

///|
fn session_setup_put_additional_directories(
  fields : Map[String, Json],
  key : String,
  value : ProtocolNullable[Array[String]],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null =>
      raise InvalidField(
        path=key,
        reason="additionalDirectories must be an array when present",
      )
    Value(values) => {
      let encoded : Array[Json] = []
      for value in values {
        encoded.push(
          Json::string(protocol_validate_absolute_path(value, field_path=key)),
        )
      }
      fields[key] = Json::array(encoded)
    }
  }
}

///|
fn session_setup_decode_mcp_servers(
  value : Json,
  path~ : String,
) -> Array[McpServer] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[McpServer] = []
  for index, value in values {
    result.push(
      mcp_server_from_json(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn session_setup_encode_mcp_servers(
  values : Array[McpServer],
) -> Json raise ProtocolDecodeError {
  let result : Array[Json] = []
  for value in values {
    result.push(mcp_server_to_json(value))
  }
  Json::array(result)
}

///|
fn session_setup_decode_config_options(
  value : Json,
  path~ : String,
) -> Array[SessionConfigOption] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[SessionConfigOption] = []
  for index, value in values {
    result.push(
      session_config_option_from_json(
        value,
        path=path + "[" + index.to_string() + "]",
      ),
    )
  }
  result
}

///|
fn session_setup_encode_config_options(
  values : Array[SessionConfigOption],
) -> Json raise ProtocolDecodeError {
  let result : Array[Json] = []
  for value in values {
    result.push(session_config_option_to_json(value))
  }
  Json::array(result)
}

///|
fn session_setup_decode_modes(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[SessionModeState] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(session_mode_state_from_json(value, path~))
  }
}

///|
fn session_setup_decode_config_options_nullable(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[Array[SessionConfigOption]] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(session_setup_decode_config_options(value, path~))
  }
}

///|
fn session_setup_put_modes(
  fields : Map[String, Json],
  key : String,
  value : ProtocolNullable[SessionModeState],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields[key] = Json::null()
    Value(value) => fields[key] = session_mode_state_to_json(value)
  }
}

///|
fn session_setup_put_config_options(
  fields : Map[String, Json],
  key : String,
  value : ProtocolNullable[Array[SessionConfigOption]],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields[key] = Json::null()
    Value(value) => fields[key] = session_setup_encode_config_options(value)
  }
}

///|
fn session_setup_decode_new_params_fields(
  fields : Map[String, Json],
  path~ : String,
) -> NewSessionParams raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["cwd", "additionalDirectories", "mcpServers", "_meta"],
    prefix=path,
  )
  let cwd = protocol_validate_absolute_path(
    protocol_required_string(fields, "cwd", path=path + ".cwd"),
    field_path=path + ".cwd",
  )
  let additional_directories = session_setup_decode_additional_directories(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
  )
  let mcp_servers = session_setup_decode_mcp_servers(
    protocol_required(fields, "mcpServers", path=path + ".mcpServers"),
    path=path + ".mcpServers",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { cwd, additional_directories, mcp_servers, meta }
}

///|
/// Decode `session/new` parameters.
pub fn new_session_params_from_json(
  value : Json,
  path? : String = "session/new",
) -> NewSessionParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  session_setup_decode_new_params_fields(fields, path~)
}

///|
/// Encode `session/new` parameters.
pub fn new_session_params_to_json(
  value : NewSessionParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["cwd"] = Json::string(
    protocol_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  session_setup_put_additional_directories(
    fields,
    "additionalDirectories",
    value.additional_directories,
  )
  fields["mcpServers"] = session_setup_encode_mcp_servers(value.mcp_servers)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn session_setup_decode_load_params_fields(
  fields : Map[String, Json],
  path~ : String,
) -> LoadSessionParams raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["mcpServers", "cwd", "additionalDirectories", "sessionId", "_meta"],
    prefix=path,
  )
  let mcp_servers = session_setup_decode_mcp_servers(
    protocol_required(fields, "mcpServers", path=path + ".mcpServers"),
    path=path + ".mcpServers",
  )
  let cwd = protocol_validate_absolute_path(
    protocol_required_string(fields, "cwd", path=path + ".cwd"),
    field_path=path + ".cwd",
  )
  let additional_directories = session_setup_decode_additional_directories(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
  )
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { mcp_servers, cwd, additional_directories, session_id, meta }
}

///|
/// Decode `session/load` parameters.
pub fn load_session_params_from_json(
  value : Json,
  path? : String = "session/load",
) -> LoadSessionParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  session_setup_decode_load_params_fields(fields, path~)
}

///|
/// Encode `session/load` parameters.
pub fn load_session_params_to_json(
  value : LoadSessionParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["mcpServers"] = session_setup_encode_mcp_servers(value.mcp_servers)
  fields["cwd"] = Json::string(
    protocol_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  session_setup_put_additional_directories(
    fields,
    "additionalDirectories",
    value.additional_directories,
  )
  fields["sessionId"] = Json::string(value.session_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn session_setup_decode_resume_params_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ResumeSessionParams raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["sessionId", "cwd", "additionalDirectories", "mcpServers", "_meta"],
    prefix=path,
  )
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let cwd = protocol_validate_absolute_path(
    protocol_required_string(fields, "cwd", path=path + ".cwd"),
    field_path=path + ".cwd",
  )
  let additional_directories = session_setup_decode_additional_directories(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
  )
  let mcp_servers : ProtocolNullable[Array[McpServer]] = match
    protocol_field(fields, "mcpServers") {
    Omitted => Omitted
    Null =>
      raise InvalidField(
        path=path + ".mcpServers",
        reason="mcpServers must be an array when present",
      )
    Value(value) =>
      Value(session_setup_decode_mcp_servers(value, path=path + ".mcpServers"))
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, cwd, additional_directories, mcp_servers, meta }
}

///|
/// Decode `session/resume` parameters.
pub fn resume_session_params_from_json(
  value : Json,
  path? : String = "session/resume",
) -> ResumeSessionParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  session_setup_decode_resume_params_fields(fields, path~)
}

///|
/// Encode `session/resume` parameters.
pub fn resume_session_params_to_json(
  value : ResumeSessionParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["cwd"] = Json::string(
    protocol_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  session_setup_put_additional_directories(
    fields,
    "additionalDirectories",
    value.additional_directories,
  )
  match value.mcp_servers {
    Omitted => ()
    Null =>
      raise InvalidField(
        path="mcpServers",
        reason="mcpServers must be an array when present",
      )
    Value(value) =>
      fields["mcpServers"] = session_setup_encode_mcp_servers(value)
  }
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn session_setup_decode_new_result_fields(
  fields : Map[String, Json],
  path~ : String,
) -> NewSessionResult raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["sessionId", "modes", "configOptions", "_meta"],
    prefix=path,
  )
  let session_id = session_setup_session_id(
    protocol_required_string(fields, "sessionId", path=path + ".sessionId"),
    field_path=path + ".sessionId",
  )
  let modes = session_setup_decode_modes(fields, "modes", path=path + ".modes")
  let config_options = session_setup_decode_config_options_nullable(
    fields,
    "configOptions",
    path=path + ".configOptions",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, modes, config_options, meta }
}

///|
/// Decode the result of `session/new`.
pub fn new_session_result_from_json(
  value : Json,
  path? : String = "session/new",
) -> NewSessionResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  session_setup_decode_new_result_fields(fields, path~)
}

///|
/// Encode the result of `session/new`.
pub fn new_session_result_to_json(
  value : NewSessionResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(
    session_setup_session_id(value.session_id, field_path="sessionId"),
  )
  session_setup_put_modes(fields, "modes", value.modes)
  session_setup_put_config_options(
    fields,
    "configOptions",
    value.config_options,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn session_setup_decode_load_result_fields(
  fields : Map[String, Json],
  path~ : String,
) -> LoadSessionResult raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["modes", "configOptions", "_meta"],
    prefix=path,
  )
  let modes = session_setup_decode_modes(fields, "modes", path=path + ".modes")
  let config_options = session_setup_decode_config_options_nullable(
    fields,
    "configOptions",
    path=path + ".configOptions",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { modes, config_options, meta }
}

///|
/// Decode the result of `session/load`.
pub fn load_session_result_from_json(
  value : Json,
  path? : String = "session/load",
) -> LoadSessionResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  session_setup_decode_load_result_fields(fields, path~)
}

///|
/// Encode the result of `session/load`.
pub fn load_session_result_to_json(
  value : LoadSessionResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  session_setup_put_modes(fields, "modes", value.modes)
  session_setup_put_config_options(
    fields,
    "configOptions",
    value.config_options,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/resume`.
pub fn resume_session_result_from_json(
  value : Json,
  path? : String = "session/resume",
) -> ResumeSessionResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["modes", "configOptions", "_meta"],
    prefix=path,
  )
  let modes = session_setup_decode_modes(fields, "modes", path=path + ".modes")
  let config_options = session_setup_decode_config_options_nullable(
    fields,
    "configOptions",
    path=path + ".configOptions",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { modes, config_options, meta }
}

///|
/// Encode the result of `session/resume`.
pub fn resume_session_result_to_json(
  value : ResumeSessionResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  session_setup_put_modes(fields, "modes", value.modes)
  session_setup_put_config_options(
    fields,
    "configOptions",
    value.config_options,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
