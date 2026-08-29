///|
/// Why foreground work stopped.  `stopReason` values are an open set: `_`
/// prefixes are implementation extensions and other unknown values are future
/// ACP variants.
pub(all) enum ExperimentalV2StopReason {
  StopReasonEndTurn
  StopReasonMaxTokens
  StopReasonMaxTurnRequests
  StopReasonRefusal
  StopReasonCancelled
  StopReasonExtension(tag~ : String)
  StopReasonFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_stop_reason(
  value : Json,
  path? : String = "stopReason",
) -> ExperimentalV2StopReason raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "end_turn" => StopReasonEndTurn
    "max_tokens" => StopReasonMaxTokens
    "max_turn_requests" => StopReasonMaxTurnRequests
    "refusal" => StopReasonRefusal
    "cancelled" => StopReasonCancelled
    _ =>
      if tag.has_prefix("_") {
        StopReasonExtension(tag~)
      } else {
        StopReasonFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_stop_reason(
  value : ExperimentalV2StopReason,
) -> Json {
  match value {
    StopReasonEndTurn => Json::string("end_turn")
    StopReasonMaxTokens => Json::string("max_tokens")
    StopReasonMaxTurnRequests => Json::string("max_turn_requests")
    StopReasonRefusal => Json::string("refusal")
    StopReasonCancelled => Json::string("cancelled")
    StopReasonExtension(tag~) => Json::string(tag)
    StopReasonFuture(raw~) => Json::string(raw)
  }
}

///|
/// `state_update` payload for `state: "running"`: foreground work is in
/// progress and no other fields are defined.
pub(all) struct ExperimentalV2RunningState {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_running_state(
  value : Json,
  path? : String = "state_update",
) -> ExperimentalV2RunningState raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta"), }
}

///|
pub fn experimental_v2_encode_running_state(
  value : ExperimentalV2RunningState,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// `state_update` payload for `state: "idle"`: `stop_reason` is omitted or
/// null when the agent reports no stop reason.
pub(all) struct ExperimentalV2IdleState {
  stop_reason : ExperimentalV2StopReason?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_idle_state(
  value : Json,
  path? : String = "state_update",
) -> ExperimentalV2IdleState raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["stopReason", "_meta"], prefix=path)
  let stop_reason = experimental_v2_decode_optional(
    fields,
    "stopReason",
    path=path + ".stopReason",
    (value, path) => experimental_v2_decode_stop_reason(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { stop_reason, meta, }
}

///|
pub fn experimental_v2_encode_idle_state(
  value : ExperimentalV2IdleState,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_optional(fields, "stopReason", value.stop_reason, reason => {
    experimental_v2_encode_stop_reason(reason)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// `state_update` payload for `state: "requires_action"`: foreground work is
/// blocked on user action and no other fields are defined.
pub(all) struct ExperimentalV2RequiresActionState {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_requires_action_state(
  value : Json,
  path? : String = "state_update",
) -> ExperimentalV2RequiresActionState raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta"), }
}

///|
pub fn experimental_v2_encode_requires_action_state(
  value : ExperimentalV2RequiresActionState,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Known payloads of a `state_update`; the `state` discriminator is an open
/// union so unknown states stay as `Extension`/`Future` raw payloads.
pub(all) enum ExperimentalV2StateUpdateKnown {
  StateRunning(ExperimentalV2RunningState)
  StateIdle(ExperimentalV2IdleState)
  StateRequiresAction(ExperimentalV2RequiresActionState)
} derive(Eq, Debug)

///|
pub type ExperimentalV2StateUpdate = ExperimentalV2Open[
  ExperimentalV2StateUpdateKnown,
]

///|
pub fn experimental_v2_decode_state_update(
  value : Json,
  path? : String = "state_update",
) -> ExperimentalV2StateUpdate raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="state",
    ["running", "idle", "requires_action"],
    (tag, payload) => {
      let untagged = experimental_v2_untag_payload(
        payload,
        tag_key="state",
        path~,
      )
      match tag {
        "running" =>
          StateRunning(experimental_v2_decode_running_state(untagged, path~))
        "idle" => StateIdle(experimental_v2_decode_idle_state(untagged, path~))
        "requires_action" =>
          StateRequiresAction(
            experimental_v2_decode_requires_action_state(untagged, path~),
          )
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".state", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_state_update(
  value : ExperimentalV2StateUpdate,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="state", known => {
    match known {
      StateRunning(state) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_running_state(state),
          tag_key="state",
          tag="running",
        )
      StateIdle(state) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_idle_state(state),
          tag_key="state",
          tag="idle",
        )
      StateRequiresAction(state) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_requires_action_state(state),
          tag_key="state",
          tag="requires_action",
        )
    }
  })
}

///|
/// Whole-message upsert shared by `user_message`, `agent_message`, and
/// `agent_thought`.  Only `message_id` (agent-owned) is required; `content`
/// has patch semantics where omitted keeps the accumulated content, null and
/// `[]` both clear it, and a concrete array replaces it wholesale.
pub(all) struct ExperimentalV2MessageUpsert {
  message_id : String
  content : ExperimentalV2Patch[Array[ExperimentalV2ContentBlock]]
  meta : ExperimentalV2Patch[Json]
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_message_upsert(
  value : Json,
  path? : String = "message",
) -> ExperimentalV2MessageUpsert raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["messageId", "content", "_meta"],
    prefix=path,
  )
  let message_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "messageId", path=path + ".messageId"),
      path=path + ".messageId",
    ),
    field_path=path + ".messageId",
  )
  let content = experimental_v2_decode_patch(
    fields,
    "content",
    path=path + ".content",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_content_block(item, path=item_path)
      })
    },
  )
  let meta = experimental_v2_top_meta(fields, path=path + "._meta")
  { message_id, content, meta, }
}

///|
pub fn experimental_v2_encode_message_upsert(
  value : ExperimentalV2MessageUpsert,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["messageId"] = Json::string(value.message_id)
  experimental_v2_put_patch(fields, "content", value.content, values => {
    experimental_v2_encode_array(values, experimental_v2_encode_content_block)
  })
  experimental_v2_put_top_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Priority of one plan entry; open set with `_` extensions and future
/// values.
pub(all) enum ExperimentalV2PlanEntryPriority {
  PlanPriorityHigh
  PlanPriorityMedium
  PlanPriorityLow
  PlanPriorityExtension(tag~ : String)
  PlanPriorityFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_plan_entry_priority(
  value : Json,
  path? : String = "priority",
) -> ExperimentalV2PlanEntryPriority raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "high" => PlanPriorityHigh
    "medium" => PlanPriorityMedium
    "low" => PlanPriorityLow
    _ =>
      if tag.has_prefix("_") {
        PlanPriorityExtension(tag~)
      } else {
        PlanPriorityFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_plan_entry_priority(
  value : ExperimentalV2PlanEntryPriority,
) -> Json {
  match value {
    PlanPriorityHigh => Json::string("high")
    PlanPriorityMedium => Json::string("medium")
    PlanPriorityLow => Json::string("low")
    PlanPriorityExtension(tag~) => Json::string(tag)
    PlanPriorityFuture(raw~) => Json::string(raw)
  }
}

///|
/// Status of one plan entry; v2 adds `cancelled` over the v1 set, and the
/// set stays open for `_` extensions and future values.
pub(all) enum ExperimentalV2PlanEntryStatus {
  PlanStatusPending
  PlanStatusInProgress
  PlanStatusCompleted
  PlanStatusCancelled
  PlanStatusExtension(tag~ : String)
  PlanStatusFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_plan_entry_status(
  value : Json,
  path? : String = "status",
) -> ExperimentalV2PlanEntryStatus raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "pending" => PlanStatusPending
    "in_progress" => PlanStatusInProgress
    "completed" => PlanStatusCompleted
    "cancelled" => PlanStatusCancelled
    _ =>
      if tag.has_prefix("_") {
        PlanStatusExtension(tag~)
      } else {
        PlanStatusFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_plan_entry_status(
  value : ExperimentalV2PlanEntryStatus,
) -> Json {
  match value {
    PlanStatusPending => Json::string("pending")
    PlanStatusInProgress => Json::string("in_progress")
    PlanStatusCompleted => Json::string("completed")
    PlanStatusCancelled => Json::string("cancelled")
    PlanStatusExtension(tag~) => Json::string(tag)
    PlanStatusFuture(raw~) => Json::string(raw)
  }
}

///|
/// One task entry of an items-based plan; `content`, `priority`, and `status`
/// are all required on the wire.
pub(all) struct ExperimentalV2PlanEntry {
  content : String
  priority : ExperimentalV2PlanEntryPriority
  status : ExperimentalV2PlanEntryStatus
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_plan_entry(
  value : Json,
  path? : String = "planEntry",
) -> ExperimentalV2PlanEntry raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["content", "priority", "status", "_meta"],
    prefix=path,
  )
  let content = experimental_v2_decode_string(
    experimental_v2_required(fields, "content", path=path + ".content"),
    path=path + ".content",
  )
  let priority = experimental_v2_decode_plan_entry_priority(
    experimental_v2_required(fields, "priority", path=path + ".priority"),
    path=path + ".priority",
  )
  let status = experimental_v2_decode_plan_entry_status(
    experimental_v2_required(fields, "status", path=path + ".status"),
    path=path + ".status",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { content, priority, status, meta, }
}

///|
pub fn experimental_v2_encode_plan_entry(
  value : ExperimentalV2PlanEntry,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["content"] = Json::string(value.content)
  fields["priority"] = experimental_v2_encode_plan_entry_priority(
    value.priority,
  )
  fields["status"] = experimental_v2_encode_plan_entry_status(value.status)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// An items-based plan: `entries` is the complete replacement list for the
/// plan identified by `plan_id`; the client swaps the whole plan on each
/// update.
pub(all) struct ExperimentalV2PlanItems {
  plan_id : String
  entries : Array[ExperimentalV2PlanEntry]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_plan_items(
  value : Json,
  path? : String = "plan",
) -> ExperimentalV2PlanItems raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["planId", "entries", "_meta"],
    prefix=path,
  )
  let plan_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "planId", path=path + ".planId"),
      path=path + ".planId",
    ),
    field_path=path + ".planId",
  )
  let entries = experimental_v2_decode_array(
    experimental_v2_required(fields, "entries", path=path + ".entries"),
    path=path + ".entries",
    (item, item_path) => experimental_v2_decode_plan_entry(item, path=item_path),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { plan_id, entries, meta, }
}

///|
pub fn experimental_v2_encode_plan_items(
  value : ExperimentalV2PlanItems,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["planId"] = Json::string(value.plan_id)
  fields["entries"] = experimental_v2_encode_array(
    value.entries,
    experimental_v2_encode_plan_entry,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Known payloads of a plan update content; the `type` discriminator is an
/// open union so unknown plan kinds stay as raw payloads.
pub(all) enum ExperimentalV2PlanUpdateContentKnown {
  PlanItemsContent(ExperimentalV2PlanItems)
} derive(Eq, Debug)

///|
pub type ExperimentalV2PlanUpdateContent = ExperimentalV2Open[
  ExperimentalV2PlanUpdateContentKnown,
]

///|
pub fn experimental_v2_decode_plan_update_content(
  value : Json,
  path? : String = "plan",
) -> ExperimentalV2PlanUpdateContent raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["items"],
    (tag, payload) => {
      match tag {
        "items" =>
          PlanItemsContent(
            experimental_v2_decode_plan_items(
              experimental_v2_untag_payload(payload, tag_key="type", path~),
              path~,
            ),
          )
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".type", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_plan_update_content(
  value : ExperimentalV2PlanUpdateContent,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    match known {
      PlanItemsContent(items) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_plan_items(items),
          tag_key="type",
          tag="items",
        )
    }
  })
}

///|
/// A `plan_update`: the content for the plan identified inside `plan`.
pub(all) struct ExperimentalV2PlanUpdate {
  plan : ExperimentalV2PlanUpdateContent
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_plan_update(
  value : Json,
  path? : String = "plan_update",
) -> ExperimentalV2PlanUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["plan", "_meta"], prefix=path)
  let plan = experimental_v2_decode_plan_update_content(
    experimental_v2_required(fields, "plan", path=path + ".plan"),
    path=path + ".plan",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { plan, meta, }
}

///|
pub fn experimental_v2_encode_plan_update(
  value : ExperimentalV2PlanUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["plan"] = experimental_v2_encode_plan_update_content(value.plan)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Known payloads of a command input specification; the `type` discriminator
/// is an open union so unknown input kinds stay as raw payloads.
pub(all) enum ExperimentalV2CommandInputKnown {
  CommandInputText(ExperimentalV2TextCommandInput)
} derive(Eq, Debug)

///|
/// Text input for a command: everything typed after the command name.
pub(all) struct ExperimentalV2TextCommandInput {
  hint : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_text_command_input(
  value : Json,
  path? : String = "input",
) -> ExperimentalV2TextCommandInput raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["hint", "_meta"], prefix=path)
  let hint = experimental_v2_decode_string(
    experimental_v2_required(fields, "hint", path=path + ".hint"),
    path=path + ".hint",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { hint, meta, }
}

///|
pub fn experimental_v2_encode_text_command_input(
  value : ExperimentalV2TextCommandInput,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["hint"] = Json::string(value.hint)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
pub type ExperimentalV2CommandInput = ExperimentalV2Open[
  ExperimentalV2CommandInputKnown,
]

///|
pub fn experimental_v2_decode_command_input(
  value : Json,
  path? : String = "input",
) -> ExperimentalV2CommandInput raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["text"],
    (tag, payload) => {
      match tag {
        "text" =>
          CommandInputText(
            experimental_v2_decode_text_command_input(
              experimental_v2_untag_payload(payload, tag_key="type", path~),
              path~,
            ),
          )
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".type", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_command_input(
  value : ExperimentalV2CommandInput,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    match known {
      CommandInputText(text) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_text_command_input(text),
          tag_key="type",
          tag="text",
        )
    }
  })
}

///|
/// One command the agent can execute; `input` is the input specification when
/// the command requires one and omitted or null otherwise.
pub(all) struct ExperimentalV2AvailableCommand {
  name : String
  description : String
  input : ExperimentalV2CommandInput?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_available_command(
  value : Json,
  path? : String = "availableCommand",
) -> ExperimentalV2AvailableCommand raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["name", "description", "input", "_meta"],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let description = experimental_v2_decode_string(
    experimental_v2_required(fields, "description", path=path + ".description"),
    path=path + ".description",
  )
  let input = experimental_v2_decode_optional(
    fields,
    "input",
    path=path + ".input",
    (value, path) => experimental_v2_decode_command_input(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, description, input, meta, }
}

///|
pub fn experimental_v2_encode_available_command(
  value : ExperimentalV2AvailableCommand,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["description"] = Json::string(value.description)
  experimental_v2_put_optional(
    fields,
    "input",
    value.input,
    experimental_v2_encode_command_input,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The complete set of commands the agent can currently execute; each update
/// replaces the whole list.
pub(all) struct ExperimentalV2AvailableCommandsUpdate {
  available_commands : Array[ExperimentalV2AvailableCommand]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_available_commands_update(
  value : Json,
  path? : String = "available_commands_update",
) -> ExperimentalV2AvailableCommandsUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["availableCommands", "_meta"],
    prefix=path,
  )
  let available_commands = experimental_v2_decode_array(
    experimental_v2_required(
      fields,
      "availableCommands",
      path=path + ".availableCommands",
    ),
    path=path + ".availableCommands",
    (item, item_path) => {
      experimental_v2_decode_available_command(item, path=item_path)
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { available_commands, meta, }
}

///|
pub fn experimental_v2_encode_available_commands_update(
  value : ExperimentalV2AvailableCommandsUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["availableCommands"] = experimental_v2_encode_array(
    value.available_commands,
    experimental_v2_encode_available_command,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The full current configuration option set; each update replaces the whole
/// set.
pub(all) struct ExperimentalV2ConfigOptionUpdate {
  config_options : Array[ExperimentalV2SessionConfigOption]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_config_option_update(
  value : Json,
  path? : String = "config_option_update",
) -> ExperimentalV2ConfigOptionUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["configOptions", "_meta"],
    prefix=path,
  )
  let config_options = experimental_v2_decode_array(
    experimental_v2_required(
      fields,
      "configOptions",
      path=path + ".configOptions",
    ),
    path=path + ".configOptions",
    (item, item_path) => {
      experimental_v2_decode_config_option(item, path=item_path)
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { config_options, meta, }
}

///|
pub fn experimental_v2_encode_config_option_update(
  value : ExperimentalV2ConfigOptionUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["configOptions"] = experimental_v2_encode_array(
    value.config_options,
    experimental_v2_encode_config_option,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Partial session metadata update: every field is a patch tri-state where
/// omitted keeps the stored value, null clears it, and a value replaces it.
pub(all) struct ExperimentalV2SessionInfoUpdate {
  title : ExperimentalV2Patch[String]
  updated_at : ExperimentalV2Patch[String]
  meta : ExperimentalV2Patch[Json]
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_session_info_update(
  value : Json,
  path? : String = "session_info_update",
) -> ExperimentalV2SessionInfoUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["title", "updatedAt", "_meta"],
    prefix=path,
  )
  let title = experimental_v2_decode_patch(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let updated_at = experimental_v2_decode_patch(
    fields,
    "updatedAt",
    path=path + ".updatedAt",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let meta = experimental_v2_top_meta(fields, path=path + "._meta")
  { title, updated_at, meta, }
}

///|
pub fn experimental_v2_encode_session_info_update(
  value : ExperimentalV2SessionInfoUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_patch(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_patch(fields, "updatedAt", value.updated_at, value => {
    Json::string(value)
  })
  experimental_v2_put_top_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Cumulative session cost; `currency` is a three-letter ISO 4217 code.
pub(all) struct ExperimentalV2Cost {
  amount : Double
  currency : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_cost(
  value : Json,
  path? : String = "cost",
) -> ExperimentalV2Cost raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["amount", "currency", "_meta"],
    prefix=path,
  )
  let amount = experimental_v2_decode_finite_number(
    experimental_v2_required(fields, "amount", path=path + ".amount"),
    path=path + ".amount",
  )
  let currency = experimental_v2_validate_currency(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "currency", path=path + ".currency"),
      path=path + ".currency",
    ),
    field_path=path + ".currency",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { amount, currency, meta, }
}

///|
pub fn experimental_v2_encode_cost(
  value : ExperimentalV2Cost,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["amount"] = Json::number(value.amount)
  fields["currency"] = Json::string(
    experimental_v2_validate_currency(value.currency, field_path="currency"),
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn experimental_v2_validate_currency(
  value : String,
  field_path~ : String,
) -> String raise ExperimentalV2DecodeError {
  let chars = value.to_array()
  if chars.length() == 3 {
    let mut upper = true
    for ch in chars {
      if ch < 'A' || ch > 'Z' {
        upper = false
        break
      }
    }
    if upper {
      return value
    }
  }
  raise InvalidField(
    path=field_path,
    reason="currency must be a 3-letter ISO 4217 code",
  )
}

///|
/// Context window and cost snapshot for the session; `used` and `size` count
/// tokens and `cost` is optional.
pub(all) struct ExperimentalV2UsageUpdate {
  used : UInt64
  size : UInt64
  cost : ExperimentalV2Cost?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_usage_update(
  value : Json,
  path? : String = "usage_update",
) -> ExperimentalV2UsageUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["used", "size", "cost", "_meta"],
    prefix=path,
  )
  let used = experimental_v2_decode_uint64(
    experimental_v2_required(fields, "used", path=path + ".used"),
    path=path + ".used",
  )
  let size = experimental_v2_decode_uint64(
    experimental_v2_required(fields, "size", path=path + ".size"),
    path=path + ".size",
  )
  let cost = experimental_v2_decode_optional(
    fields,
    "cost",
    path=path + ".cost",
    (value, path) => experimental_v2_decode_cost(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { used, size, cost, meta, }
}

///|
pub fn experimental_v2_encode_usage_update(
  value : ExperimentalV2UsageUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["used"] = experimental_v2_encode_uint64(value.used)
  fields["size"] = experimental_v2_encode_uint64(value.size)
  experimental_v2_put_optional(fields, "cost", value.cost, value => {
    experimental_v2_encode_cost(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Known payloads of a `session/update`; the `sessionUpdate` discriminator is
/// an open union so custom or future updates stay as raw payloads a proxy can
/// replay byte-faithfully.
pub(all) enum ExperimentalV2SessionUpdateKnown {
  UpdateUserMessageChunk(ExperimentalV2ContentChunk)
  UpdateUserMessage(ExperimentalV2MessageUpsert)
  UpdateAgentMessageChunk(ExperimentalV2ContentChunk)
  UpdateAgentMessage(ExperimentalV2MessageUpsert)
  UpdateAgentThoughtChunk(ExperimentalV2ContentChunk)
  UpdateAgentThought(ExperimentalV2MessageUpsert)
  UpdateState(ExperimentalV2StateUpdate)
  UpdateToolCallContentChunk(ExperimentalV2ToolCallContentChunk)
  UpdateToolCall(ExperimentalV2ToolCallUpdate)
  UpdateTerminal(ExperimentalV2TerminalUpdate)
  UpdateTerminalOutputChunk(ExperimentalV2TerminalOutputChunk)
  UpdatePlan(ExperimentalV2PlanUpdate)
  UpdateAvailableCommands(ExperimentalV2AvailableCommandsUpdate)
  UpdateConfigOptions(ExperimentalV2ConfigOptionUpdate)
  UpdateSessionInfo(ExperimentalV2SessionInfoUpdate)
  UpdateUsage(ExperimentalV2UsageUpdate)
} derive(Eq, Debug)

///|
pub type ExperimentalV2SessionUpdate = ExperimentalV2Open[
  ExperimentalV2SessionUpdateKnown,
]

///|
pub fn experimental_v2_decode_session_update(
  value : Json,
  path? : String = "update",
) -> ExperimentalV2SessionUpdate raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="sessionUpdate",
    [
      "user_message_chunk", "user_message", "agent_message_chunk", "agent_message",
      "agent_thought_chunk", "agent_thought", "state_update", "tool_call_content_chunk",
      "tool_call_update", "terminal_update", "terminal_output_chunk", "plan_update",
      "available_commands_update", "config_option_update", "session_info_update",
      "usage_update",
    ],
    (tag, payload) => {
      let untagged = experimental_v2_untag_payload(
        payload,
        tag_key="sessionUpdate",
        path~,
      )
      match tag {
        "user_message_chunk" =>
          UpdateUserMessageChunk(
            experimental_v2_decode_content_chunk(untagged, path~),
          )
        "user_message" =>
          UpdateUserMessage(
            experimental_v2_decode_message_upsert(untagged, path~),
          )
        "agent_message_chunk" =>
          UpdateAgentMessageChunk(
            experimental_v2_decode_content_chunk(untagged, path~),
          )
        "agent_message" =>
          UpdateAgentMessage(
            experimental_v2_decode_message_upsert(untagged, path~),
          )
        "agent_thought_chunk" =>
          UpdateAgentThoughtChunk(
            experimental_v2_decode_content_chunk(untagged, path~),
          )
        "agent_thought" =>
          UpdateAgentThought(
            experimental_v2_decode_message_upsert(untagged, path~),
          )
        "state_update" =>
          UpdateState(experimental_v2_decode_state_update(untagged, path~))
        "tool_call_content_chunk" =>
          UpdateToolCallContentChunk(
            experimental_v2_decode_tool_call_content_chunk(untagged, path~),
          )
        "tool_call_update" =>
          UpdateToolCall(
            experimental_v2_decode_tool_call_update(untagged, path~),
          )
        "terminal_update" =>
          UpdateTerminal(
            experimental_v2_decode_terminal_update(untagged, path~),
          )
        "terminal_output_chunk" =>
          UpdateTerminalOutputChunk(
            experimental_v2_decode_terminal_output_chunk(untagged, path~),
          )
        "plan_update" =>
          UpdatePlan(experimental_v2_decode_plan_update(untagged, path~))
        "available_commands_update" =>
          UpdateAvailableCommands(
            experimental_v2_decode_available_commands_update(untagged, path~),
          )
        "config_option_update" =>
          UpdateConfigOptions(
            experimental_v2_decode_config_option_update(untagged, path~),
          )
        "session_info_update" =>
          UpdateSessionInfo(
            experimental_v2_decode_session_info_update(untagged, path~),
          )
        "usage_update" =>
          UpdateUsage(experimental_v2_decode_usage_update(untagged, path~))
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".sessionUpdate", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_session_update(
  value : ExperimentalV2SessionUpdate,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="sessionUpdate", known => {
    match known {
      UpdateUserMessageChunk(chunk) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_content_chunk(chunk),
          tag_key="sessionUpdate",
          tag="user_message_chunk",
        )
      UpdateUserMessage(message) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_message_upsert(message),
          tag_key="sessionUpdate",
          tag="user_message",
        )
      UpdateAgentMessageChunk(chunk) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_content_chunk(chunk),
          tag_key="sessionUpdate",
          tag="agent_message_chunk",
        )
      UpdateAgentMessage(message) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_message_upsert(message),
          tag_key="sessionUpdate",
          tag="agent_message",
        )
      UpdateAgentThoughtChunk(chunk) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_content_chunk(chunk),
          tag_key="sessionUpdate",
          tag="agent_thought_chunk",
        )
      UpdateAgentThought(message) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_message_upsert(message),
          tag_key="sessionUpdate",
          tag="agent_thought",
        )
      UpdateState(state) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_state_update(state),
          tag_key="sessionUpdate",
          tag="state_update",
        )
      UpdateToolCallContentChunk(chunk) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_tool_call_content_chunk(chunk),
          tag_key="sessionUpdate",
          tag="tool_call_content_chunk",
        )
      UpdateToolCall(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_tool_call_update(update),
          tag_key="sessionUpdate",
          tag="tool_call_update",
        )
      UpdateTerminal(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_terminal_update(update),
          tag_key="sessionUpdate",
          tag="terminal_update",
        )
      UpdateTerminalOutputChunk(chunk) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_terminal_output_chunk(chunk),
          tag_key="sessionUpdate",
          tag="terminal_output_chunk",
        )
      UpdatePlan(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_plan_update(update),
          tag_key="sessionUpdate",
          tag="plan_update",
        )
      UpdateAvailableCommands(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_available_commands_update(update),
          tag_key="sessionUpdate",
          tag="available_commands_update",
        )
      UpdateConfigOptions(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_config_option_update(update),
          tag_key="sessionUpdate",
          tag="config_option_update",
        )
      UpdateSessionInfo(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_session_info_update(update),
          tag_key="sessionUpdate",
          tag="session_info_update",
        )
      UpdateUsage(update) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_usage_update(update),
          tag_key="sessionUpdate",
          tag="usage_update",
        )
    }
  })
}

///|
/// Parameters of the `session/update` notification: one update for the
/// session identified by `session_id`.
pub(all) struct ExperimentalV2UpdateSessionNotification {
  session_id : String
  update : ExperimentalV2SessionUpdate
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_update_session_notification(
  value : Json,
  path? : String = "session/update",
) -> ExperimentalV2UpdateSessionNotification raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "sessionId", "update"],
    prefix=path,
  )
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let update = experimental_v2_decode_session_update(
    experimental_v2_required(fields, "update", path=path + ".update"),
    path=path + ".update",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, update, meta, }
}

///|
pub fn experimental_v2_encode_update_session_notification(
  value : ExperimentalV2UpdateSessionNotification,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["update"] = experimental_v2_encode_session_update(value.update)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
