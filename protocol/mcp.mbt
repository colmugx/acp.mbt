///|
/// One environment variable passed to a stdio MCP server.
pub(all) struct McpEnvVariable {
  name : String
  value : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// One HTTP header passed to an HTTP or SSE MCP server.
pub(all) struct McpHttpHeader {
  name : String
  value : String
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Stdio MCP transport configuration.
pub(all) struct McpServerStdio {
  name : String
  command : String
  args : Array[String]
  env : Array[McpEnvVariable]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// HTTP MCP transport configuration.
pub(all) struct McpServerHttp {
  name : String
  url : String
  headers : Array[McpHttpHeader]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Server-sent-events MCP transport configuration.
pub(all) struct McpServerSse {
  name : String
  url : String
  headers : Array[McpHttpHeader]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// MCP server transport union.  The wire discriminator is `type`.
pub(all) enum McpServer {
  Stdio(McpServerStdio)
  Http(McpServerHttp)
  Sse(McpServerSse)
} derive(Eq, Debug)

///|
fn mcp_decode_string(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  protocol_decode_string(value, path~)
}

///|
fn mcp_decode_string_array(
  value : Json,
  path~ : String,
) -> Array[String] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[String] = []
  for index, value in values {
    result.push(
      mcp_decode_string(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn mcp_nullable_meta(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Json] raise ProtocolDecodeError {
  protocol_meta(fields, path~)
}

///|
fn mcp_decode_env_variable(
  value : Json,
  path~ : String,
) -> McpEnvVariable raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta", "name", "value"], prefix=path)
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let variable_value = protocol_required_string(
    fields,
    "value",
    path=path + ".value",
  )
  let meta = mcp_nullable_meta(fields, path=path + "._meta")
  { name, value: variable_value, meta }
}

///|
fn mcp_encode_env_variable(
  value : McpEnvVariable,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["value"] = Json::string(value.value)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn mcp_decode_env_array(
  value : Json,
  path~ : String,
) -> Array[McpEnvVariable] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[McpEnvVariable] = []
  for index, value in values {
    result.push(
      mcp_decode_env_variable(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn mcp_encode_env_array(
  values : Array[McpEnvVariable],
) -> Json raise ProtocolDecodeError {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(mcp_encode_env_variable(value))
  }
  Json::array(encoded)
}

///|
fn mcp_decode_http_header(
  value : Json,
  path~ : String,
) -> McpHttpHeader raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["_meta", "name", "value"], prefix=path)
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let header_value = protocol_required_string(
    fields,
    "value",
    path=path + ".value",
  )
  let meta = mcp_nullable_meta(fields, path=path + "._meta")
  { name, value: header_value, meta }
}

///|
fn mcp_encode_http_header(
  value : McpHttpHeader,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["value"] = Json::string(value.value)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn mcp_decode_http_headers(
  value : Json,
  path~ : String,
) -> Array[McpHttpHeader] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[McpHttpHeader] = []
  for index, value in values {
    result.push(
      mcp_decode_http_header(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn mcp_encode_http_headers(
  values : Array[McpHttpHeader],
) -> Json raise ProtocolDecodeError {
  let encoded : Array[Json] = []
  for value in values {
    encoded.push(mcp_encode_http_header(value))
  }
  Json::array(encoded)
}

///|
fn mcp_decode_stdio_fields(
  fields : Map[String, Json],
  path~ : String,
) -> McpServerStdio raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["type", "_meta", "name", "command", "args", "env"],
    prefix=path,
  )
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let command = protocol_validate_absolute_path(
    protocol_required_string(fields, "command", path=path + ".command"),
    field_path=path + ".command",
  )
  let args = mcp_decode_string_array(
    protocol_required(fields, "args", path=path + ".args"),
    path=path + ".args",
  )
  let env = mcp_decode_env_array(
    protocol_required(fields, "env", path=path + ".env"),
    path=path + ".env",
  )
  let meta = mcp_nullable_meta(fields, path=path + "._meta")
  { name, command, args, env, meta }
}

///|
fn mcp_encode_stdio(value : McpServerStdio) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string("stdio")
  fields["name"] = Json::string(value.name)
  fields["command"] = Json::string(
    protocol_validate_absolute_path(value.command, field_path="command"),
  )
  fields["args"] = Json::array(value.args.map(value => Json::string(value)))
  fields["env"] = mcp_encode_env_array(value.env)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn mcp_decode_http_fields(
  fields : Map[String, Json],
  path~ : String,
) -> McpServerHttp raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["type", "_meta", "name", "url", "headers"],
    prefix=path,
  )
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let url = protocol_required_string(fields, "url", path=path + ".url")
  let headers = mcp_decode_http_headers(
    protocol_required(fields, "headers", path=path + ".headers"),
    path=path + ".headers",
  )
  let meta = mcp_nullable_meta(fields, path=path + "._meta")
  { name, url, headers, meta }
}

///|
fn mcp_encode_http(value : McpServerHttp) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string("http")
  fields["name"] = Json::string(value.name)
  fields["url"] = Json::string(value.url)
  fields["headers"] = mcp_encode_http_headers(value.headers)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
fn mcp_decode_sse_fields(
  fields : Map[String, Json],
  path~ : String,
) -> McpServerSse raise ProtocolDecodeError {
  protocol_reject_unknown(
    fields,
    ["type", "_meta", "name", "url", "headers"],
    prefix=path,
  )
  let name = protocol_required_string(fields, "name", path=path + ".name")
  let url = protocol_required_string(fields, "url", path=path + ".url")
  let headers = mcp_decode_http_headers(
    protocol_required(fields, "headers", path=path + ".headers"),
    path=path + ".headers",
  )
  let meta = mcp_nullable_meta(fields, path=path + "._meta")
  { name, url, headers, meta }
}

///|
fn mcp_encode_sse(value : McpServerSse) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string("sse")
  fields["name"] = Json::string(value.name)
  fields["url"] = Json::string(value.url)
  fields["headers"] = mcp_encode_http_headers(value.headers)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode one MCP server transport configuration.
///
/// Per the wire schema only `http`/`sse` carry a `type` tag; stdio is the
/// untagged variant, so an absent `type` decodes as stdio. An explicit
/// `"stdio"` tag stays accepted for backwards compatibility with payloads
/// produced before this fix.
pub fn mcp_server_from_json(
  value : Json,
  path? : String = "mcpServer",
) -> McpServer raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  let tag : String? = match protocol_field(fields, "type") {
    Omitted => None
    Null => raise ExpectedString(path=path + ".type")
    Value(discriminator) =>
      Some(protocol_decode_string(discriminator, path=path + ".type"))
  }
  match tag {
    None => Stdio(mcp_decode_stdio_fields(fields, path~))
    Some("stdio") => Stdio(mcp_decode_stdio_fields(fields, path~))
    Some("http") => Http(mcp_decode_http_fields(fields, path~))
    Some("sse") => Sse(mcp_decode_sse_fields(fields, path~))
    Some(other) => raise InvalidDiscriminator(path=path + ".type", value=other)
  }
}

///|
/// Encode one MCP server transport configuration with its wire discriminator.
pub fn mcp_server_to_json(value : McpServer) -> Json raise ProtocolDecodeError {
  match value {
    Stdio(value) => mcp_encode_stdio(value)
    Http(value) => mcp_encode_http(value)
    Sse(value) => mcp_encode_sse(value)
  }
}
