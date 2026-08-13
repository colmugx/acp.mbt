///|
/// Categories of tools that can be invoked by an agent.
pub(all) enum ToolKind {
  Read
  Edit
  Delete
  Move
  Search
  Execute
  Think
  Fetch
  SwitchMode
  Other
} derive(Eq, Debug)

///|
/// Lifecycle status of a tool call.
pub(all) enum ToolCallStatus {
  Pending
  InProgress
  Completed
  Failed
} derive(Eq, Debug)

///|
/// A file location affected by a tool call.
pub(all) struct ToolCallLocation {
  path : String
  line : ProtocolNullable[UInt64]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// A file modification shown in a tool call.
pub(all) struct Diff {
  path : String
  old_text : ProtocolNullable[String]
  new_text : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// A terminal created by the client and referenced by a tool call.
pub(all) struct Terminal {
  terminal_id : TerminalId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Content produced by a tool call.
pub(all) enum ToolCallContent {
  Content(Content)
  Diff(Diff)
  Terminal(Terminal)
} derive(Eq, Debug)

///|
/// Initial description of a tool call.
pub(all) struct ToolCall {
  tool_call_id : ToolCallId
  title : String
  kind : ProtocolNullable[ToolKind]
  status : ProtocolNullable[ToolCallStatus]
  content : ProtocolNullable[Array[ToolCallContent]]
  locations : ProtocolNullable[Array[ToolCallLocation]]
  raw_input : ProtocolNullable[Json]
  raw_output : ProtocolNullable[Json]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Partial replacement update for an existing tool call.
pub(all) struct ToolCallUpdate {
  tool_call_id : ToolCallId
  kind : ProtocolNullable[ToolKind]
  status : ProtocolNullable[ToolCallStatus]
  title : ProtocolNullable[String]
  content : ProtocolNullable[Array[ToolCallContent]]
  locations : ProtocolNullable[Array[ToolCallLocation]]
  raw_input : ProtocolNullable[Json]
  raw_output : ProtocolNullable[Json]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Permission option kinds presented to a user.
pub(all) enum PermissionOptionKind {
  AllowOnce
  AllowAlways
  RejectOnce
  RejectAlways
} derive(Eq, Debug)

///|
/// One selectable permission option.
pub(all) struct PermissionOption {
  option_id : PermissionOptionId
  name : String
  kind : PermissionOptionKind
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The selected permission outcome payload.
pub(all) struct SelectedPermissionOutcome {
  option_id : PermissionOptionId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The two stable permission outcomes.
pub(all) enum RequestPermissionOutcome {
  Cancelled
  Selected(SelectedPermissionOutcome)
} derive(Eq, Debug)

///|
/// Agent request for client permission to execute a tool call.
pub(all) struct RequestPermissionRequest {
  session_id : SessionId
  tool_call : ToolCallUpdate
  options : Array[PermissionOption]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Client response to a permission request.
pub(all) struct RequestPermissionResponse {
  outcome : RequestPermissionOutcome
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn encode_tool_kind(value : ToolKind) -> Json {
  Json::string(
    match value {
      Read => "read"
      Edit => "edit"
      Delete => "delete"
      Move => "move"
      Search => "search"
      Execute => "execute"
      Think => "think"
      Fetch => "fetch"
      SwitchMode => "switch_mode"
      Other => "other"
    },
  )
}

///|
fn decode_tool_kind(
  value : Json,
  path~ : String,
) -> ToolKind raise ProtocolDecodeError {
  match value {
    String("read") => Read
    String("edit") => Edit
    String("delete") => Delete
    String("move") => Move
    String("search") => Search
    String("execute") => Execute
    String("think") => Think
    String("fetch") => Fetch
    String("switch_mode") => SwitchMode
    String("other") => Other
    String(value) => raise InvalidDiscriminator(path~, value~)
    _ => raise ExpectedString(path~)
  }
}

///|
fn encode_tool_call_status(value : ToolCallStatus) -> Json {
  Json::string(
    match value {
      Pending => "pending"
      InProgress => "in_progress"
      Completed => "completed"
      Failed => "failed"
    },
  )
}

///|
fn decode_tool_call_status(
  value : Json,
  path~ : String,
) -> ToolCallStatus raise ProtocolDecodeError {
  match value {
    String("pending") => Pending
    String("in_progress") => InProgress
    String("completed") => Completed
    String("failed") => Failed
    String(value) => raise InvalidDiscriminator(path~, value~)
    _ => raise ExpectedString(path~)
  }
}

///|
fn encode_permission_option_kind(value : PermissionOptionKind) -> Json {
  Json::string(
    match value {
      AllowOnce => "allow_once"
      AllowAlways => "allow_always"
      RejectOnce => "reject_once"
      RejectAlways => "reject_always"
    },
  )
}

///|
fn decode_permission_option_kind(
  value : Json,
  path~ : String,
) -> PermissionOptionKind raise ProtocolDecodeError {
  match value {
    String("allow_once") => AllowOnce
    String("allow_always") => AllowAlways
    String("reject_once") => RejectOnce
    String("reject_always") => RejectAlways
    String(value) => raise InvalidDiscriminator(path~, value~)
    _ => raise ExpectedString(path~)
  }
}

///|
fn encode_tool_location(
  value : ToolCallLocation,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json::string(
    protocol_validate_absolute_path(value.path, field_path="path"),
  )
  match value.line {
    Omitted => ()
    Null => fields["line"] = Json::null()
    Value(line) => {
      if line == 0 {
        raise InvalidField(path="line", reason="line must be 1-based")
      }
      fields["line"] = line.to_json()
    }
  }
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_tool_location(
  value : Json,
  path~ : String,
) -> ToolCallLocation raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["path", "line", "_meta"], prefix=path)
  let path_value = protocol_required_string(fields, "path", path=path + ".path")
  let path_value = protocol_validate_absolute_path(
    path_value,
    field_path=path + ".path",
  )
  let line : ProtocolNullable[UInt64] = match protocol_field(fields, "line") {
    Omitted => Omitted
    Null => Null
    Value(value) => {
      let line = protocol_decode_uint64(value, path=path + ".line")
      if line == 0 {
        raise InvalidField(path=path + ".line", reason="line must be 1-based")
      }
      Value(line)
    }
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { path: path_value, line, meta }
}

///|
fn decode_locations(
  value : Json,
  path~ : String,
) -> Array[ToolCallLocation] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let locations : Array[ToolCallLocation] = []
  for index, value in values {
    locations.push(
      decode_tool_location(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  locations
}

///|
fn encode_locations(
  values : Array[ToolCallLocation],
) -> Json raise ProtocolDecodeError {
  Json::array(values.map(value => encode_tool_location(value)))
}

///|
fn encode_diff(
  value : Diff,
  with_type : Bool,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  if with_type {
    fields["type"] = Json::string("diff")
  }
  fields["path"] = Json::string(
    protocol_validate_absolute_path(value.path, field_path="path"),
  )
  protocol_put_nullable(fields, "oldText", value.old_text, value => {
    Json::string(value)
  })
  fields["newText"] = Json::string(value.new_text)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_diff(
  value : Json,
  path~ : String,
  with_type : Bool,
) -> Diff raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let allowed = if with_type {
    ["type", "path", "oldText", "newText", "_meta"]
  } else {
    ["path", "oldText", "newText", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let path_value = protocol_required_string(fields, "path", path=path + ".path")
  let path_value = protocol_validate_absolute_path(
    path_value,
    field_path=path + ".path",
  )
  let old_text = protocol_nullable_string(
    fields,
    "oldText",
    path=path + ".oldText",
  )
  let new_text = protocol_required_string(
    fields,
    "newText",
    path=path + ".newText",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { path: path_value, old_text, new_text, meta }
}

///|
fn encode_terminal(
  value : Terminal,
  with_type : Bool,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  if with_type {
    fields["type"] = Json::string("terminal")
  }
  fields["terminalId"] = Json::string(value.terminal_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_terminal(
  value : Json,
  path~ : String,
  with_type : Bool,
) -> Terminal raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let allowed = if with_type {
    ["type", "terminalId", "_meta"]
  } else {
    ["terminalId", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let terminal_id = protocol_required_string(
    fields,
    "terminalId",
    path=path + ".terminalId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { terminal_id, meta }
}

///|
fn encode_tool_call_content(
  value : ToolCallContent,
) -> Json raise ProtocolDecodeError {
  match value {
    Content(value) => add_tool_content_type(content_to_json(value), "content")
    Diff(value) => encode_diff(value, true)
    Terminal(value) => encode_terminal(value, true)
  }
}

///|
fn add_tool_content_type(
  value : Json,
  kind : String,
) -> Json raise ProtocolDecodeError {
  match value {
    Object(fields) => {
      fields["type"] = Json::string(kind)
      Json::object(fields)
    }
    _ =>
      raise InvalidField(
        path="toolContent",
        reason="encoded tool content must be an object",
      )
  }
}

///|
fn decode_tool_call_content(
  value : Json,
  path~ : String,
) -> ToolCallContent raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let kind = protocol_required_string(fields, "type", path=path + ".type")
  match kind {
    "content" => Content(content_from_fields(fields, path~, true))
    "diff" => Diff(decode_diff(value, path~, true))
    "terminal" => Terminal(decode_terminal(value, path~, true))
    _ => raise InvalidDiscriminator(path=path + ".type", value=kind)
  }
}

///|
fn decode_tool_call_contents(
  value : Json,
  path~ : String,
) -> Array[ToolCallContent] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let contents : Array[ToolCallContent] = []
  for index, value in values {
    contents.push(
      decode_tool_call_content(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  contents
}

///|
fn encode_tool_call_contents(
  values : Array[ToolCallContent],
) -> Json raise ProtocolDecodeError {
  Json::array(values.map(value => encode_tool_call_content(value)))
}

///|
fn decode_optional_tool_kind(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[ToolKind] raise ProtocolDecodeError {
  match protocol_field(fields, "kind") {
    Omitted => Omitted
    Null => raise InvalidField(path~, reason="kind is not nullable")
    Value(value) => Value(decode_tool_kind(value, path~))
  }
}

///|
fn decode_optional_tool_status(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[ToolCallStatus] raise ProtocolDecodeError {
  match protocol_field(fields, "status") {
    Omitted => Omitted
    Null => raise InvalidField(path~, reason="status is not nullable")
    Value(value) => Value(decode_tool_call_status(value, path~))
  }
}

///|
fn decode_optional_tool_contents(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Array[ToolCallContent]] raise ProtocolDecodeError {
  match protocol_field(fields, "content") {
    Omitted => Omitted
    Null => raise InvalidField(path~, reason="content is not nullable")
    Value(value) => Value(decode_tool_call_contents(value, path~))
  }
}

///|
fn decode_optional_locations(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Array[ToolCallLocation]] raise ProtocolDecodeError {
  match protocol_field(fields, "locations") {
    Omitted => Omitted
    Null => raise InvalidField(path~, reason="locations is not nullable")
    Value(value) => Value(decode_locations(value, path~))
  }
}

///|
fn put_optional_tool_kind(
  fields : Map[String, Json],
  value : ProtocolNullable[ToolKind],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => raise InvalidField(path="kind", reason="kind is not nullable")
    Value(value) => fields["kind"] = encode_tool_kind(value)
  }
}

///|
fn put_optional_tool_status(
  fields : Map[String, Json],
  value : ProtocolNullable[ToolCallStatus],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => raise InvalidField(path="status", reason="status is not nullable")
    Value(value) => fields["status"] = encode_tool_call_status(value)
  }
}

///|
fn put_optional_tool_contents(
  fields : Map[String, Json],
  value : ProtocolNullable[Array[ToolCallContent]],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => raise InvalidField(path="content", reason="content is not nullable")
    Value(value) => fields["content"] = encode_tool_call_contents(value)
  }
}

///|
fn put_optional_locations(
  fields : Map[String, Json],
  value : ProtocolNullable[Array[ToolCallLocation]],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null =>
      raise InvalidField(path="locations", reason="locations is not nullable")
    Value(value) => fields["locations"] = encode_locations(value)
  }
}

///|
fn put_nullable_tool_contents(
  fields : Map[String, Json],
  value : ProtocolNullable[Array[ToolCallContent]],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields["content"] = Json::null()
    Value(value) => fields["content"] = encode_tool_call_contents(value)
  }
}

///|
fn put_nullable_locations(
  fields : Map[String, Json],
  value : ProtocolNullable[Array[ToolCallLocation]],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields["locations"] = Json::null()
    Value(value) => fields["locations"] = encode_locations(value)
  }
}

///|
fn decode_tool_call_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ToolCall raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    [
      "toolCallId", "title", "kind", "status", "content", "locations", "rawInput",
      "rawOutput", "_meta",
    ],
    prefix=path,
  )
  let tool_call_id = protocol_required_string(
    fields,
    "toolCallId",
    path=path + ".toolCallId",
  )
  let title = protocol_required_string(fields, "title", path=path + ".title")
  let kind = decode_optional_tool_kind(fields, path=path + ".kind")
  let status = decode_optional_tool_status(fields, path=path + ".status")
  let content = decode_optional_tool_contents(fields, path=path + ".content")
  let locations = decode_optional_locations(fields, path=path + ".locations")
  let raw_input = protocol_nullable_json(fields, "rawInput")
  let raw_output = protocol_nullable_json(fields, "rawOutput")
  let meta = protocol_meta(fields, path=path + "._meta")
  {
    tool_call_id,
    title,
    kind,
    status,
    content,
    locations,
    raw_input,
    raw_output,
    meta,
  }
}

///|
/// Decode an initial tool call from JSON.
pub fn tool_call_from_json(
  value : Json,
  path? : String = "toolCall",
) -> ToolCall raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_tool_call_fields(fields, path~)
}

///|
/// Encode an initial tool call as JSON.
pub fn tool_call_to_json(value : ToolCall) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["toolCallId"] = Json::string(value.tool_call_id)
  fields["title"] = Json::string(value.title)
  put_optional_tool_kind(fields, value.kind)
  put_optional_tool_status(fields, value.status)
  put_optional_tool_contents(fields, value.content)
  put_optional_locations(fields, value.locations)
  protocol_put_nullable(fields, "rawInput", value.raw_input, value => value)
  protocol_put_nullable(fields, "rawOutput", value.raw_output, value => value)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_tool_call_update_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ToolCallUpdate raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    [
      "toolCallId", "kind", "status", "title", "content", "locations", "rawInput",
      "rawOutput", "_meta",
    ],
    prefix=path,
  )
  let tool_call_id = protocol_required_string(
    fields,
    "toolCallId",
    path=path + ".toolCallId",
  )
  let kind = match protocol_field(fields, "kind") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(decode_tool_kind(value, path=path + ".kind"))
  }
  let status = match protocol_field(fields, "status") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(decode_tool_call_status(value, path=path + ".status"))
  }
  let title = protocol_nullable_string(fields, "title", path=path + ".title")
  let content = match protocol_field(fields, "content") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(decode_tool_call_contents(value, path=path + ".content"))
  }
  let locations = match protocol_field(fields, "locations") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(decode_locations(value, path=path + ".locations"))
  }
  let raw_input = protocol_nullable_json(fields, "rawInput")
  let raw_output = protocol_nullable_json(fields, "rawOutput")
  let meta = protocol_meta(fields, path=path + "._meta")
  {
    tool_call_id,
    kind,
    status,
    title,
    content,
    locations,
    raw_input,
    raw_output,
    meta,
  }
}

///|
/// Decode a tool call update from JSON.
pub fn tool_call_update_from_json(
  value : Json,
  path? : String = "toolCallUpdate",
) -> ToolCallUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_tool_call_update_fields(fields, path~)
}

///|
/// Encode a tool call update as JSON.
pub fn tool_call_update_to_json(
  value : ToolCallUpdate,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["toolCallId"] = Json::string(value.tool_call_id)
  protocol_put_nullable(fields, "kind", value.kind, encode_tool_kind)
  protocol_put_nullable(fields, "status", value.status, encode_tool_call_status)
  protocol_put_nullable(fields, "title", value.title, value => {
    Json::string(value)
  })
  put_nullable_tool_contents(fields, value.content)
  put_nullable_locations(fields, value.locations)
  protocol_put_nullable(fields, "rawInput", value.raw_input, value => value)
  protocol_put_nullable(fields, "rawOutput", value.raw_output, value => value)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn encode_permission_option(
  value : PermissionOption,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["optionId"] = Json::string(value.option_id)
  fields["name"] = Json::string(value.name)
  fields["kind"] = encode_permission_option_kind(value.kind)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_permission_option(
  value : Json,
  path~ : String,
) -> PermissionOption raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["optionId", "name", "kind", "_meta"],
    prefix=path,
  )
  let option_id = protocol_required_string(
    fields,
    "optionId",
    path=path + ".optionId",
  )
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let kind = decode_permission_option_kind(
    protocol_required(fields, "kind", path=path + ".kind"),
    path=path + ".kind",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { option_id, name, kind, meta }
}

///|
fn encode_permission_options(
  values : Array[PermissionOption],
) -> Json raise ProtocolDecodeError {
  Json::array(values.map(value => encode_permission_option(value)))
}

///|
fn decode_permission_options(
  value : Json,
  path~ : String,
) -> Array[PermissionOption] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  if values.length() == 0 {
    raise InvalidField(
      path~,
      reason="at least one permission option is required",
    )
  }
  let options : Array[PermissionOption] = []
  for index, value in values {
    options.push(
      decode_permission_option(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  options
}

///|
fn encode_selected_permission_outcome(
  value : SelectedPermissionOutcome,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["optionId"] = Json::string(value.option_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_selected_permission_outcome(
  value : Json,
  path~ : String,
  with_outcome : Bool,
) -> SelectedPermissionOutcome raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let allowed = if with_outcome {
    ["outcome", "optionId", "_meta"]
  } else {
    ["optionId", "_meta"]
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let option_id = protocol_required_string(
    fields,
    "optionId",
    path=path + ".optionId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { option_id, meta }
}

///|
/// Encode a permission outcome as JSON.
pub fn request_permission_outcome_to_json(
  value : RequestPermissionOutcome,
) -> Json raise ProtocolDecodeError {
  match value {
    Cancelled => Json::object({ "outcome": Json::string("cancelled") })
    Selected(value) => {
      let fields = match encode_selected_permission_outcome(value) {
        Object(fields) => fields
        _ =>
          raise InvalidField(
            path="outcome",
            reason="encoded selected outcome must be an object",
          )
      }
      fields["outcome"] = Json::string("selected")
      Json::object(fields)
    }
  }
}

///|
/// Decode a permission outcome from JSON.
pub fn request_permission_outcome_from_json(
  value : Json,
  path? : String = "outcome",
) -> RequestPermissionOutcome raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let outcome = protocol_required_string(
    fields,
    "outcome",
    path=path + ".outcome",
  )
  match outcome {
    "cancelled" => {
      protocol_reject_unknown(fields, ["outcome"], prefix=path)
      Cancelled
    }
    "selected" =>
      Selected(decode_selected_permission_outcome(value, path~, true))
    _ => raise InvalidDiscriminator(path=path + ".outcome", value=outcome)
  }
}

///|
/// Decode a permission request payload from JSON.
pub fn request_permission_request_from_json(
  value : Json,
  path? : String = "requestPermission",
) -> RequestPermissionRequest raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessionId", "toolCall", "options", "_meta"],
    prefix=path,
  )
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let tool_call = match fields.get("toolCall") {
    Some(value) => tool_call_update_from_json(value, path=path + ".toolCall")
    None => raise MissingField(path=path + ".toolCall")
  }
  let options = match fields.get("options") {
    Some(value) => decode_permission_options(value, path=path + ".options")
    None => raise MissingField(path=path + ".options")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, tool_call, options, meta }
}

///|
/// Encode a permission request payload as JSON.
pub fn request_permission_request_to_json(
  value : RequestPermissionRequest,
) -> Json raise ProtocolDecodeError {
  if value.options.length() == 0 {
    raise InvalidField(
      path="options",
      reason="at least one permission option is required",
    )
  }
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["toolCall"] = tool_call_update_to_json(value.tool_call)
  fields["options"] = encode_permission_options(value.options)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode a permission response payload from JSON.
pub fn request_permission_response_from_json(
  value : Json,
  path? : String = "requestPermission",
) -> RequestPermissionResponse raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["outcome", "_meta"], prefix=path)
  let outcome = match fields.get("outcome") {
    Some(value) =>
      request_permission_outcome_from_json(value, path=path + ".outcome")
    None => raise MissingField(path=path + ".outcome")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { outcome, meta }
}

///|
/// Encode a permission response payload as JSON.
pub fn request_permission_response_to_json(
  value : RequestPermissionResponse,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["outcome"] = request_permission_outcome_to_json(value.outcome)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode a tool-call location from JSON.
pub fn tool_call_location_from_json(
  value : Json,
  path? : String = "location",
) -> ToolCallLocation raise ProtocolDecodeError {
  decode_tool_location(value, path~)
}

///|
/// Encode a tool-call location as JSON.
pub fn tool_call_location_to_json(
  value : ToolCallLocation,
) -> Json raise ProtocolDecodeError {
  encode_tool_location(value)
}

///|
/// Decode a diff from JSON.
pub fn diff_from_json(
  value : Json,
  path? : String = "diff",
) -> Diff raise ProtocolDecodeError {
  decode_diff(value, path~, false)
}

///|
/// Encode a diff as JSON.
pub fn diff_to_json(value : Diff) -> Json raise ProtocolDecodeError {
  encode_diff(value, false)
}

///|
/// Decode a terminal reference from JSON.
pub fn terminal_from_json(
  value : Json,
  path? : String = "terminal",
) -> Terminal raise ProtocolDecodeError {
  decode_terminal(value, path~, false)
}

///|
/// Encode a terminal reference as JSON.
pub fn terminal_to_json(value : Terminal) -> Json raise ProtocolDecodeError {
  encode_terminal(value, false)
}

///|
/// Decode tool-call content from JSON.
pub fn tool_call_content_from_json(
  value : Json,
  path? : String = "toolContent",
) -> ToolCallContent raise ProtocolDecodeError {
  decode_tool_call_content(value, path~)
}

///|
/// Encode tool-call content as JSON.
pub fn tool_call_content_to_json(
  value : ToolCallContent,
) -> Json raise ProtocolDecodeError {
  encode_tool_call_content(value)
}

///|
/// Decode a permission option from JSON.
pub fn permission_option_from_json(
  value : Json,
  path? : String = "permissionOption",
) -> PermissionOption raise ProtocolDecodeError {
  decode_permission_option(value, path~)
}

///|
/// Encode a permission option as JSON.
pub fn permission_option_to_json(
  value : PermissionOption,
) -> Json raise ProtocolDecodeError {
  encode_permission_option(value)
}

///|
/// Decode a selected permission outcome payload from JSON.
pub fn selected_permission_outcome_from_json(
  value : Json,
  path? : String = "selected",
) -> SelectedPermissionOutcome raise ProtocolDecodeError {
  decode_selected_permission_outcome(value, path~, false)
}

///|
/// Encode a selected permission outcome payload as JSON.
pub fn selected_permission_outcome_to_json(
  value : SelectedPermissionOutcome,
) -> Json raise ProtocolDecodeError {
  encode_selected_permission_outcome(value)
}
