///|
/// The type of permission option being presented to the user, with the
/// schema's open fallback.
pub(all) enum ExperimentalV2PermissionOptionKind {
  OptionKindAllowOnce
  OptionKindAllowAlways
  OptionKindRejectOnce
  OptionKindRejectAlways
  OptionKindExtension(tag~ : String)
  OptionKindFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_permission_option_kind(
  value : Json,
  path? : String = "kind",
) -> ExperimentalV2PermissionOptionKind raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "allow_once" => OptionKindAllowOnce
    "allow_always" => OptionKindAllowAlways
    "reject_once" => OptionKindRejectOnce
    "reject_always" => OptionKindRejectAlways
    _ =>
      if tag.has_prefix("_") {
        OptionKindExtension(tag~)
      } else {
        OptionKindFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_permission_option_kind(
  value : ExperimentalV2PermissionOptionKind,
) -> Json {
  match value {
    OptionKindAllowOnce => Json::string("allow_once")
    OptionKindAllowAlways => Json::string("allow_always")
    OptionKindRejectOnce => Json::string("reject_once")
    OptionKindRejectAlways => Json::string("reject_always")
    OptionKindExtension(tag~) => Json::string(tag)
    OptionKindFuture(raw~) => Json::string(raw)
  }
}

///|
/// An option presented to the user when requesting permission.
pub(all) struct ExperimentalV2PermissionOption {
  option_id : String
  name : String
  kind : ExperimentalV2PermissionOptionKind
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_permission_option(
  value : Json,
  path? : String = "option",
) -> ExperimentalV2PermissionOption raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["optionId", "name", "kind", "_meta"],
    prefix=path,
  )
  let option_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "optionId", path=path + ".optionId"),
      path=path + ".optionId",
    ),
    field_path=path + ".optionId",
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let kind = experimental_v2_decode_permission_option_kind(
    experimental_v2_required(fields, "kind", path=path + ".kind"),
    path=path + ".kind",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { option_id, name, kind, meta, }
}

///|
pub fn experimental_v2_encode_permission_option(
  value : ExperimentalV2PermissionOption,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["optionId"] = Json::string(value.option_id)
  fields["name"] = Json::string(value.name)
  fields["kind"] = experimental_v2_encode_permission_option_kind(value.kind)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The user selected one of the provided options.
pub(all) struct ExperimentalV2SelectedPermissionOutcome {
  option_id : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_selected_permission_outcome(
  value : Json,
  path? : String = "outcome",
) -> ExperimentalV2SelectedPermissionOutcome raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["outcome", "optionId", "_meta"],
    prefix=path,
  )
  let option_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "optionId", path=path + ".optionId"),
      path=path + ".optionId",
    ),
    field_path=path + ".optionId",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { option_id, meta, }
}

///|
pub fn experimental_v2_encode_selected_permission_outcome(
  value : ExperimentalV2SelectedPermissionOutcome,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["optionId"] = Json::string(value.option_id)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The two known v2 permission outcome payloads.
pub(all) enum ExperimentalV2PermissionOutcomeKnown {
  OutcomeCancelled
  OutcomeSelected(ExperimentalV2SelectedPermissionOutcome)
} derive(Eq, Debug)

///|
/// The outcome of a permission request.  The schema has an open fallback:
/// `_`-prefixed outcomes are implementation extensions and other unknown
/// outcomes are future values; both keep their raw object so proxies replay
/// them byte-faithfully instead of treating them as approval.
pub type ExperimentalV2PermissionOutcome = ExperimentalV2Open[
  ExperimentalV2PermissionOutcomeKnown,
]

///|
pub fn experimental_v2_decode_permission_outcome(
  value : Json,
  path? : String = "outcome",
) -> ExperimentalV2PermissionOutcome raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="outcome",
    ["cancelled", "selected"],
    (tag, payload) => {
      match tag {
        "cancelled" => {
          let fields = experimental_v2_require_object(payload, path~)
          experimental_v2_reject_unknown(fields, ["outcome"], prefix=path)
          OutcomeCancelled
        }
        "selected" =>
          OutcomeSelected(
            experimental_v2_decode_selected_permission_outcome(payload, path~),
          )
        _ =>
          // decode_open only passes known tags; keep exhaustiveness explicit.
          raise InvalidDiscriminator(path=path + ".outcome", value=tag)
      }
    },
    path~,
  )
}

///|
pub fn experimental_v2_encode_permission_outcome(
  value : ExperimentalV2PermissionOutcome,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="outcome", known => {
    match known {
      OutcomeCancelled => Json::object({ "outcome": Json::string("cancelled") })
      OutcomeSelected(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_selected_permission_outcome(value),
          tag_key="outcome",
          tag="selected",
        )
    }
  })
}

///|
/// Permission request details for a tool call; `tool_call` carries the same
/// upsert shape as a `tool_call` session update.
pub(all) struct ExperimentalV2ToolCallPermissionSubject {
  tool_call : ExperimentalV2ToolCallUpdate
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_tool_call_permission_subject(
  value : Json,
  path? : String = "subject",
) -> ExperimentalV2ToolCallPermissionSubject raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["type", "toolCall"], prefix=path)
  let tool_call = experimental_v2_decode_tool_call_update(
    experimental_v2_required(fields, "toolCall", path=path + ".toolCall"),
    path=path + ".toolCall",
  )
  { tool_call, }
}

///|
pub fn experimental_v2_encode_tool_call_permission_subject(
  value : ExperimentalV2ToolCallPermissionSubject,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["toolCall"] = experimental_v2_encode_tool_call_update(value.tool_call)
  Json::object(fields)
}

///|
/// Permission request details for a command.
pub(all) struct ExperimentalV2CommandPermissionSubject {
  command : String
  cwd : String
  tool_call_id : String?
  terminal_id : String?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_command_permission_subject(
  value : Json,
  path? : String = "subject",
) -> ExperimentalV2CommandPermissionSubject raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["type", "command", "cwd", "toolCallId", "terminalId", "_meta"],
    prefix=path,
  )
  let command = experimental_v2_decode_string(
    experimental_v2_required(fields, "command", path=path + ".command"),
    path=path + ".command",
  )
  let cwd = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "cwd", path=path + ".cwd"),
      path=path + ".cwd",
    ),
    field_path=path + ".cwd",
  )
  let tool_call_id = experimental_v2_decode_optional(
    fields,
    "toolCallId",
    path=path + ".toolCallId",
    (value, path) => {
      experimental_v2_validate_id(
        experimental_v2_decode_string(value, path~),
        field_path=path,
      )
    },
  )
  let terminal_id = experimental_v2_decode_optional(
    fields,
    "terminalId",
    path=path + ".terminalId",
    (value, path) => {
      experimental_v2_validate_id(
        experimental_v2_decode_string(value, path~),
        field_path=path,
      )
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { command, cwd, tool_call_id, terminal_id, meta, }
}

///|
pub fn experimental_v2_encode_command_permission_subject(
  value : ExperimentalV2CommandPermissionSubject,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["command"] = Json::string(value.command)
  fields["cwd"] = Json::string(
    experimental_v2_validate_absolute_path(value.cwd, field_path="cwd"),
  )
  experimental_v2_put_optional(fields, "toolCallId", value.tool_call_id, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(fields, "terminalId", value.terminal_id, value => {
    Json::string(value)
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The two known v2 permission subject payloads.
pub(all) enum ExperimentalV2PermissionSubjectKnown {
  SubjectToolCall(ExperimentalV2ToolCallPermissionSubject)
  SubjectCommand(ExperimentalV2CommandPermissionSubject)
} derive(Eq, Debug)

///|
/// The operation requiring permission.  The schema has an open fallback:
/// `_`-prefixed subject types are implementation extensions and other unknown
/// types are future values; both keep their raw object.
pub type ExperimentalV2PermissionSubject = ExperimentalV2Open[
  ExperimentalV2PermissionSubjectKnown,
]

///|
pub fn experimental_v2_decode_permission_subject(
  value : Json,
  path? : String = "subject",
) -> ExperimentalV2PermissionSubject raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["tool_call", "command"],
    (tag, payload) => {
      match tag {
        "tool_call" =>
          SubjectToolCall(
            experimental_v2_decode_tool_call_permission_subject(payload, path~),
          )
        "command" =>
          SubjectCommand(
            experimental_v2_decode_command_permission_subject(payload, path~),
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
pub fn experimental_v2_encode_permission_subject(
  value : ExperimentalV2PermissionSubject,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    match known {
      SubjectToolCall(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_tool_call_permission_subject(value),
          tag_key="type",
          tag="tool_call",
        )
      SubjectCommand(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_command_permission_subject(value),
          tag_key="type",
          tag="command",
        )
    }
  })
}

///|
/// Request for user permission to proceed with an operation.
pub(all) struct ExperimentalV2RequestPermissionRequest {
  session_id : String
  title : String
  description : String?
  subject : ExperimentalV2PermissionSubject?
  options : Array[ExperimentalV2PermissionOption]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_request_permission_request(
  value : Json,
  path? : String = "session/request_permission",
) -> ExperimentalV2RequestPermissionRequest raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "sessionId", "title", "description", "subject", "options"],
    prefix=path,
  )
  let session_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    ),
    field_path=path + ".sessionId",
  )
  let title = experimental_v2_decode_string(
    experimental_v2_required(fields, "title", path=path + ".title"),
    path=path + ".title",
  )
  let description = experimental_v2_decode_optional(
    fields,
    "description",
    path=path + ".description",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let subject = experimental_v2_decode_optional(
    fields,
    "subject",
    path=path + ".subject",
    (value, path) => experimental_v2_decode_permission_subject(value, path~),
  )
  let options = experimental_v2_decode_array(
    experimental_v2_required(fields, "options", path=path + ".options"),
    path=path + ".options",
    (item, item_path) => {
      experimental_v2_decode_permission_option(item, path=item_path)
    },
  )
  if options.is_empty() {
    raise InvalidField(
      path=path + ".options",
      reason="options must contain at least one option",
    )
  }
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session_id, title, description, subject, options, meta, }
}

///|
pub fn experimental_v2_encode_request_permission_request(
  value : ExperimentalV2RequestPermissionRequest,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["title"] = Json::string(value.title)
  experimental_v2_put_optional(fields, "description", value.description, value => {
    Json::string(value)
  })
  experimental_v2_put_optional(
    fields,
    "subject",
    value.subject,
    experimental_v2_encode_permission_subject,
  )
  fields["options"] = experimental_v2_encode_array(
    value.options,
    experimental_v2_encode_permission_option,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Response to a permission request.
pub(all) struct ExperimentalV2RequestPermissionResponse {
  outcome : ExperimentalV2PermissionOutcome
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_request_permission_response(
  value : Json,
  path? : String = "session/request_permission",
) -> ExperimentalV2RequestPermissionResponse raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["outcome", "_meta"], prefix=path)
  let outcome = experimental_v2_decode_permission_outcome(
    experimental_v2_required(fields, "outcome", path=path + ".outcome"),
    path=path + ".outcome",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { outcome, meta, }
}

///|
pub fn experimental_v2_encode_request_permission_response(
  value : ExperimentalV2RequestPermissionResponse,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["outcome"] = experimental_v2_encode_permission_outcome(value.outcome)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
