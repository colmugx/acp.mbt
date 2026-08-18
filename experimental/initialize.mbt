///|
/// Role-agnostic implementation info exchanged in `initialize` both ways.
pub(all) struct ExperimentalV2Implementation {
  name : String
  title : String?
  version : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_implementation(
  value : Json,
  path? : String = "info",
) -> ExperimentalV2Implementation raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "name", "title", "version"],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let title = experimental_v2_decode_optional(
    fields,
    "title",
    path=path + ".title",
    (value, path) => experimental_v2_decode_string(value, path~),
  )
  let version = experimental_v2_decode_string(
    experimental_v2_required(fields, "version", path=path + ".version"),
    path=path + ".version",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, title, version, meta }
}

///|
pub fn experimental_v2_encode_implementation(
  value : ExperimentalV2Implementation,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  experimental_v2_put_optional(fields, "title", value.title, value => {
    Json::string(value)
  })
  fields["version"] = Json::string(value.version)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn experimental_v2_decode_protocol_version(
  value : Json,
  path~ : String,
) -> Int raise ExperimentalV2DecodeError {
  let version = experimental_v2_decode_integer(value, path~)
  if version < 0 || version > 65535 {
    raise InvalidField(
      path~,
      reason="protocolVersion must be an integer between 0 and 65535",
    )
  }
  version
}

///|
/// Parameters of `initialize`, sent by the Client.  `capabilities` is decoded
/// with the schema default: an omitted field is the empty object, while any
/// present value must be a valid object.
pub(all) struct ExperimentalV2InitializeParams {
  protocol_version : Int
  info : ExperimentalV2Implementation
  capabilities : ExperimentalV2ClientCapabilities
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_initialize_params(
  value : Json,
  path? : String = "initialize",
) -> ExperimentalV2InitializeParams raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "protocolVersion", "info", "capabilities"],
    prefix=path,
  )
  let protocol_version = experimental_v2_decode_protocol_version(
    experimental_v2_required(
      fields,
      "protocolVersion",
      path=path + ".protocolVersion",
    ),
    path=path + ".protocolVersion",
  )
  let info = experimental_v2_decode_implementation(
    experimental_v2_required(fields, "info", path=path + ".info"),
    path=path + ".info",
  )
  let capabilities : ExperimentalV2ClientCapabilities = match
    fields.get("capabilities") {
    None => { elicitation: MarkerUnsupported, meta: None }
    Some(value) =>
      experimental_v2_decode_client_capabilities(
        value,
        path=path + ".capabilities",
      )
  }
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { protocol_version, info, capabilities, meta }
}

///|
pub fn experimental_v2_encode_initialize_params(
  value : ExperimentalV2InitializeParams,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["protocolVersion"] = Json::number(value.protocol_version.to_double())
  fields["info"] = experimental_v2_encode_implementation(value.info)
  fields["capabilities"] = experimental_v2_encode_client_capabilities(
    value.capabilities,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Result of `initialize`, returned by the Agent.  A non-empty `auth_methods`
/// advertises that the Agent supports both `auth/login` and `auth/logout`.
pub(all) struct ExperimentalV2InitializeResult {
  protocol_version : Int
  info : ExperimentalV2Implementation
  capabilities : ExperimentalV2AgentCapabilities
  auth_methods : Array[ExperimentalV2AuthMethod]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_initialize_result(
  value : Json,
  path? : String = "initialize",
) -> ExperimentalV2InitializeResult raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "protocolVersion", "info", "capabilities", "authMethods"],
    prefix=path,
  )
  let protocol_version = experimental_v2_decode_protocol_version(
    experimental_v2_required(
      fields,
      "protocolVersion",
      path=path + ".protocolVersion",
    ),
    path=path + ".protocolVersion",
  )
  let info = experimental_v2_decode_implementation(
    experimental_v2_required(fields, "info", path=path + ".info"),
    path=path + ".info",
  )
  let capabilities : ExperimentalV2AgentCapabilities = match
    fields.get("capabilities") {
    None => { session: MarkerUnsupported, auth: MarkerUnsupported, meta: None }
    Some(value) =>
      experimental_v2_decode_agent_capabilities(
        value,
        path=path + ".capabilities",
      )
  }
  let auth_methods = experimental_v2_decode_optional(
    fields,
    "authMethods",
    path=path + ".authMethods",
    (value, path) => experimental_v2_decode_auth_methods(value, path~),
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { protocol_version, info, capabilities, auth_methods, meta }
}

///|
pub fn experimental_v2_encode_initialize_result(
  value : ExperimentalV2InitializeResult,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["protocolVersion"] = Json::number(value.protocol_version.to_double())
  fields["info"] = experimental_v2_encode_implementation(value.info)
  fields["capabilities"] = experimental_v2_encode_agent_capabilities(
    value.capabilities,
  )
  experimental_v2_put_optional(
    fields,
    "authMethods",
    value.auth_methods,
    experimental_v2_encode_auth_methods,
  )
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}
