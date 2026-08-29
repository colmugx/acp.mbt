///|
/// Categories of tools that can be invoked, with the schema's open fallback:
/// `other` is a defined value, `_`-prefixed kinds are implementation
/// extensions, and other unknown kinds are future values.
pub(all) enum ExperimentalV2ToolKind {
  ToolKindRead
  ToolKindEdit
  ToolKindDelete
  ToolKindMove
  ToolKindSearch
  ToolKindExecute
  ToolKindThink
  ToolKindFetch
  ToolKindSwitchMode
  ToolKindOther
  ToolKindExtension(tag~ : String)
  ToolKindFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_tool_kind(
  value : Json,
  path? : String = "kind",
) -> ExperimentalV2ToolKind raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "read" => ToolKindRead
    "edit" => ToolKindEdit
    "delete" => ToolKindDelete
    "move" => ToolKindMove
    "search" => ToolKindSearch
    "execute" => ToolKindExecute
    "think" => ToolKindThink
    "fetch" => ToolKindFetch
    "switch_mode" => ToolKindSwitchMode
    "other" => ToolKindOther
    _ =>
      if tag.has_prefix("_") {
        ToolKindExtension(tag~)
      } else {
        ToolKindFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_tool_kind(value : ExperimentalV2ToolKind) -> Json {
  match value {
    ToolKindRead => Json::string("read")
    ToolKindEdit => Json::string("edit")
    ToolKindDelete => Json::string("delete")
    ToolKindMove => Json::string("move")
    ToolKindSearch => Json::string("search")
    ToolKindExecute => Json::string("execute")
    ToolKindThink => Json::string("think")
    ToolKindFetch => Json::string("fetch")
    ToolKindSwitchMode => Json::string("switch_mode")
    ToolKindOther => Json::string("other")
    ToolKindExtension(tag~) => Json::string(tag)
    ToolKindFuture(raw~) => Json::string(raw)
  }
}

///|
/// Execution status of a tool call, with the schema's open fallback.
pub(all) enum ExperimentalV2ToolCallStatus {
  ToolCallStatusPending
  ToolCallStatusInProgress
  ToolCallStatusCompleted
  ToolCallStatusFailed
  ToolCallStatusCancelled
  ToolCallStatusExtension(tag~ : String)
  ToolCallStatusFuture(raw~ : String)
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_tool_call_status(
  value : Json,
  path? : String = "status",
) -> ExperimentalV2ToolCallStatus raise ExperimentalV2DecodeError {
  let tag = experimental_v2_decode_string(value, path~)
  match tag {
    "pending" => ToolCallStatusPending
    "in_progress" => ToolCallStatusInProgress
    "completed" => ToolCallStatusCompleted
    "failed" => ToolCallStatusFailed
    "cancelled" => ToolCallStatusCancelled
    _ =>
      if tag.has_prefix("_") {
        ToolCallStatusExtension(tag~)
      } else {
        ToolCallStatusFuture(raw=tag)
      }
  }
}

///|
pub fn experimental_v2_encode_tool_call_status(
  value : ExperimentalV2ToolCallStatus,
) -> Json {
  match value {
    ToolCallStatusPending => Json::string("pending")
    ToolCallStatusInProgress => Json::string("in_progress")
    ToolCallStatusCompleted => Json::string("completed")
    ToolCallStatusFailed => Json::string("failed")
    ToolCallStatusCancelled => Json::string("cancelled")
    ToolCallStatusExtension(tag~) => Json::string(tag)
    ToolCallStatusFuture(raw~) => Json::string(raw)
  }
}

///|
/// A file location being accessed or modified by a tool.
pub(all) struct ExperimentalV2ToolCallLocation {
  path : String
  line : UInt?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_tool_call_location(
  value : Json,
  path? : String = "location",
) -> ExperimentalV2ToolCallLocation raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["path", "line", "_meta"], prefix=path)
  let location_path = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "path", path=path + ".path"),
      path=path + ".path",
    ),
    field_path=path + ".path",
  )
  let line = experimental_v2_decode_optional(
    fields,
    "line",
    path=path + ".line",
    (value, path) => experimental_v2_decode_uint32(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { path: location_path, line, meta, }
}

///|
pub fn experimental_v2_encode_tool_call_location(
  value : ExperimentalV2ToolCallLocation,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["path"] = Json::string(
    experimental_v2_validate_absolute_path(value.path, field_path="path"),
  )
  experimental_v2_put_optional(fields, "line", value.line, value => {
    Json::number(value.to_double())
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// The three known v2 tool-call content payloads.
pub(all) enum ExperimentalV2ToolCallContentKnown {
  ToolCallContentBlock(ExperimentalV2Content)
  ToolCallContentDiff(ExperimentalV2Diff)
  ToolCallContentTerminal(ExperimentalV2Terminal)
} derive(Eq, Debug)

///|
/// Content produced by a tool call.  The schema has an open fallback:
/// `_`-prefixed types are implementation extensions and other unknown types
/// are future values; both keep their raw object for byte-faithful replay.
pub type ExperimentalV2ToolCallContent = ExperimentalV2Open[
  ExperimentalV2ToolCallContentKnown,
]

///|
pub fn experimental_v2_decode_tool_call_content(
  value : Json,
  path? : String = "content",
) -> ExperimentalV2ToolCallContent raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["content", "diff", "terminal"],
    (tag, payload) => {
      match tag {
        "content" =>
          ToolCallContentBlock(experimental_v2_decode_content(payload, path~))
        "diff" =>
          ToolCallContentDiff(experimental_v2_decode_diff(payload, path~))
        "terminal" =>
          ToolCallContentTerminal(
            experimental_v2_decode_terminal(payload, path~),
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
pub fn experimental_v2_encode_tool_call_content(
  value : ExperimentalV2ToolCallContent,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", known => {
    match known {
      ToolCallContentBlock(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_content(value),
          tag_key="type",
          tag="content",
        )
      ToolCallContentDiff(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_diff(value),
          tag_key="type",
          tag="diff",
        )
      ToolCallContentTerminal(value) =>
        experimental_v2_tag_payload(
          experimental_v2_encode_terminal(value),
          tag_key="type",
          tag="terminal",
        )
    }
  })
}

///|
/// An upsert for a tool call that the language model has requested.  Only
/// `tool_call_id` is required; every other field is a patch tri-state where
/// omitted keeps the existing value, null clears it, and a value replaces it.
/// Collection fields replace wholesale (`null` and `[]` both clear).
pub(all) struct ExperimentalV2ToolCallUpdate {
  tool_call_id : String
  title : ExperimentalV2Patch[String]
  kind : ExperimentalV2Patch[ExperimentalV2ToolKind]
  status : ExperimentalV2Patch[ExperimentalV2ToolCallStatus]
  content : ExperimentalV2Patch[Array[ExperimentalV2ToolCallContent]]
  locations : ExperimentalV2Patch[Array[ExperimentalV2ToolCallLocation]]
  raw_input : ExperimentalV2Patch[Json]
  raw_output : ExperimentalV2Patch[Json]
  meta : ExperimentalV2Patch[Json]
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_tool_call_update(
  value : Json,
  path? : String = "toolCall",
) -> ExperimentalV2ToolCallUpdate raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    [
      "_meta", "toolCallId", "title", "kind", "status", "content", "locations", "rawInput",
      "rawOutput",
    ],
    prefix=path,
  )
  let tool_call_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "toolCallId", path=path + ".toolCallId"),
      path=path + ".toolCallId",
    ),
    field_path=path + ".toolCallId",
  )
  let title = experimental_v2_decode_patch(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let kind = experimental_v2_decode_patch(fields, "kind", path=path + ".kind", (
    value,
    path,
  ) => experimental_v2_decode_tool_kind(value, path~))
  let status = experimental_v2_decode_patch(
    fields,
    "status",
    path=path + ".status",
    (value, path) => experimental_v2_decode_tool_call_status(value, path~),
  )
  let content = experimental_v2_decode_patch(
    fields,
    "content",
    path=path + ".content",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_tool_call_content(item, path=item_path)
      })
    },
  )
  let locations = experimental_v2_decode_patch(
    fields,
    "locations",
    path=path + ".locations",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_tool_call_location(item, path=item_path)
      })
    },
  )
  let raw_input = experimental_v2_patch_field(fields, "rawInput")
  let raw_output = experimental_v2_patch_field(fields, "rawOutput")
  let meta = experimental_v2_top_meta(fields, path=path + "._meta")
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
pub fn experimental_v2_encode_tool_call_update(
  value : ExperimentalV2ToolCallUpdate,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["toolCallId"] = Json::string(value.tool_call_id)
  experimental_v2_put_patch(fields, "title", value.title, value => {
    Json::string(value)
  })
  experimental_v2_put_patch(fields, "kind", value.kind, value => {
    experimental_v2_encode_tool_kind(value)
  })
  experimental_v2_put_patch(fields, "status", value.status, value => {
    experimental_v2_encode_tool_call_status(value)
  })
  experimental_v2_put_patch(fields, "content", value.content, values => {
    experimental_v2_encode_array(
      values, experimental_v2_encode_tool_call_content,
    )
  })
  experimental_v2_put_patch(fields, "locations", value.locations, values => {
    experimental_v2_encode_array(
      values, experimental_v2_encode_tool_call_location,
    )
  })
  experimental_v2_put_patch(fields, "rawInput", value.raw_input, raw => raw)
  experimental_v2_put_patch(fields, "rawOutput", value.raw_output, raw => raw)
  experimental_v2_put_top_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// A streamed item of tool-call content; each chunk appends one content item
/// to the current content for the matching tool call.
pub(all) struct ExperimentalV2ToolCallContentChunk {
  tool_call_id : String
  content : ExperimentalV2ToolCallContent
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_tool_call_content_chunk(
  value : Json,
  path? : String = "toolCallContentChunk",
) -> ExperimentalV2ToolCallContentChunk raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["toolCallId", "content", "_meta"],
    prefix=path,
  )
  let tool_call_id = experimental_v2_validate_id(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "toolCallId", path=path + ".toolCallId"),
      path=path + ".toolCallId",
    ),
    field_path=path + ".toolCallId",
  )
  let content = experimental_v2_decode_tool_call_content(
    experimental_v2_required(fields, "content", path=path + ".content"),
    path=path + ".content",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { tool_call_id, content, meta, }
}

///|
pub fn experimental_v2_encode_tool_call_content_chunk(
  value : ExperimentalV2ToolCallContentChunk,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["toolCallId"] = Json::string(value.tool_call_id)
  fields["content"] = experimental_v2_encode_tool_call_content(value.content)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
