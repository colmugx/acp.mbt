///|
fn mcp_test_meta() -> ProtocolNullable[Json] {
  Omitted
}

///|
test "stdio MCP server round trips arrays and validates absolute command" {
  let server : McpServer = Stdio({
    name: "files",
    command: "/usr/local/bin/mcp-files",
    args: ["--root", "/tmp"],
    env: [{ name: "MODE", value: "test", meta: mcp_test_meta() }],
    meta: Null,
  })
  let encoded = mcp_server_to_json(server)
  assert_eq(
    encoded,
    protocol_parse_json(
      "{\"type\":\"stdio\",\"name\":\"files\",\"command\":\"/usr/local/bin/mcp-files\",\"args\":[\"--root\",\"/tmp\"],\"env\":[{\"name\":\"MODE\",\"value\":\"test\"}],\"_meta\":null}",
    ),
  )
  assert_eq(mcp_server_from_json(encoded), server)
}

///|
test "http and sse MCP unions preserve discriminator and headers" {
  let http : McpServer = Http({
    name: "remote-http",
    url: "https://example.test/mcp",
    headers: [
      { name: "Authorization", value: "Bearer token", meta: mcp_test_meta() },
    ],
    meta: mcp_test_meta(),
  })
  let sse : McpServer = Sse({
    name: "remote-sse",
    url: "https://example.test/events",
    headers: [],
    meta: mcp_test_meta(),
  })
  assert_eq(mcp_server_from_json(mcp_server_to_json(http)), http)
  assert_eq(mcp_server_from_json(mcp_server_to_json(sse)), sse)
  assert_eq(
    mcp_server_to_json(http),
    protocol_parse_json(
      "{\"type\":\"http\",\"name\":\"remote-http\",\"url\":\"https://example.test/mcp\",\"headers\":[{\"name\":\"Authorization\",\"value\":\"Bearer token\"}]}",
    ),
  )
}

///|
test "MCP unknown tags and fields fail with wire paths" {
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"websocket\",\"name\":\"x\",\"url\":\"wss://example.test\",\"headers\":[]}",
      ),
    )
  catch {
    InvalidDiscriminator(path="mcpServer.type", value="websocket") => ()
    _ => fail("expected unknown MCP discriminator")
  } noraise {
    _ => fail("expected unknown MCP discriminator")
  }
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"http\",\"name\":\"x\",\"url\":\"https://example.test\",\"headers\":[],\"extra\":true}",
      ),
    )
  catch {
    UnknownField(path="mcpServer.extra") => ()
    _ => fail("expected unknown MCP field")
  } noraise {
    _ => fail("expected unknown MCP field")
  }
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"stdio\",\"name\":\"x\",\"command\":\"relative/mcp\",\"args\":[],\"env\":[]}",
      ),
    )
  catch {
    InvalidPath(path="mcpServer.command", value="relative/mcp") => ()
    _ => fail("expected absolute command validation")
  } noraise {
    _ => fail("expected absolute command validation")
  }
}

///|
test "MCP required arrays and nested fields fail explicitly" {
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"stdio\",\"name\":\"x\",\"command\":\"/bin/mcp\",\"env\":[]}",
      ),
    )
  catch {
    MissingField(path="mcpServer.args") => ()
    _ => fail("expected missing args")
  } noraise {
    _ => fail("expected missing args")
  }
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"http\",\"name\":\"x\",\"url\":\"https://example.test\",\"headers\":[{\"name\":\"X\"}]}",
      ),
    )
  catch {
    MissingField(path="mcpServer.headers[0].value") => ()
    _ => fail("expected missing header value")
  } noraise {
    _ => fail("expected missing header value")
  }
  try
    mcp_server_from_json(
      protocol_parse_json(
        "{\"type\":\"stdio\",\"name\":\"x\",\"command\":\"/bin/mcp\",\"args\":[1],\"env\":[]}",
      ),
    )
  catch {
    ExpectedString(path="mcpServer.args[0]") => ()
    _ => fail("expected string argument error")
  } noraise {
    _ => fail("expected string argument error")
  }
}
