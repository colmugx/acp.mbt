///|
using @protocol {
  type ProtocolNullable,
  type ProtocolDecodeError,
  type ContentBlock,
  type McpServer,
  type SessionConfigId,
  type SessionConfigValueId,
  type SessionConfigOption,
  type SessionId,
  type SessionModeId,
  type SessionInfo,
  type SessionUpdate,
  protocol_field,
  protocol_require_object,
  protocol_require_array,
  protocol_required,
  protocol_required_string,
  protocol_decode_string,
  protocol_decode_boolean,
  protocol_nullable_string,
  protocol_meta,
  protocol_put_nullable,
  protocol_put_meta,
  protocol_reject_unknown,
  protocol_validate_absolute_path,
  content_block_from_json,
  content_block_to_json,
  mcp_server_from_json,
  mcp_server_to_json,
  session_config_option_from_json,
  session_config_option_to_json,
  session_info_from_json,
  session_info_to_json,
  session_update_from_json,
  session_update_to_json,
}

///|
/// One mode available for a session.
pub(all) struct SessionMode {
  id : SessionModeId
  name : String
  description : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The current mode and the complete set of modes available to a session.
pub(all) struct SessionModeState {
  current_mode_id : SessionModeId
  available_modes : Array[SessionMode]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// A value accepted by `session/set_config_option`.
pub(all) enum SessionConfigValue {
  Boolean(Bool)
  ValueId(SessionConfigValueId)
} derive(Eq, Debug)

///|
/// Parameters for `session/set_mode`.
pub(all) struct SetSessionModeParams {
  session_id : SessionId
  mode_id : SessionModeId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/set_mode`.
pub(all) struct SetSessionModeResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `session/set_config_option`.
pub(all) struct SetSessionConfigOptionParams {
  session_id : SessionId
  config_id : SessionConfigId
  value : SessionConfigValue
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/set_config_option`.
pub(all) struct SetSessionConfigOptionResult {
  config_options : Array[SessionConfigOption]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn session_config_decode_modes(
  value : Json,
  path~ : String,
) -> Array[SessionMode] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[SessionMode] = []
  for index, value in values {
    result.push(
      session_mode_from_json(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn session_config_encode_modes(
  values : Array[SessionMode],
) -> Json raise ProtocolDecodeError {
  let result : Array[Json] = []
  for value in values {
    result.push(session_mode_to_json(value))
  }
  Json::array(result)
}

///|
/// Decode one session mode.
pub fn session_mode_from_json(
  value : Json,
  path? : String = "mode",
) -> SessionMode raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["id", "name", "description", "_meta"],
    prefix=path,
  )
  let id = protocol_required_string(fields, "id", path=path + ".id")
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let description = protocol_nullable_string(
    fields,
    "description",
    path=path + ".description",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { id, name, description, meta, }
}

///|
/// Encode one session mode.
pub fn session_mode_to_json(
  value : SessionMode,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json::string(value.id)
  fields["name"] = Json::string(value.name)
  protocol_put_nullable(fields, "description", value.description, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Fail fast when a mode state names a current mode that is not available.
/// Which modes exist is service-owned; the codec only enforces that the state
/// an endpoint emits or accepts is internally consistent, so an unknown
/// modeId can never become a silent default current mode.
fn session_config_validate_current_mode(
  state : SessionModeState,
  field_path~ : String,
) -> Unit raise ProtocolDecodeError {
  for mode in state.available_modes {
    if mode.id == state.current_mode_id {
      return
    }
  }
  raise InvalidField(
    path=field_path,
    reason="currentModeId must reference one of availableModes",
  )
}

///|
/// Decode the mode state returned by session lifecycle methods.
pub fn session_mode_state_from_json(
  value : Json,
  path? : String = "modes",
) -> SessionModeState raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["currentModeId", "availableModes", "_meta"],
    prefix=path,
  )
  let current_mode_id = protocol_required_string(
    fields,
    "currentModeId",
    path=path + ".currentModeId",
  )
  let available_modes = session_config_decode_modes(
    protocol_required(fields, "availableModes", path=path + ".availableModes"),
    path=path + ".availableModes",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  let state : SessionModeState = { current_mode_id, available_modes, meta, }
  session_config_validate_current_mode(
    state,
    field_path=path + ".currentModeId",
  )
  state
}

///|
/// Encode the mode state returned by session lifecycle methods.
pub fn session_mode_state_to_json(
  value : SessionModeState,
) -> Json raise ProtocolDecodeError {
  session_config_validate_current_mode(value, field_path="currentModeId")
  let fields : Map[String, Json] = Map([])
  fields["currentModeId"] = Json::string(value.current_mode_id)
  fields["availableModes"] = session_config_encode_modes(value.available_modes)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn session_config_decode_options(
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
fn session_config_encode_options(
  values : Array[SessionConfigOption],
) -> Json raise ProtocolDecodeError {
  let result : Array[Json] = []
  for value in values {
    result.push(session_config_option_to_json(value))
  }
  Json::array(result)
}

///|
/// Decode `session/set_mode` parameters.
pub fn set_session_mode_params_from_json(
  value : Json,
  path? : String = "session/set_mode",
) -> SetSessionModeParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["sessionId", "modeId", "_meta"], prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let mode_id = protocol_required_string(
    fields,
    "modeId",
    path=path + ".modeId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, mode_id, meta, }
}

///|
/// Encode `session/set_mode` parameters.
pub fn set_session_mode_params_to_json(
  value : SetSessionModeParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["modeId"] = Json::string(value.mode_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/set_mode`.
pub fn set_session_mode_result_from_json(
  value : Json,
  path? : String = "session/set_mode",
) -> SetSessionModeResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta"], prefix=path)
  let meta = protocol_meta(fields, path=path + "._meta")
  { meta, }
}

///|
/// Encode the result of `session/set_mode`.
pub fn set_session_mode_result_to_json(
  value : SetSessionModeResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn session_config_value_from_fields(
  fields : Map[String, Json],
  path~ : String,
) -> SessionConfigValue raise ProtocolDecodeError {
  let value_path = path + ".value"
  match fields.get("type") {
    None =>
      ValueId(
        protocol_decode_string(
          protocol_required(fields, "value", path=value_path),
          path=value_path,
        ),
      )
    Some(String("boolean")) =>
      Boolean(
        protocol_decode_boolean(
          protocol_required(fields, "value", path=value_path),
          path=value_path,
        ),
      )
    Some(String(other)) =>
      raise InvalidDiscriminator(path=path + ".type", value=other)
    Some(_) => raise ExpectedString(path=path + ".type")
  }
}

///|
fn session_config_value_to_fields(
  fields : Map[String, Json],
  value : SessionConfigValue,
) -> Unit {
  match value {
    Boolean(value) => {
      fields["type"] = Json::string("boolean")
      fields["value"] = Json::boolean(value)
    }
    ValueId(value) => fields["value"] = Json::string(value)
  }
}

///|
/// Decode `session/set_config_option` parameters.
pub fn set_session_config_option_params_from_json(
  value : Json,
  path? : String = "session/set_config_option",
) -> SetSessionConfigOptionParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let config_value = session_config_value_from_fields(fields, path~)
  let allowed = match config_value {
    Boolean(_) => ["sessionId", "configId", "type", "value", "_meta"]
    ValueId(_) => ["sessionId", "configId", "value", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let config_id = protocol_required_string(
    fields,
    "configId",
    path=path + ".configId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, config_id, value: config_value, meta, }
}

///|
/// Encode `session/set_config_option` parameters.
pub fn set_session_config_option_params_to_json(
  value : SetSessionConfigOptionParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["configId"] = Json::string(value.config_id)
  session_config_value_to_fields(fields, value.value)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/set_config_option`.
pub fn set_session_config_option_result_from_json(
  value : Json,
  path? : String = "session/set_config_option",
) -> SetSessionConfigOptionResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["configOptions", "_meta"], prefix=path)
  let config_options = session_config_decode_options(
    protocol_required(fields, "configOptions", path=path + ".configOptions"),
    path=path + ".configOptions",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { config_options, meta, }
}

///|
/// Encode the result of `session/set_config_option`.
pub fn set_session_config_option_result_to_json(
  value : SetSessionConfigOptionResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["configOptions"] = session_config_encode_options(value.config_options)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
