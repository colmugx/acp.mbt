///|
/// Information identifying an ACP client or agent implementation.
pub(all) struct Implementation {
  name : String
  title : ProtocolNullable[String]
  version : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// An empty object used as a capability support marker.
///
/// The marker is distinct from an omitted or null capability.  `_meta` is the
/// only extension accepted by the wire schema; all other fields are rejected.
pub(all) struct CapabilityMarker {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Client file-system capabilities.  Read and write are independent gates.
pub(all) struct ClientFileSystemCapabilities {
  read_text_file : ProtocolNullable[Bool]
  write_text_file : ProtocolNullable[Bool]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Client elicitation modes.  An empty outer object supports neither mode.
pub(all) struct ClientElicitationCapabilities {
  form : ProtocolNullable[CapabilityMarker]
  url : ProtocolNullable[CapabilityMarker]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Client-side config-option capabilities.
pub(all) struct ClientConfigOptionCapabilities {
  boolean : ProtocolNullable[CapabilityMarker]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Client authentication capabilities (upstream unstable `auth` field): which
/// authentication method types the client can handle. Decoded so editors that
/// advertise it do not fail initialization.
pub(all) struct ClientAuthCapabilities {
  terminal : ProtocolNullable[Bool]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Client session capabilities advertised during initialization.
pub(all) struct ClientSessionCapabilities {
  config_options : ProtocolNullable[ClientConfigOptionCapabilities]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Capabilities advertised by the Client.
pub(all) struct ClientCapabilities {
  fs : ProtocolNullable[ClientFileSystemCapabilities]
  terminal : ProtocolNullable[Bool]
  elicitation : ProtocolNullable[ClientElicitationCapabilities]
  session : ProtocolNullable[ClientSessionCapabilities]
  /// Upstream unstable field: the client can receive plan session updates.
  plan : ProtocolNullable[CapabilityMarker]
  /// Upstream unstable field; see `ClientAuthCapabilities`.
  auth : ProtocolNullable[ClientAuthCapabilities]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Agent prompt content capabilities.
pub(all) struct AgentPromptCapabilities {
  image : ProtocolNullable[Bool]
  audio : ProtocolNullable[Bool]
  embedded_context : ProtocolNullable[Bool]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// MCP transports supported by the Agent.
pub(all) struct AgentMcpCapabilities {
  http : ProtocolNullable[Bool]
  sse : ProtocolNullable[Bool]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Agent authentication capabilities.
pub(all) struct AgentAuthCapabilities {
  logout : ProtocolNullable[CapabilityMarker]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Optional Agent session methods and workspace-root support.
pub(all) struct AgentSessionCapabilities {
  list : ProtocolNullable[CapabilityMarker]
  delete : ProtocolNullable[CapabilityMarker]
  resume_capability : ProtocolNullable[CapabilityMarker]
  close : ProtocolNullable[CapabilityMarker]
  additional_directories : ProtocolNullable[CapabilityMarker]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Capabilities advertised by the Agent.
pub(all) struct AgentCapabilities {
  load_session : ProtocolNullable[Bool]
  prompt_capabilities : ProtocolNullable[AgentPromptCapabilities]
  mcp_capabilities : ProtocolNullable[AgentMcpCapabilities]
  auth : ProtocolNullable[AgentAuthCapabilities]
  session_capabilities : ProtocolNullable[AgentSessionCapabilities]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Initialize request parameters sent by a Client.
pub(all) struct InitializeParams {
  protocol_version : Int
  client_capabilities : ProtocolNullable[ClientCapabilities]
  client_info : ProtocolNullable[Implementation]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Initialize response returned by an Agent.
pub(all) struct InitializeResult {
  protocol_version : Int
  agent_capabilities : ProtocolNullable[AgentCapabilities]
  auth_methods : ProtocolNullable[Array[AuthMethod]]
  agent_info : ProtocolNullable[Implementation]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// One authentication method advertised by an Agent.
pub(all) struct AuthMethod {
  id : String
  name : String
  description : ProtocolNullable[String]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Authenticate request parameters.
pub(all) struct AuthenticateParams {
  method_id : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Authenticate response.  It carries only optional protocol metadata.
pub(all) struct AuthenticateResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Logout request parameters.
pub(all) struct LogoutParams {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Logout response.
pub(all) struct LogoutResult {
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn init_decode_bool(
  value : Json,
  path~ : String,
) -> Bool raise ProtocolDecodeError {
  match value {
    True => true
    False => false
    _ => raise ExpectedBoolean(path~)
  }
}

///|
fn init_decode_int(
  value : Json,
  path~ : String,
) -> Int raise ProtocolDecodeError {
  @json.from_json(value) catch {
    _ => raise InvalidField(path~, reason="expected an integer")
  }
}

///|
fn[T] init_put_nullable(
  fields : Map[String, Json],
  key : String,
  value : ProtocolNullable[T],
  encode : (T) -> Json raise ProtocolDecodeError,
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields[key] = Json::null()
    Value(value) => fields[key] = encode(value)
  }
}

///|
fn init_decode_protocol_version(
  value : Json,
  path~ : String,
) -> Int raise ProtocolDecodeError {
  let version = init_decode_int(value, path~)
  if version < 0 || version > 65535 {
    raise InvalidField(path~, reason="protocol version must fit uint16")
  }
  version
}

///|
fn init_decode_non_empty_string(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  let text = protocol_decode_string(value, path~)
  if text == "" {
    raise InvalidField(path~, reason="string must not be empty")
  }
  text
}

///|
fn init_nullable_bool(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[Bool] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(init_decode_bool(value, path~))
  }
}

///|
fn init_nullable_marker(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[CapabilityMarker] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(capability_marker_from_json(value, path~))
  }
}

///|
fn init_nullable_client_fs(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[ClientFileSystemCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(client_file_system_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_client_elicitation(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[ClientElicitationCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(client_elicitation_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_client_config_options(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[ClientConfigOptionCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(client_config_option_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_client_session(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[ClientSessionCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(client_session_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_client_auth(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[ClientAuthCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(client_auth_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_prompt_capabilities(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[AgentPromptCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(agent_prompt_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_mcp_capabilities(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[AgentMcpCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(agent_mcp_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_auth_capabilities(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[AgentAuthCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(agent_auth_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_session_capabilities(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[AgentSessionCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(agent_session_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_agent_capabilities(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[AgentCapabilities] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(agent_capabilities_from_json(value, path~))
  }
}

///|
fn init_nullable_implementation(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[Implementation] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(implementation_from_json(value, path~))
  }
}

///|
fn init_decode_auth_methods(
  value : Json,
  path~ : String,
) -> Array[AuthMethod] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let methods : Array[AuthMethod] = []
  for index, value in values {
    methods.push(
      auth_method_from_json(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  methods
}

///|
fn init_encode_auth_methods(
  values : Array[AuthMethod],
) -> Json raise ProtocolDecodeError {
  let encoded : Array[Json] = []
  for entry in values {
    encoded.push(auth_method_to_json(entry))
  }
  Json::array(encoded)
}

///|
/// Decode a capability marker object.
pub fn capability_marker_from_json(
  value : Json,
  path? : String = "capability",
) -> CapabilityMarker raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta"], prefix=path)
  let meta = protocol_meta(fields, path=path + "._meta")
  { meta, }
}

///|
/// Encode a capability marker object.
pub fn capability_marker_to_json(
  value : CapabilityMarker,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode implementation information.
pub fn implementation_from_json(
  value : Json,
  path? : String = "implementation",
) -> Implementation raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["_meta", "name", "title", "version"],
    prefix=path,
  )
  let name = init_decode_non_empty_string(
    protocol_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let title = protocol_nullable_string(fields, "title", path=path + ".title")
  let version = init_decode_non_empty_string(
    protocol_required(fields, "version", path=path + ".version"),
    path=path + ".version",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { name, title, version, meta }
}

///|
/// Encode implementation information.
pub fn implementation_to_json(
  value : Implementation,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  init_put_nullable(fields, "title", value.title, value => Json::string(value))
  fields["version"] = Json::string(value.version)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_client_file_system_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ClientFileSystemCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["_meta", "readTextFile", "writeTextFile"],
    prefix=path,
  )
  let read_text_file = init_nullable_bool(
    fields,
    "readTextFile",
    path=path + ".readTextFile",
  )
  let write_text_file = init_nullable_bool(
    fields,
    "writeTextFile",
    path=path + ".writeTextFile",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { read_text_file, write_text_file, meta }
}

///|
/// Decode Client file-system capabilities.
pub fn client_file_system_capabilities_from_json(
  value : Json,
  path? : String = "fs",
) -> ClientFileSystemCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_client_file_system_fields(fields, path~)
}

///|
/// Encode Client file-system capabilities.
pub fn client_file_system_capabilities_to_json(
  value : ClientFileSystemCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "readTextFile", value.read_text_file, value => {
    Json::boolean(value)
  })
  init_put_nullable(fields, "writeTextFile", value.write_text_file, value => {
    Json::boolean(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_client_elicitation_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ClientElicitationCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(fields, ["_meta", "form", "url"], prefix=path)
  let form = init_nullable_marker(fields, "form", path=path + ".form")
  let url = init_nullable_marker(fields, "url", path=path + ".url")
  let meta = protocol_meta(fields, path=path + "._meta")
  { form, url, meta }
}

///|
/// Decode Client elicitation capabilities.
pub fn client_elicitation_capabilities_from_json(
  value : Json,
  path? : String = "elicitation",
) -> ClientElicitationCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_client_elicitation_fields(fields, path~)
}

///|
/// Encode Client elicitation capabilities.
pub fn client_elicitation_capabilities_to_json(
  value : ClientElicitationCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "form", value.form, capability_marker_to_json)
  init_put_nullable(fields, "url", value.url, capability_marker_to_json)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_client_config_option_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ClientConfigOptionCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(fields, ["_meta", "boolean"], prefix=path)
  let boolean = init_nullable_marker(fields, "boolean", path=path + ".boolean")
  let meta = protocol_meta(fields, path=path + "._meta")
  { boolean, meta }
}

///|
/// Decode Client config-option capabilities.
pub fn client_config_option_capabilities_from_json(
  value : Json,
  path? : String = "configOptions",
) -> ClientConfigOptionCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_client_config_option_fields(fields, path~)
}

///|
/// Encode Client config-option capabilities.
pub fn client_config_option_capabilities_to_json(
  value : ClientConfigOptionCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "boolean", value.boolean, capability_marker_to_json)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_client_session_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ClientSessionCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(fields, ["_meta", "configOptions"], prefix=path)
  let config_options = init_nullable_client_config_options(
    fields,
    "configOptions",
    path=path + ".configOptions",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { config_options, meta }
}

///|
/// Decode Client session capabilities.
pub fn client_session_capabilities_from_json(
  value : Json,
  path? : String = "session",
) -> ClientSessionCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_client_session_fields(fields, path~)
}

///|
/// Encode Client session capabilities.
pub fn client_session_capabilities_to_json(
  value : ClientSessionCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(
    fields,
    "configOptions",
    value.config_options,
    client_config_option_capabilities_to_json,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode Client authentication capabilities.
pub fn client_auth_capabilities_from_json(
  value : Json,
  path? : String = "auth",
) -> ClientAuthCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta", "terminal"], prefix=path)
  let terminal = init_nullable_bool(fields, "terminal", path=path + ".terminal")
  let meta = protocol_meta(fields, path=path + "._meta")
  { terminal, meta }
}

///|
/// Encode Client authentication capabilities.
pub fn client_auth_capabilities_to_json(
  value : ClientAuthCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "terminal", value.terminal, value => {
    Json::boolean(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_client_capabilities_fields(
  fields : Map[String, Json],
  path~ : String,
) -> ClientCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["_meta", "fs", "terminal", "elicitation", "session", "plan", "auth"],
    prefix=path,
  )
  let fs = init_nullable_client_fs(fields, "fs", path=path + ".fs")
  let terminal = init_nullable_bool(fields, "terminal", path=path + ".terminal")
  let elicitation = init_nullable_client_elicitation(
    fields,
    "elicitation",
    path=path + ".elicitation",
  )
  let session = init_nullable_client_session(
    fields,
    "session",
    path=path + ".session",
  )
  let plan = init_nullable_marker(fields, "plan", path=path + ".plan")
  let auth = init_nullable_client_auth(fields, "auth", path=path + ".auth")
  let meta = protocol_meta(fields, path=path + "._meta")
  { fs, terminal, elicitation, session, plan, auth, meta }
}

///|
/// Decode Client capabilities.
pub fn client_capabilities_from_json(
  value : Json,
  path? : String = "clientCapabilities",
) -> ClientCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_client_capabilities_fields(fields, path~)
}

///|
/// Encode Client capabilities.
pub fn client_capabilities_to_json(
  value : ClientCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(
    fields,
    "fs",
    value.fs,
    client_file_system_capabilities_to_json,
  )
  init_put_nullable(fields, "terminal", value.terminal, value => {
    Json::boolean(value)
  })
  init_put_nullable(
    fields,
    "elicitation",
    value.elicitation,
    client_elicitation_capabilities_to_json,
  )
  init_put_nullable(
    fields,
    "session",
    value.session,
    client_session_capabilities_to_json,
  )
  init_put_nullable(fields, "plan", value.plan, capability_marker_to_json)
  init_put_nullable(
    fields,
    "auth",
    value.auth,
    client_auth_capabilities_to_json,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_agent_prompt_fields(
  fields : Map[String, Json],
  path~ : String,
) -> AgentPromptCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["_meta", "image", "audio", "embeddedContext"],
    prefix=path,
  )
  let image = init_nullable_bool(fields, "image", path=path + ".image")
  let audio = init_nullable_bool(fields, "audio", path=path + ".audio")
  let embedded_context = init_nullable_bool(
    fields,
    "embeddedContext",
    path=path + ".embeddedContext",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { image, audio, embedded_context, meta }
}

///|
/// Decode Agent prompt capabilities.
pub fn agent_prompt_capabilities_from_json(
  value : Json,
  path? : String = "promptCapabilities",
) -> AgentPromptCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_agent_prompt_fields(fields, path~)
}

///|
/// Encode Agent prompt capabilities.
pub fn agent_prompt_capabilities_to_json(
  value : AgentPromptCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "image", value.image, value => Json::boolean(value))
  init_put_nullable(fields, "audio", value.audio, value => Json::boolean(value))
  init_put_nullable(fields, "embeddedContext", value.embedded_context, value => {
    Json::boolean(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_agent_mcp_fields(
  fields : Map[String, Json],
  path~ : String,
) -> AgentMcpCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(fields, ["_meta", "http", "sse"], prefix=path)
  let http = init_nullable_bool(fields, "http", path=path + ".http")
  let sse = init_nullable_bool(fields, "sse", path=path + ".sse")
  let meta = protocol_meta(fields, path=path + "._meta")
  { http, sse, meta }
}

///|
/// Decode Agent MCP capabilities.
pub fn agent_mcp_capabilities_from_json(
  value : Json,
  path? : String = "mcpCapabilities",
) -> AgentMcpCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_agent_mcp_fields(fields, path~)
}

///|
/// Encode Agent MCP capabilities.
pub fn agent_mcp_capabilities_to_json(
  value : AgentMcpCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "http", value.http, value => Json::boolean(value))
  init_put_nullable(fields, "sse", value.sse, value => Json::boolean(value))
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_agent_auth_fields(
  fields : Map[String, Json],
  path~ : String,
) -> AgentAuthCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(fields, ["_meta", "logout"], prefix=path)
  let logout = init_nullable_marker(fields, "logout", path=path + ".logout")
  let meta = protocol_meta(fields, path=path + "._meta")
  { logout, meta }
}

///|
/// Decode Agent authentication capabilities.
pub fn agent_auth_capabilities_from_json(
  value : Json,
  path? : String = "auth",
) -> AgentAuthCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_agent_auth_fields(fields, path~)
}

///|
/// Encode Agent authentication capabilities.
pub fn agent_auth_capabilities_to_json(
  value : AgentAuthCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "logout", value.logout, capability_marker_to_json)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_agent_session_fields(
  fields : Map[String, Json],
  path~ : String,
) -> AgentSessionCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["_meta", "list", "delete", "resume", "close", "additionalDirectories"],
    prefix=path,
  )
  let list = init_nullable_marker(fields, "list", path=path + ".list")
  let delete = init_nullable_marker(fields, "delete", path=path + ".delete")
  let resume_capability = init_nullable_marker(
    fields,
    "resume",
    path=path + ".resume",
  )
  let close = init_nullable_marker(fields, "close", path=path + ".close")
  let additional_directories = init_nullable_marker(
    fields,
    "additionalDirectories",
    path=path + ".additionalDirectories",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { list, delete, resume_capability, close, additional_directories, meta }
}

///|
/// Decode Agent session capabilities.
pub fn agent_session_capabilities_from_json(
  value : Json,
  path? : String = "sessionCapabilities",
) -> AgentSessionCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_agent_session_fields(fields, path~)
}

///|
/// Encode Agent session capabilities.
pub fn agent_session_capabilities_to_json(
  value : AgentSessionCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "list", value.list, capability_marker_to_json)
  init_put_nullable(fields, "delete", value.delete, capability_marker_to_json)
  init_put_nullable(
    fields,
    "resume",
    value.resume_capability,
    capability_marker_to_json,
  )
  init_put_nullable(fields, "close", value.close, capability_marker_to_json)
  init_put_nullable(
    fields,
    "additionalDirectories",
    value.additional_directories,
    capability_marker_to_json,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_agent_capabilities_fields(
  fields : Map[String, Json],
  path~ : String,
) -> AgentCapabilities raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    [
      "_meta", "loadSession", "promptCapabilities", "mcpCapabilities", "auth", "sessionCapabilities",
    ],
    prefix=path,
  )
  let load_session = init_nullable_bool(
    fields,
    "loadSession",
    path=path + ".loadSession",
  )
  let prompt_capabilities = init_nullable_prompt_capabilities(
    fields,
    "promptCapabilities",
    path=path + ".promptCapabilities",
  )
  let mcp_capabilities = init_nullable_mcp_capabilities(
    fields,
    "mcpCapabilities",
    path=path + ".mcpCapabilities",
  )
  let auth = init_nullable_auth_capabilities(
    fields,
    "auth",
    path=path + ".auth",
  )
  let session_capabilities = init_nullable_session_capabilities(
    fields,
    "sessionCapabilities",
    path=path + ".sessionCapabilities",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  {
    load_session,
    prompt_capabilities,
    mcp_capabilities,
    auth,
    session_capabilities,
    meta,
  }
}

///|
/// Decode Agent capabilities.
pub fn agent_capabilities_from_json(
  value : Json,
  path? : String = "agentCapabilities",
) -> AgentCapabilities raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  decode_agent_capabilities_fields(fields, path~)
}

///|
/// Encode Agent capabilities.
pub fn agent_capabilities_to_json(
  value : AgentCapabilities,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  init_put_nullable(fields, "loadSession", value.load_session, value => {
    Json::boolean(value)
  })
  init_put_nullable(
    fields,
    "promptCapabilities",
    value.prompt_capabilities,
    agent_prompt_capabilities_to_json,
  )
  init_put_nullable(
    fields,
    "mcpCapabilities",
    value.mcp_capabilities,
    agent_mcp_capabilities_to_json,
  )
  init_put_nullable(fields, "auth", value.auth, agent_auth_capabilities_to_json)
  init_put_nullable(
    fields,
    "sessionCapabilities",
    value.session_capabilities,
    agent_session_capabilities_to_json,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode initialization request parameters.
pub fn initialize_params_from_json(
  value : Json,
  path? : String = "initialize",
) -> InitializeParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["_meta", "protocolVersion", "clientCapabilities", "clientInfo"],
    prefix=path,
  )
  let protocol_version = init_decode_protocol_version(
    protocol_required(fields, "protocolVersion", path=path + ".protocolVersion"),
    path=path + ".protocolVersion",
  )
  let client_capabilities = match protocol_field(fields, "clientCapabilities") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(
        client_capabilities_from_json(value, path=path + ".clientCapabilities"),
      )
  }
  let client_info = init_nullable_implementation(
    fields,
    "clientInfo",
    path=path + ".clientInfo",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { protocol_version, client_capabilities, client_info, meta }
}

///|
/// Encode initialization request parameters.
pub fn initialize_params_to_json(
  value : InitializeParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["protocolVersion"] = Json::number(value.protocol_version.to_double())
  init_put_nullable(
    fields,
    "clientCapabilities",
    value.client_capabilities,
    client_capabilities_to_json,
  )
  init_put_nullable(
    fields,
    "clientInfo",
    value.client_info,
    implementation_to_json,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode initialization response data.
pub fn initialize_result_from_json(
  value : Json,
  path? : String = "initialize",
) -> InitializeResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    [
      "_meta", "protocolVersion", "agentCapabilities", "authMethods", "agentInfo",
    ],
    prefix=path,
  )
  let protocol_version = init_decode_protocol_version(
    protocol_required(fields, "protocolVersion", path=path + ".protocolVersion"),
    path=path + ".protocolVersion",
  )
  let agent_capabilities = init_nullable_agent_capabilities(
    fields,
    "agentCapabilities",
    path=path + ".agentCapabilities",
  )
  let auth_methods = match protocol_field(fields, "authMethods") {
    Omitted => Omitted
    Null => Null
    Value(value) =>
      Value(init_decode_auth_methods(value, path=path + ".authMethods"))
  }
  let agent_info = init_nullable_implementation(
    fields,
    "agentInfo",
    path=path + ".agentInfo",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { protocol_version, agent_capabilities, auth_methods, agent_info, meta }
}

///|
/// Encode initialization response data.
pub fn initialize_result_to_json(
  value : InitializeResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["protocolVersion"] = Json::number(value.protocol_version.to_double())
  init_put_nullable(
    fields,
    "agentCapabilities",
    value.agent_capabilities,
    agent_capabilities_to_json,
  )
  init_put_nullable(
    fields,
    "authMethods",
    value.auth_methods,
    init_encode_auth_methods,
  )
  init_put_nullable(
    fields,
    "agentInfo",
    value.agent_info,
    implementation_to_json,
  )
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode one authentication method.
pub fn auth_method_from_json(
  value : Json,
  path? : String = "authMethod",
) -> AuthMethod raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(
    fields,
    ["_meta", "id", "name", "description"],
    prefix=path,
  )
  let id = init_decode_non_empty_string(
    protocol_required(fields, "id", path=path + ".id"),
    path=path + ".id",
  )
  let name = init_decode_non_empty_string(
    protocol_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let description = protocol_nullable_string(
    fields,
    "description",
    path=path + ".description",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { id, name, description, meta }
}

///|
/// Encode one authentication method.
pub fn auth_method_to_json(
  value : AuthMethod,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["id"] = Json::string(value.id)
  fields["name"] = Json::string(value.name)
  init_put_nullable(fields, "description", value.description, value => {
    Json::string(value)
  })
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode authenticate request parameters.
pub fn authenticate_params_from_json(
  value : Json,
  path? : String = "authenticate",
) -> AuthenticateParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta", "methodId"], prefix=path)
  let method_id = init_decode_non_empty_string(
    protocol_required(fields, "methodId", path=path + ".methodId"),
    path=path + ".methodId",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { method_id, meta }
}

///|
/// Encode authenticate request parameters.
pub fn authenticate_params_to_json(
  value : AuthenticateParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["methodId"] = Json::string(value.method_id)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn decode_meta_only(
  value : Json,
  path~ : String,
) -> ProtocolNullable[Json] raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta"], prefix=path)
  protocol_meta(fields, path=path + "._meta")
}

///|
/// Decode authenticate response data.
pub fn authenticate_result_from_json(
  value : Json,
  path? : String = "authenticate",
) -> AuthenticateResult raise ProtocolDecodeError {
  { meta: decode_meta_only(value, path~) }
}

///|
/// Encode authenticate response data.
pub fn authenticate_result_to_json(
  value : AuthenticateResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode logout request parameters.
pub fn logout_params_from_json(
  value : Json,
  path? : String = "logout",
) -> LogoutParams raise ProtocolDecodeError {
  { meta: decode_meta_only(value, path~) }
}

///|
/// Encode logout request parameters.
pub fn logout_params_to_json(
  value : LogoutParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode logout response data.
pub fn logout_result_from_json(
  value : Json,
  path? : String = "logout",
) -> LogoutResult raise ProtocolDecodeError {
  { meta: decode_meta_only(value, path~) }
}

///|
/// Encode logout response data.
pub fn logout_result_to_json(
  value : LogoutResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
