///|
/// One environment variable to set when launching an MCP server.
pub(all) struct ExperimentalV2EnvVariable {
  name : String
  value : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_env_variable(
  value : Json,
  path? : String = "envVariable",
) -> ExperimentalV2EnvVariable raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "name", "value"],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let item_value = experimental_v2_decode_string(
    experimental_v2_required(fields, "value", path=path + ".value"),
    path=path + ".value",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, value: item_value, meta, }
}

///|
pub fn experimental_v2_encode_env_variable(
  value : ExperimentalV2EnvVariable,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["value"] = Json::string(value.value)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// One HTTP header to set when making requests to an MCP server.
pub(all) struct ExperimentalV2HttpHeader {
  name : String
  value : String
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_http_header(
  value : Json,
  path? : String = "httpHeader",
) -> ExperimentalV2HttpHeader raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "name", "value"],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let item_value = experimental_v2_decode_string(
    experimental_v2_required(fields, "value", path=path + ".value"),
    path=path + ".value",
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, value: item_value, meta, }
}

///|
pub fn experimental_v2_encode_http_header(
  value : ExperimentalV2HttpHeader,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["name"] = Json::string(value.name)
  fields["value"] = Json::string(value.value)
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Stdio transport configuration for one MCP server.
pub(all) struct ExperimentalV2McpServerStdio {
  name : String
  command : String
  args : Array[String]?
  env : Array[ExperimentalV2EnvVariable]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_mcp_server_stdio(
  value : Json,
  path? : String = "mcpServer",
) -> ExperimentalV2McpServerStdio raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "type", "name", "command", "args", "env"],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let command = experimental_v2_validate_absolute_path(
    experimental_v2_decode_string(
      experimental_v2_required(fields, "command", path=path + ".command"),
      path=path + ".command",
    ),
    field_path=path + ".command",
  )
  let args = experimental_v2_decode_optional(
    fields,
    "args",
    path=path + ".args",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_string(item, path=item_path)
      })
    },
  )
  let env = experimental_v2_decode_optional(fields, "env", path=path + ".env", (
    value,
    path,
  ) => {
    experimental_v2_decode_array(value, path~, (item, item_path) => {
      experimental_v2_decode_env_variable(item, path=item_path)
    })
  })
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, command, args, env, meta, }
}

///|
pub fn experimental_v2_encode_mcp_server_stdio(
  value : ExperimentalV2McpServerStdio,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string("stdio")
  fields["name"] = Json::string(value.name)
  fields["command"] = Json::string(
    experimental_v2_validate_absolute_path(value.command, field_path="command"),
  )
  experimental_v2_put_optional(fields, "args", value.args, values => {
    experimental_v2_encode_array(values, value => Json::string(value))
  })
  experimental_v2_put_optional(fields, "env", value.env, values => {
    experimental_v2_encode_array(values, item => {
      experimental_v2_encode_env_variable(item)
    })
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// HTTP transport configuration for one MCP server.
pub(all) struct ExperimentalV2McpServerHttp {
  name : String
  url : String
  headers : Array[ExperimentalV2HttpHeader]?
  meta : Json?
} derive(Eq, Debug)

///|
pub fn experimental_v2_decode_mcp_server_http(
  value : Json,
  path? : String = "mcpServer",
) -> ExperimentalV2McpServerHttp raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  experimental_v2_reject_unknown(
    fields,
    ["_meta", "type", "name", "url", "headers"],
    prefix=path,
  )
  let name = experimental_v2_decode_string(
    experimental_v2_required(fields, "name", path=path + ".name"),
    path=path + ".name",
  )
  let url = experimental_v2_decode_string(
    experimental_v2_required(fields, "url", path=path + ".url"),
    path=path + ".url",
  )
  let headers = experimental_v2_decode_optional(
    fields,
    "headers",
    path=path + ".headers",
    (value, path) => {
      experimental_v2_decode_array(value, path~, (item, item_path) => {
        experimental_v2_decode_http_header(item, path=item_path)
      })
    },
  )
  let meta = experimental_v2_nested_meta(fields, path=path + "._meta")
  { name, url, headers, meta, }
}

///|
pub fn experimental_v2_encode_mcp_server_http(
  value : ExperimentalV2McpServerHttp,
) -> Json raise ExperimentalV2DecodeError {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string("http")
  fields["name"] = Json::string(value.name)
  fields["url"] = Json::string(value.url)
  experimental_v2_put_optional(fields, "headers", value.headers, values => {
    experimental_v2_encode_array(values, item => {
      experimental_v2_encode_http_header(item)
    })
  })
  experimental_v2_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Known MCP server transports: `type: "stdio"` or `type: "http"`.
pub(all) enum ExperimentalV2McpServerTransport {
  TransportStdio(ExperimentalV2McpServerStdio)
  TransportHttp(ExperimentalV2McpServerHttp)
} derive(Eq, Debug)

///|
/// Configuration for connecting to one MCP server.  The schema has an open
/// fallback, so transports this baseline does not know (including the removed
/// v1 `"sse"`) stay as `Extension`/`Future` raw payloads instead of decoding
/// as a known transport.
pub type ExperimentalV2McpServer = ExperimentalV2Open[
  ExperimentalV2McpServerTransport,
]

///|
pub fn experimental_v2_decode_mcp_server(
  value : Json,
  path? : String = "mcpServer",
) -> ExperimentalV2McpServer raise ExperimentalV2DecodeError {
  experimental_v2_decode_open(
    value,
    tag_key="type",
    ["http", "stdio"],
    (tag, payload) => {
      match tag {
        "http" =>
          TransportHttp(experimental_v2_decode_mcp_server_http(payload, path~))
        "stdio" =>
          TransportStdio(
            experimental_v2_decode_mcp_server_stdio(payload, path~),
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
pub fn experimental_v2_encode_mcp_server(
  value : ExperimentalV2McpServer,
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_open(value, tag_key="type", transport => {
    match transport {
      TransportStdio(stdio) => experimental_v2_encode_mcp_server_stdio(stdio)
      TransportHttp(http) => experimental_v2_encode_mcp_server_http(http)
    }
  })
}

///|
fn experimental_v2_decode_mcp_servers(
  value : Json,
  path~ : String,
) -> Array[ExperimentalV2McpServer] raise ExperimentalV2DecodeError {
  experimental_v2_decode_array(value, path~, (item, item_path) => {
    experimental_v2_decode_mcp_server(item, path=item_path)
  })
}

///|
fn experimental_v2_encode_mcp_servers(
  values : Array[ExperimentalV2McpServer],
) -> Json raise ExperimentalV2DecodeError {
  experimental_v2_encode_array(values, experimental_v2_encode_mcp_server)
}
