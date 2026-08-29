///|
/// A display-only reference to an agent-owned terminal.  Terminal state and
/// output are delivered separately through the terminal update and output
/// chunk payloads.
pub(all) struct ExperimentalV2Terminal {
  terminal_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_terminal(
  value : Json,
  path? : String = "terminal",
) -> ExperimentalV2Terminal raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "terminalId", "_meta"],
    prefix=path,
  )
  let terminal_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "terminalId", path=path + ".terminalId"),
      path=path + ".terminalId",
    ),
    field_path=path + ".terminalId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { terminal_id, meta, }
}

///|
pub fn experimental_v2_encode_terminal(
  value : ExperimentalV2Terminal,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["terminalId"] = Json::string(value.terminal_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// An authoritative replacement snapshot of terminal output bytes.
pub(all) struct ExperimentalV2TerminalOutput {
  data : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_terminal_output(
  value : Json,
  path? : String = "output",
) -> ExperimentalV2TerminalOutput raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["data", "_meta"], prefix=path)
  let data = experimental_v2_validate_base64(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "data", path=path + ".data"),
      path=path + ".data",
    ),
    field_path=path + ".data",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { data, meta, }
}

///|
pub fn experimental_v2_encode_terminal_output(
  value : ExperimentalV2TerminalOutput,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["data"] = Json::string(
    experimental_v2_validate_base64(value.data, field_path="data"),
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Exit information for an agent-owned terminal.  Presence of the object
/// marks the terminal as exited even when neither an exit code nor a signal
/// is known; omitted and null are equivalent for both fields.
pub(all) struct ExperimentalV2TerminalExitStatus {
  exit_code : UInt?
  signal : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_terminal_exit_status(
  value : Json,
  path? : String = "exitStatus",
) -> ExperimentalV2TerminalExitStatus raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["exitCode", "signal", "_meta"],
    prefix=path,
  )
  let exit_code = experimental_v2_decode_optional(
    fields,
    "exitCode",
    path=path + ".exitCode",
    (value, path) => experimental_v2_decode_uint32(value, path~),
  )
  let signal = experimental_v2_decode_optional(
    fields,
    "signal",
    path=path + ".signal",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { exit_code, signal, meta, }
}

///|
pub fn experimental_v2_encode_terminal_exit_status(
  value : ExperimentalV2TerminalExitStatus,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "exitCode", value.exit_code, value => {
    Json::number(value.to_double())
  })
  experimental_v2_put_optional(fields, "signal", value.signal, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// An upsert for the stored state of an agent-owned terminal.  Only
/// `terminal_id` is required; every other field is a patch tri-state where
/// omitted keeps the stored value, null clears it, and a value replaces it.
pub(all) struct ExperimentalV2TerminalUpdate {
  terminal_id : String
  command : ExperimentalV2Patch[String]
  cwd : ExperimentalV2Patch[String]
  output : ExperimentalV2Patch[ExperimentalV2TerminalOutput]
  exit_status : ExperimentalV2Patch[ExperimentalV2TerminalExitStatus]
  meta : ExperimentalV2Patch[Json]
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_terminal_update(
  value : Json,
  path? : String = "terminal",
) -> ExperimentalV2TerminalUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "terminalId", "command", "cwd", "output", "exitStatus"],
    prefix=path,
  )
  let terminal_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "terminalId", path=path + ".terminalId"),
      path=path + ".terminalId",
    ),
    field_path=path + ".terminalId",
  )
  let command = experimental_v2_decode_patch(
    fields,
    "command",
    path=path + ".command",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let cwd = experimental_v2_decode_patch(fields, "cwd", path=path + ".cwd", (
    value,
    path,
  ) => {
    experimental_v2_validate_absolute_path(
      experimental_v2_decode_string(value, path~),
      field_path=path,
    )
  })
  let output = experimental_v2_decode_patch(
    fields,
    "output",
    path=path + ".output",
    (value, path) => experimental_v2_decode_terminal_output(value, path~),
  )
  let exit_status = experimental_v2_decode_patch(
    fields,
    "exitStatus",
    path=path + ".exitStatus",
    (value, path) => experimental_v2_decode_terminal_exit_status(value, path~),
  )
  let meta = experimental_v2_top_meta(fields, path=path + "._meta")
  { terminal_id, command, cwd, output, exit_status, meta, }
}

///|
pub fn experimental_v2_encode_terminal_update(
  value : ExperimentalV2TerminalUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["terminalId"] = Json::string(value.terminal_id)
  experimental_v2_put_patch(fields, "command", value.command, value => {
    Json::string(value)
  })
  experimental_v2_put_patch(fields, "cwd", value.cwd, cwd => {
    Json::string(experimental_v2_validate_absolute_path(cwd, field_path="cwd"))
  })
  experimental_v2_put_patch(fields, "output", value.output, value => {
    experimental_v2_encode_terminal_output(value)
  })
  experimental_v2_put_patch(fields, "exitStatus", value.exit_status, value => {
    experimental_v2_encode_terminal_exit_status(value)
  })
  experimental_v2_put_top_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// A chunk of bytes appended to an agent-owned terminal's output.  Each chunk
/// is independently base64-encoded and may split UTF-8 code points or ANSI
/// escape sequences.
pub(all) struct ExperimentalV2TerminalOutputChunk {
  terminal_id : String
  data : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_terminal_output_chunk(
  value : Json,
  path? : String = "terminalOutputChunk",
) -> ExperimentalV2TerminalOutputChunk raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["terminalId", "data", "_meta"],
    prefix=path,
  )
  let terminal_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "terminalId", path=path + ".terminalId"),
      path=path + ".terminalId",
    ),
    field_path=path + ".terminalId",
  )
  let data = experimental_v2_validate_base64(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "data", path=path + ".data"),
      path=path + ".data",
    ),
    field_path=path + ".data",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { terminal_id, data, meta, }
}

///|
pub fn experimental_v2_encode_terminal_output_chunk(
  value : ExperimentalV2TerminalOutputChunk,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["terminalId"] = Json::string(value.terminal_id)
  fields["data"] = Json::string(
    experimental_v2_validate_base64(value.data, field_path="data"),
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
