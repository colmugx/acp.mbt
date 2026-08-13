///|
/// One environment variable for `terminal/create`.
pub(all) struct TerminalEnvVariable {
  name : String
  value : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `terminal/create`.
pub(all) struct TerminalCreateParams {
  session_id : SessionId
  command : String
  args : ProtocolNullable[Array[String]]
  env : ProtocolNullable[Array[TerminalEnvVariable]]
  cwd : ProtocolNullable[String]
  output_byte_limit : ProtocolNullable[UInt64]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `terminal/create`.
pub(all) struct TerminalCreateResult {
  terminal_id : TerminalId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `terminal/output`.
pub(all) struct TerminalOutputParams {
  session_id : SessionId
  terminal_id : TerminalId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Exit status shared by terminal output and runtime-independent terminal
/// results.  A normal exit supplies `exit_code`; signal termination supplies
/// `signal`.  The wire schema keeps both fields optional to preserve null and
/// omission exactly.
pub(all) struct TerminalExitStatus {
  exit_code : ProtocolNullable[UInt64]
  signal : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `terminal/output`.
pub(all) struct TerminalOutputResult {
  output : String
  truncated : Bool
  exit_status : ProtocolNullable[TerminalExitStatus]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `terminal/wait_for_exit`.
pub(all) struct TerminalWaitForExitParams {
  session_id : SessionId
  terminal_id : TerminalId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `terminal/wait_for_exit`.
pub(all) struct TerminalWaitForExitResult {
  exit_code : ProtocolNullable[UInt64]
  signal : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `terminal/kill`.
pub(all) struct TerminalKillParams {
  session_id : SessionId
  terminal_id : TerminalId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `terminal/kill`.
pub(all) struct TerminalKillResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for `terminal/release`.
pub(all) struct TerminalReleaseParams {
  session_id : SessionId
  terminal_id : TerminalId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `terminal/release`.
pub(all) struct TerminalReleaseResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn terminal_require_non_empty(
  value : String,
  path~ : String,
) -> String raise ProtocolDecodeError {
  if value == "" {
    raise InvalidField(path~, reason="string must not be empty")
  }
  value
}

///|
fn terminal_decode_non_empty_string(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  terminal_require_non_empty(protocol_decode_string(value, path~), path~)
}

///|
fn terminal_decode_string_array(
  value : Json,
  path~ : String,
) -> Array[String] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[String] = []
  for index, value in values {
    result.push(
      protocol_decode_string(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn terminal_encode_string_array(values : Array[String]) -> Json {
  Json::array(values.map(value => Json::string(value)))
}

///|
fn terminal_decode_env_variable(
  value : Json,
  path~ : String,
) -> TerminalEnvVariable raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["name", "value", "_meta"], prefix=path)
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let variable_value = protocol_required_string(
    fields,
    "value",
    path=path + ".value",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { name, value: variable_value, meta }
}

///|
fn terminal_decode_env_array(
  value : Json,
  path~ : String,
) -> Array[TerminalEnvVariable] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[TerminalEnvVariable] = []
  for index, value in values {
    result.push(
      terminal_decode_env_variable(
        value,
        path=path + "[" + index.to_string() + "]",
      ),
    )
  }
  result
}

///|
fn terminal_encode_env_variable(
  value : TerminalEnvVariable,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["value"] = Json::string(value.value)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn terminal_encode_env_array(
  values : Array[TerminalEnvVariable],
) -> Json raise ProtocolDecodeError {
  Json::array(values.map(value => terminal_encode_env_variable(value)))
}

///|
fn terminal_decode_nullable_args(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Array[String]] raise ProtocolDecodeError {
  match protocol_field(fields, "args") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(terminal_decode_string_array(value, path~))
  }
}

///|
fn terminal_decode_nullable_env(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Array[TerminalEnvVariable]] raise ProtocolDecodeError {
  match protocol_field(fields, "env") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(terminal_decode_env_array(value, path~))
  }
}

///|
fn terminal_decode_nullable_cwd(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[String] raise ProtocolDecodeError {
  match protocol_field(fields, "cwd") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(
        protocol_validate_absolute_path(
          terminal_decode_non_empty_string(value, path~),
          field_path=path,
        ),
      )
  }
}

///|
fn terminal_decode_nullable_uint64(
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
fn terminal_validate_exit_code(
  value : ProtocolNullable[UInt64],
  path~ : String,
) -> ProtocolNullable[UInt64] raise ProtocolDecodeError {
  match value {
    Value(value) => {
      if value > 4294967295UL {
        raise InvalidField(path~, reason="exitCode must fit uint32")
      }
      Value(value)
    }
    _ => value
  }
}

///|
fn terminal_decode_nullable_exit_code(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[UInt64] raise ProtocolDecodeError {
  terminal_validate_exit_code(
    terminal_decode_nullable_uint64(fields, "exitCode", path~),
    path~,
  )
}

///|
fn terminal_decode_exit_status(
  value : Json,
  path~ : String,
) -> TerminalExitStatus raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["exitCode", "signal", "_meta"], prefix=path)
  let exit_code = terminal_decode_nullable_exit_code(
    fields,
    path=path + ".exitCode",
  )
  let signal = protocol_nullable_string(fields, "signal", path=path + ".signal")
  let meta = protocol_meta(fields, path=path + "._meta")
  { exit_code, signal, meta }
}

///|
fn terminal_encode_exit_status(
  value : TerminalExitStatus,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  let exit_code = terminal_validate_exit_code(value.exit_code, path="exitCode")
  protocol_put_nullable(fields, "exitCode", exit_code, protocol_encode_uint64)
  protocol_put_nullable(fields, "signal", value.signal, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn terminal_decode_session_terminal(
  fields : Map[String, Json],
  path~ : String,
) -> (SessionId, TerminalId) raise ProtocolDecodeError {
  let session_id = terminal_decode_non_empty_string(
    protocol_required(fields, "sessionId", path=path + ".sessionId"),
    path=path + ".sessionId",
  )
  let terminal_id = terminal_decode_non_empty_string(
    protocol_required(fields, "terminalId", path=path + ".terminalId"),
    path=path + ".terminalId",
  )
  (session_id, terminal_id)
}

///|
fn terminal_encode_session_terminal(
  fields : Map[String, Json],
  session_id : SessionId,
  terminal_id : TerminalId,
) -> Unit raise ProtocolDecodeError {
  fields["sessionId"] = Json::string(
    terminal_require_non_empty(session_id, path="sessionId"),
  )
  fields["terminalId"] = Json::string(
    terminal_require_non_empty(terminal_id, path="terminalId"),
  )
}

///|
fn terminal_decode_empty_result(
  value : Json,
  path~ : String,
) -> ProtocolNullable[Json] raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta"], prefix=path)
  protocol_meta(fields, path=path + "._meta")
}

///|
fn terminal_encode_empty_result(
  meta : ProtocolNullable[Json],
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, meta)
  Json::object(fields)
}

///|
/// Decode `terminal/create` parameters.
pub fn terminal_create_params_from_json(
  value : Json,
  path? : String = "terminal/create",
) -> TerminalCreateParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessionId", "command", "args", "env", "cwd", "outputByteLimit", "_meta"],
    prefix=path,
  )
  let session_id = terminal_decode_non_empty_string(
    protocol_required(fields, "sessionId", path=path + ".sessionId"),
    path=path + ".sessionId",
  )
  let command = protocol_required_string(
    fields,
    "command",
    path=path + ".command",
  )
  let args = terminal_decode_nullable_args(fields, path=path + ".args")
  let env = terminal_decode_nullable_env(fields, path=path + ".env")
  let cwd = terminal_decode_nullable_cwd(fields, path=path + ".cwd")
  let output_byte_limit = terminal_decode_nullable_uint64(
    fields,
    "outputByteLimit",
    path=path + ".outputByteLimit",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, command, args, env, cwd, output_byte_limit, meta }
}

///|
/// Encode `terminal/create` parameters.
pub fn terminal_create_params_to_json(
  value : TerminalCreateParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(
    terminal_require_non_empty(value.session_id, path="sessionId"),
  )
  fields["command"] = Json::string(value.command)
  protocol_put_nullable(
    fields,
    "args",
    value.args,
    terminal_encode_string_array,
  )
  match value.env {
    Omitted => ()
    Null => fields["env"] = Json::null()
    Value(value) => fields["env"] = terminal_encode_env_array(value)
  }
  match value.cwd {
    Omitted => ()
    Null => fields["cwd"] = Json::null()
    Value(value) =>
      fields["cwd"] = Json::string(
        protocol_validate_absolute_path(
          terminal_require_non_empty(value, path="cwd"),
          field_path="cwd",
        ),
      )
  }
  protocol_put_nullable(
    fields,
    "outputByteLimit",
    value.output_byte_limit,
    protocol_encode_uint64,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `terminal/create`.
pub fn terminal_create_result_from_json(
  value : Json,
  path? : String = "terminal/create",
) -> TerminalCreateResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["terminalId", "_meta"], prefix=path)
  let terminal_id = terminal_decode_non_empty_string(
    protocol_required(fields, "terminalId", path=path + ".terminalId"),
    path=path + ".terminalId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { terminal_id, meta }
}

///|
/// Encode the result of `terminal/create`.
pub fn terminal_create_result_to_json(
  value : TerminalCreateResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["terminalId"] = Json::string(
    terminal_require_non_empty(value.terminal_id, path="terminalId"),
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode `terminal/output` parameters.
pub fn terminal_output_params_from_json(
  value : Json,
  path? : String = "terminal/output",
) -> TerminalOutputParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessionId", "terminalId", "_meta"],
    prefix=path,
  )
  let (session_id, terminal_id) = terminal_decode_session_terminal(
    fields,
    path~,
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, terminal_id, meta }
}

///|
/// Encode `terminal/output` parameters.
pub fn terminal_output_params_to_json(
  value : TerminalOutputParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  terminal_encode_session_terminal(fields, value.session_id, value.terminal_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `terminal/output`.
pub fn terminal_output_result_from_json(
  value : Json,
  path? : String = "terminal/output",
) -> TerminalOutputResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["output", "truncated", "exitStatus", "_meta"],
    prefix=path,
  )
  let output = protocol_required_string(fields, "output", path=path + ".output")
  let truncated = protocol_decode_boolean(
    protocol_required(fields, "truncated", path=path + ".truncated"),
    path=path + ".truncated",
  )
  let exit_status : ProtocolNullable[TerminalExitStatus] = match
    protocol_field(fields, "exitStatus") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(terminal_decode_exit_status(value, path=path + ".exitStatus"))
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { output, truncated, exit_status, meta }
}

///|
/// Encode the result of `terminal/output`.
pub fn terminal_output_result_to_json(
  value : TerminalOutputResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["output"] = Json::string(value.output)
  fields["truncated"] = Json::boolean(value.truncated)
  match value.exit_status {
    Omitted => ()
    Null => fields["exitStatus"] = Json::null()
    Value(value) => fields["exitStatus"] = terminal_encode_exit_status(value)
  }
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn terminal_decode_wait_params(
  value : Json,
  path~ : String,
) -> (SessionId, TerminalId, ProtocolNullable[Json]) raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessionId", "terminalId", "_meta"],
    prefix=path,
  )
  let (session_id, terminal_id) = terminal_decode_session_terminal(
    fields,
    path~,
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  (session_id, terminal_id, meta)
}

///|
fn terminal_encode_wait_params(
  session_id : SessionId,
  terminal_id : TerminalId,
  meta : ProtocolNullable[Json],
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  terminal_encode_session_terminal(fields, session_id, terminal_id)
  protocol_put_meta(fields, meta)
  Json::object(fields)
}

///|
/// Decode `terminal/wait_for_exit` parameters.
pub fn terminal_wait_for_exit_params_from_json(
  value : Json,
  path? : String = "terminal/wait_for_exit",
) -> TerminalWaitForExitParams raise ProtocolDecodeError {
  let (session_id, terminal_id, meta) = terminal_decode_wait_params(
    value,
    path~,
  )
  { session_id, terminal_id, meta }
}

///|
/// Encode `terminal/wait_for_exit` parameters.
pub fn terminal_wait_for_exit_params_to_json(
  value : TerminalWaitForExitParams,
) -> Json raise ProtocolDecodeError {
  terminal_encode_wait_params(value.session_id, value.terminal_id, value.meta)
}

///|
fn terminal_decode_exit_result_fields(
  value : Json,
  path~ : String,
) -> (
  ProtocolNullable[UInt64],
  ProtocolNullable[String],
  ProtocolNullable[Json],
) raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["exitCode", "signal", "_meta"], prefix=path)
  let exit_code = terminal_decode_nullable_exit_code(
    fields,
    path=path + ".exitCode",
  )
  let signal = protocol_nullable_string(fields, "signal", path=path + ".signal")
  let meta = protocol_meta(fields, path=path + "._meta")
  (exit_code, signal, meta)
}

///|
fn terminal_encode_exit_result(
  exit_code : ProtocolNullable[UInt64],
  signal : ProtocolNullable[String],
  meta : ProtocolNullable[Json],
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  let exit_code = terminal_validate_exit_code(exit_code, path="exitCode")
  protocol_put_nullable(fields, "exitCode", exit_code, protocol_encode_uint64)
  protocol_put_nullable(fields, "signal", signal, value => Json::string(value))
  protocol_put_meta(fields, meta)
  Json::object(fields)
}

///|
/// Decode the result of `terminal/wait_for_exit`.
pub fn terminal_wait_for_exit_result_from_json(
  value : Json,
  path? : String = "terminal/wait_for_exit",
) -> TerminalWaitForExitResult raise ProtocolDecodeError {
  let (exit_code, signal, meta) = terminal_decode_exit_result_fields(
    value,
    path~,
  )
  { exit_code, signal, meta }
}

///|
/// Encode the result of `terminal/wait_for_exit`.
pub fn terminal_wait_for_exit_result_to_json(
  value : TerminalWaitForExitResult,
) -> Json raise ProtocolDecodeError {
  terminal_encode_exit_result(value.exit_code, value.signal, value.meta)
}

///|
fn terminal_decode_control_params(
  value : Json,
  path~ : String,
) -> (SessionId, TerminalId, ProtocolNullable[Json]) raise ProtocolDecodeError {
  terminal_decode_wait_params(value, path~)
}

///|
fn terminal_encode_control_params(
  session_id : SessionId,
  terminal_id : TerminalId,
  meta : ProtocolNullable[Json],
) -> Json raise ProtocolDecodeError {
  terminal_encode_wait_params(session_id, terminal_id, meta)
}

///|
/// Decode `terminal/kill` parameters.
pub fn terminal_kill_params_from_json(
  value : Json,
  path? : String = "terminal/kill",
) -> TerminalKillParams raise ProtocolDecodeError {
  let (session_id, terminal_id, meta) = terminal_decode_control_params(
    value,
    path~,
  )
  { session_id, terminal_id, meta }
}

///|
/// Encode `terminal/kill` parameters.
pub fn terminal_kill_params_to_json(
  value : TerminalKillParams,
) -> Json raise ProtocolDecodeError {
  terminal_encode_control_params(
    value.session_id,
    value.terminal_id,
    value.meta,
  )
}

///|
/// Decode the result of `terminal/kill`.
pub fn terminal_kill_result_from_json(
  value : Json,
  path? : String = "terminal/kill",
) -> TerminalKillResult raise ProtocolDecodeError {
  { meta: terminal_decode_empty_result(value, path~) }
}

///|
/// Encode the result of `terminal/kill`.
pub fn terminal_kill_result_to_json(
  value : TerminalKillResult,
) -> Json raise ProtocolDecodeError {
  terminal_encode_empty_result(value.meta)
}

///|
/// Decode `terminal/release` parameters.
pub fn terminal_release_params_from_json(
  value : Json,
  path? : String = "terminal/release",
) -> TerminalReleaseParams raise ProtocolDecodeError {
  let (session_id, terminal_id, meta) = terminal_decode_control_params(
    value,
    path~,
  )
  { session_id, terminal_id, meta }
}

///|
/// Encode `terminal/release` parameters.
pub fn terminal_release_params_to_json(
  value : TerminalReleaseParams,
) -> Json raise ProtocolDecodeError {
  terminal_encode_control_params(
    value.session_id,
    value.terminal_id,
    value.meta,
  )
}

///|
/// Decode the result of `terminal/release`.
pub fn terminal_release_result_from_json(
  value : Json,
  path? : String = "terminal/release",
) -> TerminalReleaseResult raise ProtocolDecodeError {
  { meta: terminal_decode_empty_result(value, path~) }
}

///|
/// Encode the result of `terminal/release`.
pub fn terminal_release_result_to_json(
  value : TerminalReleaseResult,
) -> Json raise ProtocolDecodeError {
  terminal_encode_empty_result(value.meta)
}
