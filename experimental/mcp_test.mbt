///|
test "v2 mcp stdio server round-trips args and env" {
  let decoded = model_test_round_trip(
    "{\"type\":\"stdio\",\"name\":\"fs\",\"command\":\"/usr/bin/fs-mcp\",\"args\":[\"--flag\",\"x\"],\"env\":[{\"name\":\"K\",\"value\":\"V\"}],\"_meta\":{}}",
    value => experimental_v2_decode_mcp_server(value),
    experimental_v2_encode_mcp_server,
  )
  assert_true(
    decoded
    is Known(
      TransportStdio({ command: "/usr/bin/fs-mcp", args: Some([_, _]), .. })
    ),
  )
  let bare = model_test_round_trip(
    "{\"type\":\"stdio\",\"name\":\"fs\",\"command\":\"/usr/bin/fs-mcp\"}",
    value => experimental_v2_decode_mcp_server(value),
    experimental_v2_encode_mcp_server,
  )
  assert_true(bare is Known(TransportStdio({ args: None, env: None, .. })))
}

///|
test "v2 mcp stdio server requires an absolute command" {
  try
    experimental_v2_decode_mcp_server(
      experimental_v2_parse_json(
        "{\"type\":\"stdio\",\"name\":\"n\",\"command\":\"bin/tool\"}",
      ),
    )
  catch {
    InvalidPath(path="mcpServer.command", value="bin/tool") => ()
    _ => fail("expected InvalidPath for a relative command")
  } noraise {
    _ => fail("expected InvalidPath for a relative command")
  }
}

///|
test "v2 mcp http server round-trips headers" {
  let decoded = model_test_round_trip(
    "{\"type\":\"http\",\"name\":\"db\",\"url\":\"https://example.test/mcp\",\"headers\":[{\"name\":\"Authorization\",\"value\":\"Bearer t\"}]}",
    value => experimental_v2_decode_mcp_server(value),
    experimental_v2_encode_mcp_server,
  )
  assert_true(
    decoded
    is Known(
      TransportHttp({ url: "https://example.test/mcp", headers: Some([_]), .. })
    ),
  )
}

///|
test "v2 mcp known payloads reject foreign and missing fields" {
  let decode = source => {
    experimental_v2_decode_mcp_server(experimental_v2_parse_json(source))
  }
  try
    decode(
      "{\"type\":\"stdio\",\"name\":\"n\",\"command\":\"/bin/n\",\"url\":\"u\"}",
    )
  catch {
    UnknownField(path="mcpServer.url") => ()
    _ => fail("expected UnknownField for a url on a stdio server")
  } noraise {
    _ => fail("expected UnknownField for a url on a stdio server")
  }
  try
    decode(
      "{\"type\":\"http\",\"name\":\"n\",\"headers\":[{\"name\":\"H\",\"value\":\"V\"}]}",
    )
  catch {
    MissingField(path="mcpServer.url") => ()
    _ => fail("expected MissingField for an absent url")
  } noraise {
    _ => fail("expected MissingField for an absent url")
  }
  try decode("{\"type\":\"stdio\",\"command\":\"/bin/n\"}") catch {
    MissingField(path="mcpServer.name") => ()
    _ => fail("expected MissingField for an absent name")
  } noraise {
    _ => fail("expected MissingField for an absent name")
  }
}

///|
test "v2 mcp server unknown discriminator sse stays future raw" {
  // The v2 schema has an open fallback, so the removed v1 "sse" transport is
  // not decodable as a known transport but must round-trip as Future.
  let source = "{\"type\":\"sse\",\"name\":\"n\",\"url\":\"https://x\"}"
  let decoded = experimental_v2_decode_mcp_server(
    experimental_v2_parse_json(source),
  )
  assert_true(decoded is Future(tag="sse", ..))
  assert_eq(
    experimental_v2_stringify_json(experimental_v2_encode_mcp_server(decoded)),
    source,
  )
  let extension_source = "{\"type\":\"_ipc\",\"name\":\"n\",\"fd\":3}"
  let extension = experimental_v2_decode_mcp_server(
    experimental_v2_parse_json(extension_source),
  )
  assert_true(extension is Extension(tag="_ipc", ..))
  assert_eq(
    experimental_v2_stringify_json(experimental_v2_encode_mcp_server(extension)),
    extension_source,
  )
}

///|
test "v2 mcp server rejects malformed discriminators" {
  let decode = source => {
    experimental_v2_decode_mcp_server(experimental_v2_parse_json(source))
  }
  try decode("{\"name\":\"n\"}") catch {
    MissingField(path="mcpServer.type") => ()
    _ => fail("expected MissingField for an absent discriminator")
  } noraise {
    _ => fail("expected MissingField for an absent discriminator")
  }
  try decode("{\"type\":3}") catch {
    ExpectedString(path="mcpServer.type") => ()
    _ => fail("expected ExpectedString for a non-string discriminator")
  } noraise {
    _ => fail("expected ExpectedString for a non-string discriminator")
  }
  try experimental_v2_decode_mcp_server(Json::string("stdio")) catch {
    ExpectedObject(path="mcpServer") => ()
    _ => fail("expected ExpectedObject for a non-object server")
  } noraise {
    _ => fail("expected ExpectedObject for a non-object server")
  }
}

///|
test "v2 mcp env and header entries are strict" {
  try
    experimental_v2_decode_mcp_server(
      experimental_v2_parse_json(
        "{\"type\":\"stdio\",\"name\":\"n\",\"command\":\"/bin/n\",\"env\":[{\"name\":\"K\"}]}",
      ),
    )
  catch {
    MissingField(path="mcpServer.env[0].value") => ()
    _ => fail("expected MissingField for an env value")
  } noraise {
    _ => fail("expected MissingField for an env value")
  }
  try
    experimental_v2_decode_http_header(
      experimental_v2_parse_json("{\"name\":\"H\",\"value\":\"V\",\"extra\":1}"),
    )
  catch {
    UnknownField(path="httpHeader.extra") => ()
    _ => fail("expected UnknownField for a foreign header field")
  } noraise {
    _ => fail("expected UnknownField for a foreign header field")
  }
}
