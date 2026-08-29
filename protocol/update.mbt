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
  { content, priority, status, meta, }
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
  { entries, meta, }
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
  { amount, currency, meta, }
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
  { used, size, cost, meta, }
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
  { hint, meta, }
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
    commands.push({ name, description, input, meta, })
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
  { available_commands, meta, }
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
  { value: option_value, name, description, meta, }
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
  { group, name, options, meta, }
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
    Select({ current_value, options, })
  } else {
    let current_value = protocol_decode_boolean(
      protocol_required(fields, "currentValue", path=path + ".currentValue"),
      path=path + ".currentValue",
    )
    Boolean({ current_value, })
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { id, name, description, category, kind, meta, }
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
  { current_mode_id, meta, }
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
  { config_options, meta, }
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
  { title, updated_at, meta, }
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
  { session_id, cwd, additional_directories, title, updated_at, meta, }
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

///|
/// Structured failures produced while folding typed session updates into
/// consumer state.
///
/// These are consumer-side aggregation failures, not wire decode failures:
/// malformed payloads are rejected earlier by `session_update_from_json`, so a
/// typed update that reaches the fold always decoded cleanly.
pub(all) suberror SessionUpdateFoldError {
  DuplicateToolCall(tool_call_id~ : String)
  UnknownToolCall(tool_call_id~ : String)
  UnknownMode(mode_id~ : String)
  InvalidTimestamp(field~ : String, value~ : String)
} derive(Eq, Debug)

///|
/// One message aggregated from streamed content chunks.
///
/// Chunks that carry the same `messageId` value fold into one message, in
/// arrival order.  The v1 schema pins the aggregation contract: all chunks
/// belonging to the same message share one `messageId`, and a change of
/// `messageId` starts a new message.  A chunk without a `messageId` value
/// (omitted or JSON null) cannot be correlated, so the fold records it as its
/// own standalone message instead of merging or overwriting anything.
pub(all) struct SessionUpdateMessage {
  message_id : ProtocolNullable[MessageId]
  blocks : Array[ContentBlock]
} derive(Eq, Debug)

///|
/// Pure per-session consumer state for a stream of typed session updates.
///
/// This is the consumer-side half of the `session/update` semantics (matrix
/// rows E01-E11): the codec in this file owns wire shape and tri-state
/// fidelity, while this fold owns aggregation and replacement semantics.  The
/// fold follows the same discipline as `connection/reducer.mbt`: it is a pure
/// function of `(state, update)`, allocates the next state without mutating
/// the input state, keeps no mutable registry, and holds no global state.
/// Each session owns one fold value, so a rejected update for one session can
/// never pollute another session's state.
///
/// Semantics per variant:
///
/// - `user_message_chunk` / `agent_message_chunk` / `agent_thought_chunk`
///   (E01-E03): chunks aggregate by `messageId` within their own kind bucket;
///   the three kinds never merge with each other.
/// - `tool_call` (E04): the first occurrence creates the tracked call keyed by
///   `toolCallId`; a duplicate id is a typed error, never an overwrite.
/// - `tool_call_update` (E05): present fields replace, omitted fields keep,
///   and JSON null clears the field back to the omitted state; an unknown
///   `toolCallId` is a typed error and never fabricates a new call.
/// - `plan` (E06), `available_commands_update` (E07), and
///   `config_option_update` (E09): each update is the complete replacement
///   set; the fold never append-merges entries or options.
/// - `current_mode_update` (E08): `currentModeId` is validated against the
///   caller-supplied `known_modes`.  Consistent with the C10 boundary, the
///   codec validates only shape; which modes exist is session knowledge the
///   consumer owns.  The fold is strict: an empty known-mode set rejects every
///   mode update rather than accepting a silent default mode.
/// - `session_info_update` (E10): `title`/`updatedAt` keep tri-state
///   semantics (omitted keeps, null clears, value sets) and an `updatedAt`
///   value must parse as an RFC 3339 / ISO 8601 extended timestamp.
/// - `usage_update` (E11): replaces the previously recorded usage; the
///     non-negative `used`/`size` invariant is enforced at the codec by the
///     unsigned integer decode.
pub(all) struct SessionUpdateFold {
  known_modes : Array[SessionModeId]
  user_messages : Array[SessionUpdateMessage]
  agent_messages : Array[SessionUpdateMessage]
  agent_thoughts : Array[SessionUpdateMessage]
  tool_calls : Array[ToolCall]
  plan : Plan?
  available_commands : Array[AvailableCommand]
  current_mode_id : SessionModeId?
  config_options : Array[SessionConfigOption]
  session_title : ProtocolNullable[String]
  session_updated_at : ProtocolNullable[String]
  usage : UsageUpdate?
} derive(Eq, Debug)

///|
/// Create the initial consumer state for one session.
///
/// `known_modes` is the immutable mode set the consumer knows for the session
/// (typically `SessionModeState.available_modes` from `session/new`); it is
/// only read by `current_mode_update` validation and is never modified by any
/// applied update.
pub fn session_update_fold(
  known_modes~ : Array[SessionModeId],
) -> SessionUpdateFold {
  {
    known_modes: known_modes.copy(),
    user_messages: [],
    agent_messages: [],
    agent_thoughts: [],
    tool_calls: [],
    plan: None,
    available_commands: [],
    current_mode_id: None,
    config_options: [],
    session_title: Omitted,
    session_updated_at: Omitted,
    usage: None,
  }
}

///|
/// Apply strict `tool_call_update` patch semantics to one nullable field: a
/// present value replaces the previous value, JSON null clears the field back
/// to the omitted state, and an omitted field keeps the previous value.
fn[T] session_update_patch_field(
  current : ProtocolNullable[T],
  patch : ProtocolNullable[T],
) -> ProtocolNullable[T] {
  match patch {
    Omitted => current
    Null => Omitted
    Value(_) => patch
  }
}

///|
/// Patch semantics for nullable collection fields.  Identical to
/// `session_update_patch_field` except that a replaced collection is copied,
/// so the fold never aliases an array the caller could later mutate.
fn[T] session_update_patch_collection(
  current : ProtocolNullable[Array[T]],
  patch : ProtocolNullable[Array[T]],
) -> ProtocolNullable[Array[T]] {
  match patch {
    Omitted => current
    Null => Omitted
    Value(values) => Value(values.copy())
  }
}

///|
/// Fold one resolved tool call update into its tracked call.
///
/// A null `title` patch keeps the creation title: the v1 `ToolCall` record
/// requires a title, the consumer state cannot represent a title-less call,
/// and the fold never fabricates an empty title to simulate a clear.
fn session_update_patch_tool_call(
  call : ToolCall,
  patch : ToolCallUpdate,
) -> ToolCall {
  {
    tool_call_id: call.tool_call_id,
    title: match patch.title {
      Value(title) => title
      _ => call.title
    },
    kind: session_update_patch_field(call.kind, patch.kind),
    status: session_update_patch_field(call.status, patch.status),
    content: session_update_patch_collection(call.content, patch.content),
    locations: session_update_patch_collection(call.locations, patch.locations),
    raw_input: session_update_patch_field(call.raw_input, patch.raw_input),
    raw_output: session_update_patch_field(call.raw_output, patch.raw_output),
    meta: session_update_patch_field(call.meta, patch.meta),
  }
}

///|
/// Locate a tracked message by its `messageId` value.
fn session_update_message_index(
  messages : Array[SessionUpdateMessage],
  message_id : MessageId,
) -> Int? {
  for index, message in messages {
    match message.message_id {
      Value(id) => if id == message_id { return Some(index) }
      _ => ()
    }
  }
  None
}

///|
/// Fold one streamed chunk into a message bucket (E01-E03).
///
/// A chunk whose `messageId` carries a value appends to the message with that
/// id, creating it on first occurrence; a change of id therefore starts a new
/// message while earlier messages keep their blocks.  A chunk without a
/// `messageId` value becomes its own standalone message because nothing on
/// the wire correlates it with an existing one.
fn session_update_append_chunk(
  messages : Array[SessionUpdateMessage],
  chunk : ContentChunk,
) -> Array[SessionUpdateMessage] {
  match chunk.message_id {
    Value(id) => {
      let next = messages.copy()
      match session_update_message_index(messages, id) {
        Some(index) => {
          let message = next[index]
          let blocks = message.blocks.copy()
          blocks.push(chunk.content)
          next[index] = { message_id: message.message_id, blocks, }
        }
        None =>
          next.push({ message_id: chunk.message_id, blocks: [chunk.content], })
      }
      next
    }
    _ => {
      let next = messages.copy()
      next.push({ message_id: chunk.message_id, blocks: [chunk.content], })
      next
    }
  }
}

///|
/// Locate a tracked tool call by its `toolCallId`.
fn session_update_tool_call_index(
  calls : Array[ToolCall],
  tool_call_id : ToolCallId,
) -> Int? {
  for index, call in calls {
    if call.tool_call_id == tool_call_id {
      return Some(index)
    }
  }
  None
}

///|
/// Report whether the caller-supplied known-mode set contains `mode_id`.
fn session_update_mode_known(
  known_modes : Array[SessionModeId],
  mode_id : SessionModeId,
) -> Bool {
  let mut known = false
  for mode in known_modes {
    if mode == mode_id {
      known = true
      break
    }
  }
  known
}

///|
/// Read one ASCII digit at `index`, or `None` when out of range or not a
/// digit.
fn session_update_timestamp_digit(chars : Array[Char], index : Int) -> Int? {
  if index >= chars.length() {
    None
  } else if protocol_is_digit(chars[index]) {
    Some(chars[index].to_int() - '0')
  } else {
    None
  }
}

///|
/// Read a two-digit zero-padded number at `index`.
fn session_update_timestamp_pair(chars : Array[Char], index : Int) -> Int? {
  match
    (
      session_update_timestamp_digit(chars, index),
      session_update_timestamp_digit(chars, index + 1),
    ) {
    (Some(high), Some(low)) => Some(high * 10 + low)
    _ => None
  }
}

///|
/// Read the four-digit year at the start of a timestamp.
fn session_update_timestamp_year(chars : Array[Char]) -> Int? {
  match
    (
      session_update_timestamp_digit(chars, 0),
      session_update_timestamp_digit(chars, 1),
      session_update_timestamp_digit(chars, 2),
      session_update_timestamp_digit(chars, 3),
    ) {
    (Some(a), Some(b), Some(c), Some(d)) =>
      Some(a * 1000 + b * 100 + c * 10 + d)
    _ => None
  }
}

///|
/// Proleptic Gregorian leap-year test for day-of-month validation.
fn session_update_is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// Days in one month; an out-of-range month yields 0 so the caller's day
/// check fails.
fn session_update_days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if session_update_is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
/// Validate the timezone designator starting at `start`: `Z`/`z`, or a
/// numeric offset `±HH:MM` within range.  The timestamp must end there.
fn session_update_timestamp_offset_valid(
  chars : Array[Char],
  start : Int,
) -> Bool {
  let length = chars.length()
  if start >= length {
    return false
  }
  match chars[start] {
    'Z' | 'z' => start + 1 == length
    '+' | '-' =>
      match
        (
          session_update_timestamp_pair(chars, start + 1),
          session_update_timestamp_pair(chars, start + 4),
        ) {
        (Some(hour), Some(minute)) =>
          if start + 3 < length && chars[start + 3] == ':' {
            hour <= 23 && minute <= 59 && start + 6 == length
          } else {
            false
          }
        _ => false
      }
    _ => false
  }
}

///|
/// Strict shape check for the RFC 3339 / ISO 8601 extended calendar form the
/// v1 schema requires for `updatedAt`:
/// `YYYY-MM-DDTHH:MM:SS[.fraction](Z|±HH:MM)` with `T`/`t` and `Z`/`z`
/// accepted, zero-padded two-digit fields, calendar-valid month and day
/// (leap-year aware), and seconds up to 60 for leap seconds.  This is a
/// shape/parse gate only; it does not normalize or rewrite the value.
fn session_update_is_valid_timestamp(value : String) -> Bool {
  let chars = value.to_array()
  let length = chars.length()
  if length < 20 {
    return false
  }
  if chars[4] != '-' || chars[7] != '-' {
    return false
  }
  if chars[10] != 'T' && chars[10] != 't' {
    return false
  }
  if chars[13] != ':' || chars[16] != ':' {
    return false
  }
  let date_valid = match
    (
      session_update_timestamp_year(chars),
      session_update_timestamp_pair(chars, 5),
      session_update_timestamp_pair(chars, 8),
      session_update_timestamp_pair(chars, 11),
      session_update_timestamp_pair(chars, 14),
      session_update_timestamp_pair(chars, 17),
    ) {
    (Some(year), Some(month), Some(day), Some(hour), Some(minute), Some(second)) =>
      month >= 1 &&
      month <= 12 &&
      day >= 1 &&
      day <= session_update_days_in_month(year, month) &&
      hour <= 23 &&
      minute <= 59 &&
      second <= 60
    _ => false
  }
  if !date_valid {
    return false
  }
  let mut offset_start = 19
  if offset_start < length && chars[offset_start] == '.' {
    offset_start += 1
    let fraction_start = offset_start
    while offset_start < length && protocol_is_digit(chars[offset_start]) {
      offset_start += 1
    }
    if offset_start == fraction_start {
      return false
    }
  }
  session_update_timestamp_offset_valid(chars, offset_start)
}

///|
/// Apply one typed session update to consumer state, returning either the
/// next state or a typed rejection.  The input state is never mutated, so a
/// caller that keeps the previous value still observes it unchanged after a
/// rejection.
pub fn session_update_apply(
  state : SessionUpdateFold,
  update : SessionUpdate,
) -> Result[SessionUpdateFold, SessionUpdateFoldError] {
  match update {
    UserMessageChunk(chunk) =>
      Ok({
        ..state,
        user_messages: session_update_append_chunk(state.user_messages, chunk),
      })
    AgentMessageChunk(chunk) =>
      Ok({
        ..state,
        agent_messages: session_update_append_chunk(state.agent_messages, chunk),
      })
    AgentThoughtChunk(chunk) =>
      Ok({
        ..state,
        agent_thoughts: session_update_append_chunk(state.agent_thoughts, chunk),
      })
    ToolCall(call) =>
      match
        session_update_tool_call_index(state.tool_calls, call.tool_call_id) {
        Some(_) => Err(DuplicateToolCall(tool_call_id=call.tool_call_id))
        None => {
          let calls = state.tool_calls.copy()
          calls.push(call)
          Ok({ ..state, tool_calls: calls, })
        }
      }
    ToolCallUpdate(patch) =>
      match
        session_update_tool_call_index(state.tool_calls, patch.tool_call_id) {
        Some(index) => {
          let calls = state.tool_calls.copy()
          calls[index] = session_update_patch_tool_call(calls[index], patch)
          Ok({ ..state, tool_calls: calls, })
        }
        None => Err(UnknownToolCall(tool_call_id=patch.tool_call_id))
      }
    Plan(value) => Ok({ ..state, plan: Some(value), })
    AvailableCommandsUpdate(value) =>
      Ok({ ..state, available_commands: value.available_commands.copy(), })
    CurrentModeUpdate(value) =>
      if session_update_mode_known(state.known_modes, value.current_mode_id) {
        Ok({ ..state, current_mode_id: Some(value.current_mode_id), })
      } else {
        Err(UnknownMode(mode_id=value.current_mode_id))
      }
    ConfigOptionUpdate(value) =>
      Ok({ ..state, config_options: value.config_options.copy(), })
    SessionInfoUpdate(value) => {
      let title = match value.title {
        Omitted => state.session_title
        updated => updated
      }
      let updated_at = match value.updated_at {
        Omitted => state.session_updated_at
        Null => Null
        Value(timestamp) =>
          if session_update_is_valid_timestamp(timestamp) {
            Value(timestamp)
          } else {
            return Err(InvalidTimestamp(field="updatedAt", value=timestamp))
          }
      }
      Ok({ ..state, session_title: title, session_updated_at: updated_at, })
    }
    UsageUpdate(value) => Ok({ ..state, usage: Some(value), })
  }
}
