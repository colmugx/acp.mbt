///|
using @jsonrpc {type RequestId, jsonrpc_decode_int64}

///|
/// Stable wire identifier for a URL elicitation.
pub type ElicitationId = String

///|
/// Request scope for `elicitation/create`.  The two variants are flattened
/// into `requestId` or `sessionId` on the wire.
pub(all) enum ElicitationScope {
  Request(RequestId)
  Session(session_id~ : SessionId, tool_call_id~ : ProtocolNullable[ToolCallId])
} derive(Eq, Debug)

///|
/// Form-mode elicitation parameters.
pub(all) struct ElicitationFormParams {
  scope : ElicitationScope
  message : String
  requested_schema : Json
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// URL-mode elicitation parameters.
pub(all) struct ElicitationUrlParams {
  scope : ElicitationScope
  elicitation_id : ElicitationId
  message : String
  url : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// The form/URL union for `elicitation/create`.
pub(all) enum ElicitationCreateParams {
  Form(ElicitationFormParams)
  Url(ElicitationUrlParams)
} derive(Eq, Debug)

///|
/// The action returned by the client for `elicitation/create`.
pub(all) enum ElicitationAction {
  Accept
  Decline
  Cancel
} derive(Eq, Debug)

///|
/// Result of `elicitation/create`.
///
/// `content` carries the accept-action form values.  Only the accept outcome
/// may carry content; decline and cancel are payload-free per the fixed v1
/// schema (`CreateElicitationResponse`/`ElicitationAcceptAction`).
pub(all) struct ElicitationCreateResult {
  action : ElicitationAction
  content : ProtocolNullable[Json]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Parameters for the `elicitation/complete` notification.
pub(all) struct ElicitationCompleteParams {
  elicitation_id : ElicitationId
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn elicitation_require_non_empty(
  value : String,
  path~ : String,
) -> String raise ProtocolDecodeError {
  if value == "" {
    raise InvalidField(path~, reason="string must not be empty")
  }
  value
}

///|
fn elicitation_decode_non_empty_string(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  elicitation_require_non_empty(protocol_decode_string(value, path~), path~)
}

///|
fn elicitation_decode_request_id(
  value : Json,
  path~ : String,
) -> RequestId raise ProtocolDecodeError {
  match value {
    String(value) => String(value)
    Number(value, repr~) =>
      Number(
        jsonrpc_decode_int64(value, repr, path~) catch {
          _ =>
            raise InvalidField(path~, reason="expected a signed 64-bit integer")
        },
      )
    Null => Null
    _ =>
      raise InvalidField(
        path~,
        reason="requestId must be a string, integer, or null",
      )
  }
}

///|
fn elicitation_encode_request_id(value : RequestId) -> Json {
  match value {
    String(value) => Json::string(value)
    Number(value) => Json::number(value.to_double(), repr=value.to_string())
    Null => Json::null()
  }
}

///|
fn elicitation_decode_non_negative_integer(
  value : Json,
  path~ : String,
) -> UInt64 raise ProtocolDecodeError {
  match value {
    Number(number, repr~) =>
      match protocol_parse_uint64_number(number, repr) {
        Ok(value) => value
        Err(NonFinite) =>
          raise InvalidField(path~, reason="expected a finite integer")
        Err(Fractional) =>
          raise InvalidField(path~, reason="expected a non-negative integer")
        Err(Malformed | OutOfRange | PrecisionUnavailable) =>
          raise InvalidField(path~, reason="expected a uint64 integer")
      }
    _ => raise ExpectedNumber(path~)
  }
}

///|
fn elicitation_decode_signed_integer(
  value : Json,
  path~ : String,
) -> Int64 raise ProtocolDecodeError {
  match value {
    Number(number, repr~) =>
      match protocol_parse_int64_number(number, repr) {
        Ok(value) => value
        Err(NonFinite) =>
          raise InvalidField(path~, reason="expected a finite integer")
        Err(Fractional) =>
          raise InvalidField(path~, reason="expected an integer")
        Err(Malformed | OutOfRange | PrecisionUnavailable) =>
          raise InvalidField(path~, reason="expected an int64 integer")
      }
    _ => raise ExpectedNumber(path~)
  }
}

///|
fn elicitation_validate_optional_string(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted | Null => ()
    Value(value) => ignore(protocol_decode_string(value, path~))
  }
}

///|
fn elicitation_validate_optional_boolean(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted | Null => ()
    Value(value) => ignore(protocol_decode_boolean(value, path~))
  }
}

///|
fn elicitation_validate_optional_number(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted | Null => ()
    Value(value) => ignore(protocol_decode_number(value, path~))
  }
}

///|
fn elicitation_validate_optional_non_negative_integer(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted | Null => ()
    Value(value) =>
      ignore(elicitation_decode_non_negative_integer(value, path~))
  }
}

///|
fn elicitation_validate_optional_integer(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted | Null => ()
    Value(value) => ignore(elicitation_decode_signed_integer(value, path~))
  }
}

///|
fn elicitation_validate_string_array(
  value : Json,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  for index, value in values {
    ignore(
      protocol_decode_string(value, path=path + "[" + index.to_string() + "]"),
    )
  }
}

///|
fn elicitation_validate_enum_options(
  value : Json,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  for index, value in values {
    let option_path = path + "[" + index.to_string() + "]"
    let fields = protocol_require_object(value, path=option_path)
    protocol_reject_unknown(
      fields,
      ["const", "title", "description", "_meta"],
      prefix=option_path,
    )
    ignore(protocol_required(fields, "const", path=option_path + ".const"))
    elicitation_validate_optional_string(
      fields,
      "title",
      path=option_path + ".title",
    )
    elicitation_validate_optional_string(
      fields,
      "description",
      path=option_path + ".description",
    )
    ignore(protocol_meta(fields, path=option_path + "._meta"))
  }
}

///|
fn elicitation_validate_array_items(
  value : Json,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["type", "anyOf", "enum", "_meta"],
    prefix=path,
  )
  match protocol_field(fields, "type") {
    Omitted => ()
    Null => raise InvalidField(path=path + ".type", reason="type is required")
    Value(value) =>
      match protocol_decode_string(value, path=path + ".type") {
        "string" => ()
        other => raise InvalidDiscriminator(path=path + ".type", value=other)
      }
  }
  match protocol_field(fields, "anyOf") {
    Omitted | Null => ()
    Value(value) =>
      elicitation_validate_enum_options(value, path=path + ".anyOf")
  }
  match protocol_field(fields, "enum") {
    Omitted | Null => ()
    Value(value) =>
      elicitation_validate_string_array(value, path=path + ".enum")
  }
  ignore(protocol_meta(fields, path=path + "._meta"))
}

///|
fn elicitation_validate_property_schema(
  value : Json,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let type_value = protocol_required_string(fields, "type", path=path + ".type")
  match type_value {
    "string" => {
      protocol_reject_unknown(
        fields,
        [
          "type", "title", "description", "default", "minLength", "maxLength", "pattern",
          "format", "enum", "oneOf", "_meta",
        ],
        prefix=path,
      )
      elicitation_validate_optional_string(
        fields,
        "title",
        path=path + ".title",
      )
      elicitation_validate_optional_string(
        fields,
        "description",
        path=path + ".description",
      )
      elicitation_validate_optional_string(
        fields,
        "default",
        path=path + ".default",
      )
      elicitation_validate_optional_non_negative_integer(
        fields,
        "minLength",
        path=path + ".minLength",
      )
      elicitation_validate_optional_non_negative_integer(
        fields,
        "maxLength",
        path=path + ".maxLength",
      )
      elicitation_validate_optional_string(
        fields,
        "pattern",
        path=path + ".pattern",
      )
      match protocol_field(fields, "format") {
        Omitted | Null => ()
        Value(value) => {
          let format = protocol_decode_string(value, path=path + ".format")
          match format {
            "email" | "uri" | "date" | "date-time" => ()
            other =>
              raise InvalidDiscriminator(path=path + ".format", value=other)
          }
        }
      }
      match protocol_field(fields, "enum") {
        Omitted | Null => ()
        Value(value) =>
          elicitation_validate_string_array(value, path=path + ".enum")
      }
      match protocol_field(fields, "oneOf") {
        Omitted | Null => ()
        Value(value) =>
          elicitation_validate_enum_options(value, path=path + ".oneOf")
      }
    }
    "number" | "integer" => {
      protocol_reject_unknown(
        fields,
        [
          "type", "title", "description", "default", "minimum", "maximum", "_meta",
        ],
        prefix=path,
      )
      elicitation_validate_optional_string(
        fields,
        "title",
        path=path + ".title",
      )
      elicitation_validate_optional_string(
        fields,
        "description",
        path=path + ".description",
      )
      if type_value == "number" {
        elicitation_validate_optional_number(
          fields,
          "default",
          path=path + ".default",
        )
        elicitation_validate_optional_number(
          fields,
          "minimum",
          path=path + ".minimum",
        )
        elicitation_validate_optional_number(
          fields,
          "maximum",
          path=path + ".maximum",
        )
      } else {
        elicitation_validate_optional_integer(
          fields,
          "default",
          path=path + ".default",
        )
        elicitation_validate_optional_integer(
          fields,
          "minimum",
          path=path + ".minimum",
        )
        elicitation_validate_optional_integer(
          fields,
          "maximum",
          path=path + ".maximum",
        )
      }
    }
    "boolean" => {
      protocol_reject_unknown(
        fields,
        ["type", "title", "description", "default", "_meta"],
        prefix=path,
      )
      elicitation_validate_optional_string(
        fields,
        "title",
        path=path + ".title",
      )
      elicitation_validate_optional_string(
        fields,
        "description",
        path=path + ".description",
      )
      elicitation_validate_optional_boolean(
        fields,
        "default",
        path=path + ".default",
      )
    }
    "array" => {
      protocol_reject_unknown(
        fields,
        [
          "type", "title", "description", "default", "minItems", "maxItems", "items",
          "_meta",
        ],
        prefix=path,
      )
      elicitation_validate_optional_string(
        fields,
        "title",
        path=path + ".title",
      )
      elicitation_validate_optional_string(
        fields,
        "description",
        path=path + ".description",
      )
      match protocol_field(fields, "default") {
        Omitted | Null => ()
        Value(value) =>
          ignore(protocol_require_array(value, path=path + ".default"))
      }
      match protocol_field(fields, "minItems") {
        Omitted | Null => ()
        Value(value) =>
          ignore(
            elicitation_decode_non_negative_integer(
              value,
              path=path + ".minItems",
            ),
          )
      }
      match protocol_field(fields, "maxItems") {
        Omitted | Null => ()
        Value(value) =>
          ignore(
            elicitation_decode_non_negative_integer(
              value,
              path=path + ".maxItems",
            ),
          )
      }
      let items = protocol_required(fields, "items", path=path + ".items")
      elicitation_validate_array_items(items, path=path + ".items")
    }
    other => raise InvalidDiscriminator(path=path + ".type", value=other)
  }
  ignore(protocol_meta(fields, path=path + "._meta"))
}

///|
fn elicitation_validate_requested_schema(
  value : Json,
  path~ : String,
) -> Json raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["type", "properties", "required"],
    prefix=path,
  )
  let schema_type = protocol_required_string(
    fields,
    "type",
    path=path + ".type",
  )
  if schema_type != "object" {
    raise InvalidDiscriminator(path=path + ".type", value=schema_type)
  }
  let properties = protocol_require_object(
    protocol_required(fields, "properties", path=path + ".properties"),
    path=path + ".properties",
  )
  for name, property in properties {
    elicitation_validate_property_schema(
      property,
      path=path + ".properties." + name,
    )
  }
  match protocol_field(fields, "required") {
    Omitted | Null => ()
    Value(value) =>
      elicitation_validate_string_array(value, path=path + ".required")
  }
  value
}

///|
fn elicitation_decode_scope(
  fields : Map[String, Json],
  path~ : String,
) -> ElicitationScope raise ProtocolDecodeError {
  let has_request = fields.contains("requestId")
  let has_session = fields.contains("sessionId")
  if has_request && has_session {
    raise InvalidField(
      path~,
      reason="requestId and sessionId are mutually exclusive",
    )
  }
  if has_request {
    if fields.contains("toolCallId") {
      raise InvalidField(
        path=path + ".toolCallId",
        reason="toolCallId requires sessionId",
      )
    }
    Request(
      elicitation_decode_request_id(
        protocol_required(fields, "requestId", path=path + ".requestId"),
        path=path + ".requestId",
      ),
    )
  } else if has_session {
    let session_id = elicitation_decode_non_empty_string(
      protocol_required(fields, "sessionId", path=path + ".sessionId"),
      path=path + ".sessionId",
    )
    let tool_call_id : ProtocolNullable[ToolCallId] = match
      protocol_field(fields, "toolCallId") {
      Omitted => Omitted
      Null => Null
      Value(value) =>
        Value(
          elicitation_decode_non_empty_string(value, path=path + ".toolCallId"),
        )
    }
    Session(session_id~, tool_call_id~)
  } else {
    raise MissingField(path=path + ".requestId|sessionId")
  }
}

///|
fn elicitation_put_scope(
  fields : Map[String, Json],
  scope : ElicitationScope,
) -> Unit raise ProtocolDecodeError {
  match scope {
    Request(request_id) =>
      fields["requestId"] = elicitation_encode_request_id(request_id)
    Session(session_id~, tool_call_id~) => {
      fields["sessionId"] = Json::string(
        elicitation_require_non_empty(session_id, path="sessionId"),
      )
      match tool_call_id {
        Omitted => ()
        Null => fields["toolCallId"] = Json::null()
        Value(value) =>
          fields["toolCallId"] = Json::string(
            elicitation_require_non_empty(value, path="toolCallId"),
          )
      }
    }
  }
}

///|
fn elicitation_decode_mode(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  match protocol_decode_string(value, path~) {
    "form" => "form"
    "url" => "url"
    other => raise InvalidDiscriminator(path~, value=other)
  }
}

///|
fn elicitation_encode_action(value : ElicitationAction) -> Json {
  Json::string(
    match value {
      Accept => "accept"
      Decline => "decline"
      Cancel => "cancel"
    },
  )
}

///|
fn elicitation_decode_action(
  value : Json,
  path~ : String,
) -> ElicitationAction raise ProtocolDecodeError {
  match protocol_decode_string(value, path~) {
    "accept" => Accept
    "decline" => Decline
    "cancel" => Cancel
    other => raise InvalidDiscriminator(path~, value=other)
  }
}

///|
/// Validate one elicitation content value.  The fixed v1 schema allows
/// strings, integers, numbers, booleans, and arrays of strings; nulls and
/// nested objects are rejected instead of silently dropped.
fn elicitation_validate_content_value(
  value : Json,
  path~ : String,
) -> Unit raise ProtocolDecodeError {
  match value {
    String(_) => ()
    True | False => ()
    Array(values) =>
      for index, item in values {
        match item {
          String(_) => ()
          _ =>
            raise InvalidField(
              path=path + "[" + index.to_string() + "]",
              reason="content array values must be strings",
            )
        }
      }
    Null | Object(_) =>
      raise InvalidField(
        path~,
        reason="content values must be primitives or string arrays",
      )
    _ => ignore(protocol_decode_number(value, path~))
  }
}

///|
/// Validate the accept-action content object keyed by form field names and
/// return it unchanged.
fn elicitation_validate_content(
  value : Json,
  path~ : String,
) -> Json raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  for name, item in fields {
    elicitation_validate_content_value(item, path=path + "." + name)
  }
  value
}

///|
/// Decode the form/URL union for `elicitation/create`.
pub fn elicitation_create_params_from_json(
  value : Json,
  path? : String = "elicitation/create",
) -> ElicitationCreateParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    [
      "mode", "message", "requestedSchema", "elicitationId", "url", "requestId",
      "sessionId", "toolCallId", "_meta",
    ],
    prefix=path,
  )
  let mode = elicitation_decode_mode(
    protocol_required(fields, "mode", path=path + ".mode"),
    path=path + ".mode",
  )
  let message = protocol_required_string(
    fields,
    "message",
    path=path + ".message",
  )
  let scope = elicitation_decode_scope(fields, path~)
  let meta = protocol_meta(fields, path=path + "._meta")
  match mode {
    "form" => {
      if fields.contains("elicitationId") || fields.contains("url") {
        raise InvalidField(path~, reason="form mode cannot contain URL fields")
      }
      let requested_schema = elicitation_validate_requested_schema(
        protocol_required(
          fields,
          "requestedSchema",
          path=path + ".requestedSchema",
        ),
        path=path + ".requestedSchema",
      )
      Form({ scope, message, requested_schema, meta })
    }
    "url" => {
      if fields.contains("requestedSchema") {
        raise InvalidField(
          path~,
          reason="url mode cannot contain requestedSchema",
        )
      }
      let elicitation_id = elicitation_decode_non_empty_string(
        protocol_required(fields, "elicitationId", path=path + ".elicitationId"),
        path=path + ".elicitationId",
      )
      let url = elicitation_decode_non_empty_string(
        protocol_required(fields, "url", path=path + ".url"),
        path=path + ".url",
      )
      Url({ scope, elicitation_id, message, url, meta })
    }
    _ => abort("unreachable")
  }
}

///|
/// Encode the form/URL union for `elicitation/create`.
pub fn elicitation_create_params_to_json(
  value : ElicitationCreateParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  match value {
    Form(value) => {
      fields["mode"] = Json::string("form")
      fields["message"] = Json::string(value.message)
      elicitation_put_scope(fields, value.scope)
      fields["requestedSchema"] = elicitation_validate_requested_schema(
        value.requested_schema,
        path="requestedSchema",
      )
      protocol_put_meta(fields, value.meta)
    }
    Url(value) => {
      fields["mode"] = Json::string("url")
      fields["message"] = Json::string(value.message)
      fields["elicitationId"] = Json::string(
        elicitation_require_non_empty(
          value.elicitation_id,
          path="elicitationId",
        ),
      )
      fields["url"] = Json::string(
        elicitation_require_non_empty(value.url, path="url"),
      )
      elicitation_put_scope(fields, value.scope)
      protocol_put_meta(fields, value.meta)
    }
  }
  Json::object(fields)
}

///|
/// Decode the result of `elicitation/create`.  Only the accept outcome may
/// carry `content`; a decline or cancel carrying content is an explicit
/// invalid-params failure, never a silently ignored payload.
pub fn elicitation_create_result_from_json(
  value : Json,
  path? : String = "elicitation/create",
) -> ElicitationCreateResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["action", "content", "_meta"], prefix=path)
  let action = elicitation_decode_action(
    protocol_required(fields, "action", path=path + ".action"),
    path=path + ".action",
  )
  let content : ProtocolNullable[Json] = match
    protocol_field(fields, "content") {
    Omitted => Omitted
    Null =>
      match action {
        Accept => Null
        Decline | Cancel =>
          raise InvalidField(
            path=path + ".content",
            reason="decline and cancel must not carry content",
          )
      }
    Value(content) =>
      match action {
        Accept =>
          Value(elicitation_validate_content(content, path=path + ".content"))
        Decline | Cancel =>
          raise InvalidField(
            path=path + ".content",
            reason="decline and cancel must not carry content",
          )
      }
  }
  let meta = protocol_meta(fields, path=path + "._meta")
  { action, content, meta }
}

///|
/// Encode the result of `elicitation/create`.  Encoding a decline or cancel
/// result whose `content` is set fails fast instead of dropping the payload.
pub fn elicitation_create_result_to_json(
  value : ElicitationCreateResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["action"] = elicitation_encode_action(value.action)
  match value.action {
    Accept =>
      match value.content {
        Omitted => ()
        Null => fields["content"] = Json::null()
        Value(content) =>
          fields["content"] = elicitation_validate_content(
            content,
            path="content",
          )
      }
    Decline | Cancel =>
      match value.content {
        Omitted => ()
        Null | Value(_) =>
          raise InvalidField(
            path="content",
            reason="decline and cancel must not carry content",
          )
      }
  }
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the `elicitation/complete` notification parameters.
pub fn elicitation_complete_params_from_json(
  value : Json,
  path? : String = "elicitation/complete",
) -> ElicitationCompleteParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["elicitationId", "_meta"], prefix=path)
  let elicitation_id = elicitation_decode_non_empty_string(
    protocol_required(fields, "elicitationId", path=path + ".elicitationId"),
    path=path + ".elicitationId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { elicitation_id, meta }
}

///|
/// Encode the `elicitation/complete` notification parameters.
pub fn elicitation_complete_params_to_json(
  value : ElicitationCompleteParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["elicitationId"] = Json::string(
    elicitation_require_non_empty(value.elicitation_id, path="elicitationId"),
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
