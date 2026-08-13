///|
/// Priority of a plan entry.
pub(all) enum PlanEntryPriority {
  High
  Medium
  Low
} derive(Eq, Debug)

///|
/// Lifecycle status of a plan entry.
pub(all) enum PlanEntryStatus {
  Pending
  InProgress
  Completed
} derive(Eq, Debug)

///|
/// One item in an execution plan.
pub(all) struct PlanEntry {
  content : String
  priority : PlanEntryPriority
  status : PlanEntryStatus
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// A complete replacement execution plan.
pub(all) struct Plan {
  entries : Array[PlanEntry]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Cumulative cost information.
pub(all) struct Cost {
  amount : Double
  currency : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Current context-window usage.
pub(all) struct UsageUpdate {
  used : UInt64
  size : UInt64
  cost : ProtocolNullable[Cost]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The unstructured command input form.
pub(all) struct UnstructuredCommandInput {
  hint : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Available command input variants.
pub(all) enum AvailableCommandInput {
  Unstructured(UnstructuredCommandInput)
} derive(Eq, Debug)

///|
/// One command exposed by an agent.
pub(all) struct AvailableCommand {
  name : String
  description : String
  input : ProtocolNullable[AvailableCommandInput]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Complete replacement list of available commands.
pub(all) struct AvailableCommandsUpdate {
  available_commands : Array[AvailableCommand]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Current mode selected for a session.
pub(all) struct CurrentModeUpdate {
  current_mode_id : SessionModeId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Semantic categories for configuration selectors.
pub(all) enum SessionConfigOptionCategory {
  Mode
  Model
  ModelConfig
  ThoughtLevel
  Other(String)
} derive(Eq, Debug)

///|
/// One selectable configuration value.
pub(all) struct SessionConfigSelectOption {
  value : SessionConfigValueId
  name : String
  description : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// A grouped set of selectable configuration values.
pub(all) struct SessionConfigSelectGroup {
  group : SessionConfigGroupId
  name : String
  options : Array[SessionConfigSelectOption]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Flat or grouped selectable values.
pub(all) enum SessionConfigSelectOptions {
  Ungrouped(Array[SessionConfigSelectOption])
  Grouped(Array[SessionConfigSelectGroup])
} derive(Eq, Debug)

///|
/// Selector-specific configuration payload.
pub(all) struct SessionConfigSelect {
  current_value : SessionConfigValueId
  options : SessionConfigSelectOptions
} derive(Eq, Debug)

///|
/// Boolean-specific configuration payload.
pub(all) struct SessionConfigBoolean {
  current_value : Bool
} derive(Eq, Debug)

///|
/// Configuration option payload variants.
pub(all) enum SessionConfigOptionKind {
  Select(SessionConfigSelect)
  Boolean(SessionConfigBoolean)
} derive(Eq, Debug)

///|
/// One complete session configuration option.
pub(all) struct SessionConfigOption {
  id : SessionConfigId
  name : String
  description : ProtocolNullable[String]
  category : ProtocolNullable[SessionConfigOptionCategory]
  kind : SessionConfigOptionKind
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Complete replacement configuration option list.
pub(all) struct ConfigOptionUpdate {
  config_options : Array[SessionConfigOption]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Partial session metadata update.
pub(all) struct SessionInfoUpdate {
  title : ProtocolNullable[String]
  updated_at : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Session metadata used by session listing.
pub(all) struct SessionInfo {
  session_id : SessionId
  cwd : String
  additional_directories : ProtocolNullable[Array[String]]
  title : ProtocolNullable[String]
  updated_at : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// All stable v1 session update variants.
pub(all) enum SessionUpdate {
  UserMessageChunk(ContentChunk)
  AgentMessageChunk(ContentChunk)
  AgentThoughtChunk(ContentChunk)
  ToolCall(ToolCall)
  ToolCallUpdate(ToolCallUpdate)
  Plan(Plan)
  AvailableCommandsUpdate(AvailableCommandsUpdate)
  CurrentModeUpdate(CurrentModeUpdate)
  ConfigOptionUpdate(ConfigOptionUpdate)
  SessionInfoUpdate(SessionInfoUpdate)
  UsageUpdate(UsageUpdate)
} derive(Eq, Debug)

///|
fn encode_plan_priority(value : PlanEntryPriority) -> Json {
  Json::string(
    match value {
      High => "high"
      Medium => "medium"
      Low => "low"
    },
  )
}

///|
fn decode_plan_priority(
  value : Json,
  path~ : String,
) -> PlanEntryPriority raise ProtocolDecodeError {
  match value {
    String("high") => High
    String("medium") => Medium
    String("low") => Low
    String(value) => raise InvalidDiscriminator(path~, value~)
    _ => raise ExpectedString(path~)
  }
}

///|
fn encode_plan_status(value : PlanEntryStatus) -> Json {
  Json::string(
    match value {
      Pending => "pending"
      InProgress => "in_progress"
      Completed => "completed"
    },
  )
}

///|
fn decode_plan_status(
  value : Json,
  path~ : String,
) -> PlanEntryStatus raise ProtocolDecodeError {
  match value {
    String("pending") => Pending
    String("in_progress") => InProgress
    String("completed") => Completed
    String(value) => raise InvalidDiscriminator(path~, value~)
    _ => raise ExpectedString(path~)
  }
}

///|
fn encode_plan_entry(value : PlanEntry) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["content"] = Json::string(value.content)
  fields["priority"] = encode_plan_priority(value.priority)
  fields["status"] = encode_plan_status(value.status)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_plan_entry(
  value : Json,
  path~ : String,
) -> PlanEntry raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["content", "priority", "status", "_meta"],
    prefix=path,
  )
  let content = protocol_required_string(
    fields,
    "content",
    path=path + ".content",
  )
  let priority = decode_plan_priority(
    protocol_required(fields, "priority", path=path + ".priority"),
    path=path + ".priority",
  )
  let status = decode_plan_status(
    protocol_required(fields, "status", path=path + ".status"),
    path=path + ".status",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { content, priority, status, meta }
}

///|
fn encode_plan_entries(
  values : Array[PlanEntry],
) -> Json raise ProtocolDecodeError {
  Json::array(values.map(value => encode_plan_entry(value)))
}

///|
fn decode_plan_entries(
  value : Json,
  path~ : String,
) -> Array[PlanEntry] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let entries : Array[PlanEntry] = []
  for index, value in values {
    entries.push(
      decode_plan_entry(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  entries
}

///|
/// Decode a plan update from JSON.
pub fn plan_from_json(
  value : Json,
  path? : String = "plan",
) -> Plan raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["entries", "_meta"], prefix=path)
  let entries = match fields.get("entries") {
    Some(value) => decode_plan_entries(value, path=path + ".entries")
    None => raise MissingField(path=path + ".entries")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { entries, meta }
}

///|
/// Encode a plan update as JSON.
pub fn plan_to_json(value : Plan) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["entries"] = encode_plan_entries(value.entries)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn encode_cost(value : Cost) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["amount"] = encode_finite_number(value.amount, path="amount")
  fields["currency"] = Json::string(value.currency)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_cost(value : Json, path~ : String) -> Cost raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["amount", "currency", "_meta"], prefix=path)
  let amount = decode_finite_number(
    protocol_required(fields, "amount", path=path + ".amount"),
    path=path + ".amount",
  )
  let currency = protocol_required_string(
    fields,
    "currency",
    path=path + ".currency",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { amount, currency, meta }
}

///|
fn put_nullable_cost(
  fields : Map[String, Json],
  value : ProtocolNullable[Cost],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields["cost"] = Json::null()
    Value(value) => fields["cost"] = encode_cost(value)
  }
}

///|
/// Decode a usage update from JSON.
pub fn usage_update_from_json(
  value : Json,
  path? : String = "usage",
) -> UsageUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["used", "size", "cost", "_meta"],
    prefix=path,
  )
  let used = protocol_decode_uint64(
    protocol_required(fields, "used", path=path + ".used"),
    path=path + ".used",
  )
  let size = protocol_decode_uint64(
    protocol_required(fields, "size", path=path + ".size"),
    path=path + ".size",
  )
  let cost : ProtocolNullable[Cost] = match protocol_field(fields, "cost") {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(decode_cost(value, path=path + ".cost"))
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { used, size, cost, meta }
}

///|
/// Encode a usage update as JSON.
pub fn usage_update_to_json(
  value : UsageUpdate,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["used"] = value.used.to_json()
  fields["size"] = value.size.to_json()
  put_nullable_cost(fields, value.cost)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn encode_unstructured_input(
  value : UnstructuredCommandInput,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["hint"] = Json::string(value.hint)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_unstructured_input(
  value : Json,
  path~ : String,
) -> UnstructuredCommandInput raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["hint", "_meta"], prefix=path)
  let hint = protocol_required_string(fields, "hint", path=path + ".hint")
  let meta = protocol_meta(fields, path=path + "._meta")
  { hint, meta }
}

///|
fn encode_command_input(
  value : AvailableCommandInput,
) -> Json raise ProtocolDecodeError {
  match value {
    Unstructured(value) => encode_unstructured_input(value)
  }
}

///|
fn decode_command_input(
  value : Json,
  path~ : String,
) -> AvailableCommandInput raise ProtocolDecodeError {
  Unstructured(decode_unstructured_input(value, path~))
}

///|
fn encode_commands(
  values : Array[AvailableCommand],
) -> Json raise ProtocolDecodeError {
  Json::array(
    values.map(value => {
      let fields : Map[String, Json] = Map([])
      fields["name"] = Json::string(value.name)
      fields["description"] = Json::string(value.description)
      match value.input {
        Omitted => ()
        Null => fields["input"] = Json::null()
        Value(input) => fields["input"] = encode_command_input(input)
      }
      protocol_put_meta(fields, value.meta)
      Json::object(fields)
    }),
  )
}

///|
fn decode_commands(
  value : Json,
  path~ : String,
) -> Array[AvailableCommand] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let commands : Array[AvailableCommand] = []
  for index, value in values {
    let command_path = path + "[" + index.to_string() + "]"
    let fields = protocol_require_object(value, path=command_path)
    protocol_reject_unknown(
      fields,
      ["name", "description", "input", "_meta"],
      prefix=command_path,
    )
    let name = protocol_required_string(
      fields,
      "name",
      path=command_path + ".name",
    )
    let description = protocol_required_string(
      fields,
      "description",
      path=command_path + ".description",
    )
    let input : ProtocolNullable[AvailableCommandInput] = match
      protocol_field(fields, "input") {
      Omitted => Omitted
      Null => Null
      Value(value) =>
        Value(decode_command_input(value, path=command_path + ".input"))
    }
    let meta = protocol_meta(fields, path=command_path + "._meta")
    commands.push({ name, description, input, meta })
  }
  commands
}

///|
/// Decode an available-commands update from JSON.
pub fn available_commands_update_from_json(
  value : Json,
  path? : String = "availableCommands",
) -> AvailableCommandsUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["availableCommands", "_meta"], prefix=path)
  let available_commands = match fields.get("availableCommands") {
    Some(value) => decode_commands(value, path=path + ".availableCommands")
    None => raise MissingField(path=path + ".availableCommands")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { available_commands, meta }
}

///|
/// Encode an available-commands update as JSON.
pub fn available_commands_update_to_json(
  value : AvailableCommandsUpdate,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["availableCommands"] = encode_commands(value.available_commands)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn encode_config_category(value : SessionConfigOptionCategory) -> Json {
  Json::string(
    match value {
      Mode => "mode"
      Model => "model"
      ModelConfig => "model_config"
      ThoughtLevel => "thought_level"
      Other(value) => value
    },
  )
}

///|
fn decode_config_category(
  value : Json,
  path~ : String,
) -> SessionConfigOptionCategory raise ProtocolDecodeError {
  match value {
    String("mode") => Mode
    String("model") => Model
    String("model_config") => ModelConfig
    String("thought_level") => ThoughtLevel
    String(value) => Other(value)
    _ => raise ExpectedString(path~)
  }
}

///|
fn encode_select_option(
  value : SessionConfigSelectOption,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["value"] = Json::string(value.value)
  fields["name"] = Json::string(value.name)
  protocol_put_nullable(fields, "description", value.description, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_select_option(
  value : Json,
  path~ : String,
) -> SessionConfigSelectOption raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["value", "name", "description", "_meta"],
    prefix=path,
  )
  let option_value = protocol_required_string(
    fields,
    "value",
    path=path + ".value",
  )
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let description = protocol_nullable_string(
    fields,
    "description",
    path=path + ".description",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { value: option_value, name, description, meta }
}

///|
fn encode_select_options(
  values : SessionConfigSelectOptions,
) -> Json raise ProtocolDecodeError {
  match values {
    Ungrouped(values) =>
      Json::array(values.map(value => encode_select_option(value)))
    Grouped(values) =>
      Json::array(values.map(value => encode_select_group(value)))
  }
}

///|
fn decode_select_options(
  value : Json,
  path~ : String,
) -> SessionConfigSelectOptions raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  if values.length() == 0 {
    Ungrouped([])
  } else {
    let first = protocol_require_object(values[0], path=path + "[0]")
    let has_value = first.contains("value")
    let has_group = first.contains("group")
    if has_value && has_group {
      raise InvalidField(
        path~,
        reason="select option cannot be both grouped and ungrouped",
      )
    }
    if has_value {
      let options : Array[SessionConfigSelectOption] = []
      for index, item in values {
        let item_path = path + "[" + index.to_string() + "]"
        let item_fields = protocol_require_object(item, path=item_path)
        if !item_fields.contains("value") || item_fields.contains("group") {
          raise InvalidField(path=item_path, reason="mixed select option forms")
        }
        options.push(decode_select_option(item, path=item_path))
      }
      Ungrouped(options)
    } else if has_group {
      let groups : Array[SessionConfigSelectGroup] = []
      for index, item in values {
        let item_path = path + "[" + index.to_string() + "]"
        let item_fields = protocol_require_object(item, path=item_path)
        if !item_fields.contains("group") || item_fields.contains("value") {
          raise InvalidField(
            path=item_path,
            reason="mixed select option group forms",
          )
        }
        groups.push(decode_select_group(item, path=item_path))
      }
      Grouped(groups)
    } else {
      raise InvalidField(
        path~,
        reason="select option must contain value or group",
      )
    }
  }
}

///|
fn encode_select_group(
  value : SessionConfigSelectGroup,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["group"] = Json::string(value.group)
  fields["name"] = Json::string(value.name)
  fields["options"] = Json::array(
    value.options.map(value => encode_select_option(value)),
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_select_group(
  value : Json,
  path~ : String,
) -> SessionConfigSelectGroup raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["group", "name", "options", "_meta"],
    prefix=path,
  )
  let group = protocol_required_string(fields, "group", path=path + ".group")
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let options = match fields.get("options") {
    Some(value) => {
      let values = protocol_require_array(value, path=path + ".options")
      let result : Array[SessionConfigSelectOption] = []
      for index, value in values {
        result.push(
          decode_select_option(
            value,
            path=path + ".options[" + index.to_string() + "]",
          ),
        )
      }
      result
    }
    None => raise MissingField(path=path + ".options")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { group, name, options, meta }
}

///|
fn encode_config_option(
  value : SessionConfigOption,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json::string(value.id)
  fields["name"] = Json::string(value.name)
  protocol_put_nullable(fields, "description", value.description, value => {
    Json::string(value)
  })
  protocol_put_nullable(
    fields,
    "category",
    value.category,
    encode_config_category,
  )
  match value.kind {
    Select(select) => {
      fields["type"] = Json::string("select")
      fields["currentValue"] = Json::string(select.current_value)
      fields["options"] = encode_select_options(select.options)
    }
    Boolean(boolean) => {
      fields["type"] = Json::string("boolean")
      fields["currentValue"] = Json::boolean(boolean.current_value)
    }
  }
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_config_option(
  value : Json,
  path~ : String,
) -> SessionConfigOption raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let kind_name = protocol_required_string(fields, "type", path=path + ".type")
  let allowed = match kind_name {
    "select" =>
      [
        "id", "name", "description", "category", "type", "currentValue", "options",
        "_meta",
      ]
    "boolean" =>
      ["id", "name", "description", "category", "type", "currentValue", "_meta"]
    _ => ["type"]
  }
  if kind_name != "select" && kind_name != "boolean" {
    raise InvalidDiscriminator(path=path + ".type", value=kind_name)
  }
  protocol_reject_unknown(fields, allowed, prefix=path)
  let id = protocol_required_string(fields, "id", path=path + ".id")
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let description = protocol_nullable_string(
    fields,
    "description",
    path=path + ".description",
  )
  let category : ProtocolNullable[SessionConfigOptionCategory] = match
    protocol_field(fields, "category") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(decode_config_category(value, path=path + ".category"))
  }
  let kind = if kind_name == "select" {
    let current_value = protocol_required_string(
      fields,
      "currentValue",
      path=path + ".currentValue",
    )
    let options = match fields.get("options") {
      Some(value) => decode_select_options(value, path=path + ".options")
      None => raise MissingField(path=path + ".options")
    }
    Select({ current_value, options })
  } else {
    let current_value = protocol_decode_boolean(
      protocol_required(fields, "currentValue", path=path + ".currentValue"),
      path=path + ".currentValue",
    )
    Boolean({ current_value, })
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { id, name, description, category, kind, meta }
}

///|
fn encode_config_options(
  values : Array[SessionConfigOption],
) -> Json raise ProtocolDecodeError {
  Json::array(
    values.map(fn(value) raise ProtocolDecodeError {
      encode_config_option(value)
    }),
  )
}

///|
fn decode_config_options(
  value : Json,
  path~ : String,
) -> Array[SessionConfigOption] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let options : Array[SessionConfigOption] = []
  for index, value in values {
    options.push(
      decode_config_option(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  options
}

///|
/// Decode a current-mode update from JSON.
pub fn current_mode_update_from_json(
  value : Json,
  path? : String = "currentMode",
) -> CurrentModeUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["currentModeId", "_meta"], prefix=path)
  let current_mode_id = protocol_required_string(
    fields,
    "currentModeId",
    path=path + ".currentModeId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { current_mode_id, meta }
}

///|
/// Encode a current-mode update as JSON.
pub fn current_mode_update_to_json(
  value : CurrentModeUpdate,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["currentModeId"] = Json::string(value.current_mode_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode a configuration-options update from JSON.
pub fn config_option_update_from_json(
  value : Json,
  path? : String = "configOptions",
) -> ConfigOptionUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["configOptions", "_meta"], prefix=path)
  let config_options = match fields.get("configOptions") {
    Some(value) => decode_config_options(value, path=path + ".configOptions")
    None => raise MissingField(path=path + ".configOptions")
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { config_options, meta }
}

///|
/// Encode a configuration-options update as JSON.
pub fn config_option_update_to_json(
  value : ConfigOptionUpdate,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["configOptions"] = encode_config_options(value.config_options)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode a session-information update from JSON.
pub fn session_info_update_from_json(
  value : Json,
  path? : String = "sessionInfo",
) -> SessionInfoUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["title", "updatedAt", "_meta"], prefix=path)
  let title = protocol_nullable_string(fields, "title", path=path + ".title")
  let updated_at = protocol_nullable_string(
    fields,
    "updatedAt",
    path=path + ".updatedAt",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { title, updated_at, meta }
}

///|
/// Encode a session-information update as JSON.
pub fn session_info_update_to_json(
  value : SessionInfoUpdate,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_nullable(fields, "title", value.title, value => {
    Json::string(value)
  })
  protocol_put_nullable(fields, "updatedAt", value.updated_at, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode session metadata from JSON.
pub fn session_info_from_json(
  value : Json,
  path? : String = "sessionInfo",
) -> SessionInfo raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["sessionId", "cwd", "additionalDirectories", "title", "updatedAt", "_meta"],
    prefix=path,
  )
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let cwd = protocol_required_string(fields, "cwd", path=path + ".cwd")
  let cwd = protocol_validate_absolute_path(cwd, field_path=path + ".cwd")
  let additional_directories : ProtocolNullable[Array[String]] = match
    protocol_field(fields, "additionalDirectories") {
    Omitted => Omitted
    Null =>
      raise InvalidField(
        path=path + ".additionalDirectories",
        reason="additionalDirectories is not nullable",
      )
    Value(value) => {
      let values = protocol_require_array(
        value,
        path=path + ".additionalDirectories",
      )
      let directories : Array[String] = []
      for index, value in values {
        let item_path = path +
          ".additionalDirectories[" +
          index.to_string() +
          "]"
        let directory = protocol_decode_string(value, path=item_path)
        directories.push(
          protocol_validate_absolute_path(directory, field_path=item_path),
        )
      }
      Value(directories)
    }
  }
  let title = protocol_nullable_string(fields, "title", path=path + ".title")
  let updated_at = protocol_nullable_string(
    fields,
    "updatedAt",
    path=path + ".updatedAt",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, cwd, additional_directories, title, updated_at, meta }
}

///|
/// Encode session metadata as JSON.
pub fn session_info_to_json(
  value : SessionInfo,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["cwd"] = Json::string(
    protocol_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  match value.additional_directories {
    Omitted => ()
    Null =>
      raise InvalidField(
        path="additionalDirectories",
        reason="additionalDirectories is not nullable",
      )
    Value(values) => {
      let encoded : Array[Json] = []
      for value in values {
        encoded.push(
          Json::string(
            protocol_validate_absolute_path(
              value,
              field_path="additionalDirectories",
            ),
          ),
        )
      }
      fields["additionalDirectories"] = Json::array(encoded)
    }
  }
  protocol_put_nullable(fields, "title", value.title, value => {
    Json::string(value)
  })
  protocol_put_nullable(fields, "updatedAt", value.updated_at, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn add_session_update_discriminator(
  value : Json,
  kind : String,
) -> Json raise ProtocolDecodeError {
  match value {
    Object(fields) => {
      fields["sessionUpdate"] = Json::string(kind)
      Json::object(fields)
    }
    _ =>
      raise InvalidField(
        path="sessionUpdate",
        reason="encoded session update must be an object",
      )
  }
}

///|
fn without_session_update(fields : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for key, value in fields {
    if key != "sessionUpdate" {
      result[key] = value
    }
  }
  result
}

///|
fn payload_without_session_update(fields : Map[String, Json]) -> Json {
  Json::object(without_session_update(fields))
}

///|
/// Encode one stable v1 session update variant.
pub fn session_update_to_json(
  value : SessionUpdate,
) -> Json raise ProtocolDecodeError {
  match value {
    UserMessageChunk(value) =>
      add_session_update_discriminator(
        content_chunk_to_json(value),
        "user_message_chunk",
      )
    AgentMessageChunk(value) =>
      add_session_update_discriminator(
        content_chunk_to_json(value),
        "agent_message_chunk",
      )
    AgentThoughtChunk(value) =>
      add_session_update_discriminator(
        content_chunk_to_json(value),
        "agent_thought_chunk",
      )
    ToolCall(value) =>
      add_session_update_discriminator(tool_call_to_json(value), "tool_call")
    ToolCallUpdate(value) =>
      add_session_update_discriminator(
        tool_call_update_to_json(value),
        "tool_call_update",
      )
    Plan(value) => add_session_update_discriminator(plan_to_json(value), "plan")
    AvailableCommandsUpdate(value) =>
      add_session_update_discriminator(
        available_commands_update_to_json(value),
        "available_commands_update",
      )
    CurrentModeUpdate(value) =>
      add_session_update_discriminator(
        current_mode_update_to_json(value),
        "current_mode_update",
      )
    ConfigOptionUpdate(value) =>
      add_session_update_discriminator(
        config_option_update_to_json(value),
        "config_option_update",
      )
    SessionInfoUpdate(value) =>
      add_session_update_discriminator(
        session_info_update_to_json(value),
        "session_info_update",
      )
    UsageUpdate(value) =>
      add_session_update_discriminator(
        usage_update_to_json(value),
        "usage_update",
      )
  }
}

///|
/// Decode one stable v1 session update variant.
pub fn session_update_from_json(
  value : Json,
  path? : String = "sessionUpdate",
) -> SessionUpdate raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let kind = protocol_required_string(
    fields,
    "sessionUpdate",
    path=path + ".sessionUpdate",
  )
  let payload = payload_without_session_update(fields)
  match kind {
    "user_message_chunk" =>
      UserMessageChunk(content_chunk_from_json(payload, path~))
    "agent_message_chunk" =>
      AgentMessageChunk(content_chunk_from_json(payload, path~))
    "agent_thought_chunk" =>
      AgentThoughtChunk(content_chunk_from_json(payload, path~))
    "tool_call" => ToolCall(tool_call_from_json(payload, path~))
    "tool_call_update" =>
      ToolCallUpdate(tool_call_update_from_json(payload, path~))
    "plan" => Plan(plan_from_json(payload, path~))
    "available_commands_update" =>
      AvailableCommandsUpdate(
        available_commands_update_from_json(payload, path~),
      )
    "current_mode_update" =>
      CurrentModeUpdate(current_mode_update_from_json(payload, path~))
    "config_option_update" =>
      ConfigOptionUpdate(config_option_update_from_json(payload, path~))
    "session_info_update" =>
      SessionInfoUpdate(session_info_update_from_json(payload, path~))
    "usage_update" => UsageUpdate(usage_update_from_json(payload, path~))
    _ => raise InvalidDiscriminator(path=path + ".sessionUpdate", value=kind)
  }
}

///|
/// Decode a plan entry from JSON.
pub fn plan_entry_from_json(
  value : Json,
  path? : String = "planEntry",
) -> PlanEntry raise ProtocolDecodeError {
  decode_plan_entry(value, path~)
}

///|
/// Encode a plan entry as JSON.
pub fn plan_entry_to_json(value : PlanEntry) -> Json raise ProtocolDecodeError {
  encode_plan_entry(value)
}

///|
/// Decode cost information from JSON.
pub fn cost_from_json(
  value : Json,
  path? : String = "cost",
) -> Cost raise ProtocolDecodeError {
  decode_cost(value, path~)
}

///|
/// Encode cost information as JSON.
pub fn cost_to_json(value : Cost) -> Json raise ProtocolDecodeError {
  encode_cost(value)
}

///|
/// Decode unstructured command input from JSON.
pub fn unstructured_command_input_from_json(
  value : Json,
  path? : String = "input",
) -> UnstructuredCommandInput raise ProtocolDecodeError {
  decode_unstructured_input(value, path~)
}

///|
/// Encode unstructured command input as JSON.
pub fn unstructured_command_input_to_json(
  value : UnstructuredCommandInput,
) -> Json raise ProtocolDecodeError {
  encode_unstructured_input(value)
}

///|
/// Decode a command input from JSON.
pub fn available_command_input_from_json(
  value : Json,
  path? : String = "input",
) -> AvailableCommandInput raise ProtocolDecodeError {
  decode_command_input(value, path~)
}

///|
/// Encode a command input as JSON.
pub fn available_command_input_to_json(
  value : AvailableCommandInput,
) -> Json raise ProtocolDecodeError {
  encode_command_input(value)
}

///|
/// Decode a session configuration category from JSON.
pub fn session_config_option_category_from_json(
  value : Json,
  path? : String = "category",
) -> SessionConfigOptionCategory raise ProtocolDecodeError {
  decode_config_category(value, path~)
}

///|
/// Encode a session configuration category as JSON.
pub fn session_config_option_category_to_json(
  value : SessionConfigOptionCategory,
) -> Json {
  encode_config_category(value)
}

///|
/// Decode a selectable configuration option from JSON.
pub fn session_config_select_option_from_json(
  value : Json,
  path? : String = "option",
) -> SessionConfigSelectOption raise ProtocolDecodeError {
  decode_select_option(value, path~)
}

///|
/// Encode a selectable configuration option as JSON.
pub fn session_config_select_option_to_json(
  value : SessionConfigSelectOption,
) -> Json raise ProtocolDecodeError {
  encode_select_option(value)
}

///|
/// Decode a selectable configuration group from JSON.
pub fn session_config_select_group_from_json(
  value : Json,
  path? : String = "group",
) -> SessionConfigSelectGroup raise ProtocolDecodeError {
  decode_select_group(value, path~)
}

///|
/// Encode a selectable configuration group as JSON.
pub fn session_config_select_group_to_json(
  value : SessionConfigSelectGroup,
) -> Json raise ProtocolDecodeError {
  encode_select_group(value)
}

///|
/// Decode selectable configuration values from JSON.
pub fn session_config_select_options_from_json(
  value : Json,
  path? : String = "options",
) -> SessionConfigSelectOptions raise ProtocolDecodeError {
  decode_select_options(value, path~)
}

///|
/// Encode selectable configuration values as JSON.
pub fn session_config_select_options_to_json(
  value : SessionConfigSelectOptions,
) -> Json raise ProtocolDecodeError {
  encode_select_options(value)
}

///|
/// Decode one complete configuration option from JSON.
pub fn session_config_option_from_json(
  value : Json,
  path? : String = "configOption",
) -> SessionConfigOption raise ProtocolDecodeError {
  decode_config_option(value, path~)
}

///|
/// Encode one complete configuration option as JSON.
pub fn session_config_option_to_json(
  value : SessionConfigOption,
) -> Json raise ProtocolDecodeError {
  encode_config_option(value)
}
