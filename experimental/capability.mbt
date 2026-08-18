///|
/// v2 capability presence marker.  `MarkerUnsupported` is an omitted or null
/// capability; `MarkerSupported` is object presence, where `{}` is the
/// baseline payload.  Presence is not a patch: omitted and null collapse to
/// the same unsupported state, unlike `ExperimentalV2Patch`.
pub(all) enum ExperimentalV2Marker[T] {
  MarkerUnsupported
  MarkerSupported(T)
} derive(Eq, Debug)

///|
pub fn[T] experimental_v2_decode_marker(
  fields : Map[String, Json],
  key : String,
  path~ : String,
  decode : (Json, String) -> T raise ExperimentalV2DecodeError,
) -> ExperimentalV2Marker[T] raise ExperimentalV2DecodeError {
  match experimental_v2_patch_field(fields, key) {
    PatchOmitted | PatchNull => MarkerUnsupported
    PatchValue(value) => MarkerSupported(decode(value, path))
  }
}

///|
/// Encode one marker: unsupported omits the key; supported writes the payload
/// object.  An explicit wire null decodes as unsupported and encodes as
/// omission.
pub fn[T] experimental_v2_put_marker(
  fields : Map[String, Json],
  key : String,
  marker : ExperimentalV2Marker[T],
  encode : (T) -> Json raise ExperimentalV2DecodeError,
) -> Unit raise ExperimentalV2DecodeError {
  match marker {
    MarkerUnsupported => ()
    MarkerSupported(payload) => fields[key] = encode(payload)
  }
}

///|
/// Payload of every meta-only capability marker in the v2 stable baseline
/// (prompt image/audio/embeddedContext, session delete/additionalDirectories,
/// mcp stdio/http, agent auth, elicitation form/url).
pub(all) struct ExperimentalV2MarkerPayload {
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_marker_payload(
  value : Json,
  path? : String = "capability",
) -> ExperimentalV2MarkerPayload raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta"], prefix=path)
  { meta: experimental_v2_nested_meta(fields, path=path + "._meta") }
}

///|
pub fn experimental_v2_encode_marker_payload(
  value : ExperimentalV2MarkerPayload,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Elicitation capabilities of the Client.  Form and URL support are separate
/// markers.
pub(all) struct ExperimentalV2ElicitationCapabilities {
  form : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  url : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_elicitation_capabilities(
  value : Json,
  path? : String = "elicitation",
) -> ExperimentalV2ElicitationCapabilities raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta", "form", "url"], prefix=path)
  let form = experimental_v2_decode_marker(
    fields,
    "form",
    path=path + ".form",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let url = experimental_v2_decode_marker(fields, "url", path=path + ".url", (
    value,
    path,
  ) => experimental_v2_decode_marker_payload(value, path~))
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { form, url, meta }
}

///|
pub fn experimental_v2_encode_elicitation_capabilities(
  value : ExperimentalV2ElicitationCapabilities,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_marker(
    fields,
    "form",
    value.form,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_marker(
    fields,
    "url",
    value.url,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Capabilities advertised by the Client in `initialize`.
pub(all) struct ExperimentalV2ClientCapabilities {
  elicitation : ExperimentalV2Marker[ExperimentalV2ElicitationCapabilities]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_client_capabilities(
  value : Json,
  path? : String = "capabilities",
) -> ExperimentalV2ClientCapabilities raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(fields, ["_meta", "elicitation"], prefix=path)
  let elicitation = experimental_v2_decode_marker(
    fields,
    "elicitation",
    path=path + ".elicitation",
    (value, path) => {
      experimental_v2_decode_elicitation_capabilities(value, path~)
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { elicitation, meta }
}

///|
pub fn experimental_v2_encode_client_capabilities(
  value : ExperimentalV2ClientCapabilities,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_marker(
    fields,
    "elicitation",
    value.elicitation,
    experimental_v2_encode_elicitation_capabilities,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Prompt content extensions supported by the Agent beyond the baseline text
/// and resource-link content.
pub(all) struct ExperimentalV2PromptCapabilities {
  image : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  audio : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  embedded_context : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_prompt_capabilities(
  value : Json,
  path? : String = "prompt",
) -> ExperimentalV2PromptCapabilities raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "image", "audio", "embeddedContext"],
    prefix=path,
  )
  let image = experimental_v2_decode_marker(
    fields,
    "image",
    path=path + ".image",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let audio = experimental_v2_decode_marker(
    fields,
    "audio",
    path=path + ".audio",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let embedded_context = experimental_v2_decode_marker(
    fields,
    "embeddedContext",
    path=path + ".embeddedContext",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { image, audio, embedded_context, meta }
}

///|
pub fn experimental_v2_encode_prompt_capabilities(
  value : ExperimentalV2PromptCapabilities,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_marker(
    fields,
    "image",
    value.image,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_marker(
    fields,
    "audio",
    value.audio,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_marker(
    fields,
    "embeddedContext",
    value.embedded_context,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// MCP transports supported by the Agent for session lifecycle requests.
pub(all) struct ExperimentalV2McpCapabilities {
  stdio : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  http : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_mcp_capabilities(
  value : Json,
  path? : String = "mcp",
) -> ExperimentalV2McpCapabilities raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "stdio", "http"],
    prefix=path,
  )
  let stdio = experimental_v2_decode_marker(
    fields,
    "stdio",
    path=path + ".stdio",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let http = experimental_v2_decode_marker(
    fields,
    "http",
    path=path + ".http",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { stdio, http, meta }
}

///|
pub fn experimental_v2_encode_mcp_capabilities(
  value : ExperimentalV2McpCapabilities,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_marker(
    fields,
    "stdio",
    value.stdio,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_marker(
    fields,
    "http",
    value.http,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Session-surface extensions supported by the Agent.  The baseline methods
/// (`session/new`, `session/list`, `session/resume`, `session/close`,
/// `session/prompt`, `session/cancel`, `session/update`) are implied by the
/// `session` marker itself and have no per-method markers.
pub(all) struct ExperimentalV2SessionCapabilities {
  prompt : ExperimentalV2Marker[ExperimentalV2PromptCapabilities]
  mcp : ExperimentalV2Marker[ExperimentalV2McpCapabilities]
  delete : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  additional_directories : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_session_capabilities(
  value : Json,
  path? : String = "session",
) -> ExperimentalV2SessionCapabilities raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "prompt", "mcp", "delete", "additionalDirectories"],
    prefix=path,
  )
  let prompt = experimental_v2_decode_marker(
    fields,
    "prompt",
    path=path + ".prompt",
    (value, path) => experimental_v2_decode_prompt_capabilities(value, path~),
  )
  let mcp = experimental_v2_decode_marker(fields, "mcp", path=path + ".mcp", (
    value,
    path,
  ) => experimental_v2_decode_mcp_capabilities(value, path~))
  let delete = experimental_v2_decode_marker(
    fields,
    "delete",
    path=path + ".delete",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let additional_directories = experimental_v2_decode_marker(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { prompt, mcp, delete, additional_directories, meta }
}

///|
pub fn experimental_v2_encode_session_capabilities(
  value : ExperimentalV2SessionCapabilities,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_marker(
    fields,
    "prompt",
    value.prompt,
    experimental_v2_encode_prompt_capabilities,
  )
  experimental_v2_put_marker(
    fields,
    "mcp",
    value.mcp,
    experimental_v2_encode_mcp_capabilities,
  )
  experimental_v2_put_marker(
    fields,
    "delete",
    value.delete,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_marker(
    fields,
    "additionalDirectories",
    value.additional_directories,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Capabilities advertised by the Agent in `initialize`.  `auth` covers only
/// authentication-related extensions; `auth/login`/`auth/logout` support is
/// advertised by a non-empty `authMethods` list instead.
pub(all) struct ExperimentalV2AgentCapabilities {
  session : ExperimentalV2Marker[ExperimentalV2SessionCapabilities]
  auth : ExperimentalV2Marker[ExperimentalV2MarkerPayload]
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_agent_capabilities(
  value : Json,
  path? : String = "capabilities",
) -> ExperimentalV2AgentCapabilities raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "session", "auth"],
    prefix=path,
  )
  let session = experimental_v2_decode_marker(
    fields,
    "session",
    path=path + ".session",
    (value, path) => experimental_v2_decode_session_capabilities(value, path~),
  )
  let auth = experimental_v2_decode_marker(
    fields,
    "auth",
    path=path + ".auth",
    (value, path) => experimental_v2_decode_marker_payload(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { session, auth, meta }
}

///|
pub fn experimental_v2_encode_agent_capabilities(
  value : ExperimentalV2AgentCapabilities,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_marker(
    fields,
    "session",
    value.session,
    experimental_v2_encode_session_capabilities,
  )
  experimental_v2_put_marker(
    fields,
    "auth",
    value.auth,
    experimental_v2_encode_marker_payload,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn experimental_v2_required(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Json raise ExperimentalV2DecodeError {
  match fields.get(key) {
    Some(value) => value
    None => raise MissingField(path~)
  }
}

///|
fn experimental_v2_require_array(
  value : Json,
  path~ : String,
) -> Array[Json] raise ExperimentalV2DecodeError {
  match value {
    Array(items) => items
    _ => raise ExpectedArray(path~)
  }
}

///|
fn experimental_v2_decode_boolean(
  value : Json,
  path~ : String,
) -> Bool raise ExperimentalV2DecodeError {
  match value {
    True => true
    False => false
    _ => raise ExpectedBoolean(path~)
  }
}

///|
fn experimental_v2_decode_integer(
  value : Json,
  path~ : String,
) -> Int raise ExperimentalV2DecodeError {
  match value {
    Number(number, ..) =>
      if number == number.floor() &&
        number >= -2147483648.0 &&
        number <= 2147483647.0 {
        number.to_int()
      } else {
        raise InvalidField(path~, reason="expected an integer")
      }
    _ => raise ExpectedNumber(path~)
  }
}

///|
fn experimental_v2_put_meta(
  fields : Map[String, Json],
  meta : Json?,
) -> Unit raise ExperimentalV2DecodeError {
  match meta {
    None => ()
    Some(value) =>
      match value {
        Object(_) => fields["_meta"] = value
        _ =>
          raise InvalidField(
            path="_meta",
            reason="_meta must be an object or null",
          )
      }
  }
}

///|
/// Decode an optional field where omitted and null are equivalent.
fn[T] experimental_v2_decode_optional(
  fields : Map[String, Json],
  key : String,
  path~ : String,
  decode : (Json, String) -> T raise ExperimentalV2DecodeError,
) -> T? raise ExperimentalV2DecodeError {
  match experimental_v2_patch_field(fields, key) {
    PatchOmitted | PatchNull => None
    PatchValue(value) => Some(decode(value, path))
  }
}

///|
fn[T] experimental_v2_put_optional(
  fields : Map[String, Json],
  key : String,
  value : T?,
  encode : (T) -> Json raise ExperimentalV2DecodeError,
) -> Unit raise ExperimentalV2DecodeError {
  match value {
    None => ()
    Some(value) => fields[key] = encode(value)
  }
}

///|
fn[T] experimental_v2_decode_array(
  value : Json,
  path~ : String,
  decode_item : (Json, String) -> T raise ExperimentalV2DecodeError,
) -> Array[T] raise ExperimentalV2DecodeError {
  let items = experimental_v2_require_array(value, path~)
  let result : Array[T] = []
  for index, item in items {
    result.push(decode_item(item, path + "[" + index.to_string() + "]"))
  }
  result
}

///|
fn[T] experimental_v2_encode_array(
  values : Array[T],
  encode_item : (T) -> Json raise ExperimentalV2DecodeError,
) -> Json raise ExperimentalV2DecodeError {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(encode_item(value))
  }
  Json::array(encoded)
}
