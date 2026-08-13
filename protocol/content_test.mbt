///|
fn omitted_annotations() -> ProtocolNullable[Annotations] {
  Omitted
}

///|
fn omitted_json() -> ProtocolNullable[Json] {
  Omitted
}

///|
test "all five content block variants round trip" {
  let text : ContentBlock = Text({
    annotations: omitted_annotations(),
    text: "hello",
    meta: omitted_json(),
  })
  let image : ContentBlock = Image({
    annotations: omitted_annotations(),
    data: "aGVsbG8=",
    mime_type: "image/png",
    uri: Value("https://example.test/image.png"),
    meta: omitted_json(),
  })
  let audio : ContentBlock = Audio({
    annotations: omitted_annotations(),
    data: "aGVsbG8=",
    mime_type: "audio/wav",
    meta: omitted_json(),
  })
  let link : ContentBlock = ResourceLink({
    annotations: omitted_annotations(),
    description: Value("a document"),
    mime_type: Value("text/plain"),
    name: "readme",
    size: Value(7L),
    title: Value("README"),
    uri: "file:///tmp/readme",
    meta: omitted_json(),
  })
  let resource : ContentBlock = Resource({
    annotations: omitted_annotations(),
    resource: Text({
      mime_type: Value("text/plain"),
      text: "embedded",
      uri: "file:///tmp/embedded",
      meta: omitted_json(),
    }),
    meta: omitted_json(),
  })
  let blocks : Array[ContentBlock] = [text, image, audio, link, resource]
  for block in blocks {
    let encoded = content_block_to_json(block)
    assert_eq(content_block_from_json(encoded), block)
  }
}

///|
test "content wrappers preserve omitted and explicit null fields" {
  let block : ContentBlock = Text({
    annotations: Null,
    text: "nullable",
    meta: Null,
  })
  let chunk : ContentChunk = { content: block, message_id: Null, meta: Null }
  let decoded_block = content_block_from_json(content_block_to_json(block))
  let decoded_chunk = content_chunk_from_json(content_chunk_to_json(chunk))
  assert_eq(decoded_block, block)
  assert_eq(decoded_chunk, chunk)
  let wrapper : Content = { content: block, meta: Null }
  assert_eq(content_from_json(content_to_json(wrapper)), wrapper)
}

///|
test "annotations round trip roles priority and metadata" {
  let annotations : Annotations = {
    audience: Value([User, Assistant]),
    last_modified: Value("2026-08-11T00:00:00Z"),
    priority: Value(0.75),
    meta: Value({ "trace": Json::string("kept") }),
  }
  assert_eq(
    annotations_from_json(annotations_to_json(annotations)),
    annotations,
  )
}

///|
test "content codecs reject malformed discriminators and fields" {
  try
    content_block_from_json(protocol_parse_json("{\"type\":\"video\"}"))
  catch {
    InvalidDiscriminator(path="content.type", value="video") => ()
    _ => fail("expected unknown content discriminator")
  } noraise {
    _ => fail("expected content decoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json("{\"type\":\"text\",\"text\":3}"),
    )
  catch {
    ExpectedString(path="content.text") => ()
    _ => fail("expected text type error")
  } noraise {
    _ => fail("expected text decoding to fail")
  }
  try
    content_block_from_json(protocol_parse_json("{\"type\":\"text\"}"))
  catch {
    MissingField(path="content.text") => ()
    _ => fail("expected missing text error")
  } noraise {
    _ => fail("expected text decoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json("{\"type\":\"text\",\"text\":\"ok\",\"extra\":true}"),
    )
  catch {
    UnknownField(path="content.extra") => ()
    _ => fail("expected unknown field error")
  } noraise {
    _ => fail("expected text decoding to fail")
  }
}

///|
test "media and blob payloads validate base64 without fallback" {
  let bad_image : ContentBlock = Image({
    annotations: omitted_annotations(),
    data: "%%%",
    mime_type: "image/png",
    uri: Omitted,
    meta: omitted_json(),
  })
  try content_block_to_json(bad_image) catch {
    InvalidBase64(path="data") => ()
    _ => fail("expected image base64 validation")
  } noraise {
    _ => fail("expected image encoding to fail")
  }
  try
    content_block_from_json(
      protocol_parse_json(
        "{\"type\":\"audio\",\"data\":\"%%%\",\"mimeType\":\"audio/wav\"}",
      ),
    )
  catch {
    InvalidBase64(path="content.data") => ()
    _ => fail("expected audio base64 validation")
  } noraise {
    _ => fail("expected audio decoding to fail")
  }
  try
    embedded_resource_resource_from_json(
      protocol_parse_json(
        "{\"text\":\"text\",\"blob\":\"aA==\",\"uri\":\"file:///x\"}",
      ),
    )
  catch {
    InvalidField(path="resource", reason=_) => ()
    _ => fail("expected ambiguous resource payload")
  } noraise {
    _ => fail("expected resource decoding to fail")
  }
}

///|
test "embedded blob resources validate payload shape and base64" {
  let blob : BlobResourceContents = {
    blob: "aGVsbG8=",
    mime_type: Value("application/octet-stream"),
    uri: "file:///tmp/blob",
    meta: omitted_json(),
  }
  assert_eq(
    blob_resource_contents_from_json(blob_resource_contents_to_json(blob)),
    blob,
  )

  try
    blob_resource_contents_from_json(
      protocol_parse_json("{\"blob\":\"%%%\",\"uri\":\"file:///x\"}"),
    )
  catch {
    InvalidBase64(path="resource.blob") => ()
    _ => fail("expected direct blob base64 validation")
  } noraise {
    _ => fail("expected direct blob decoding to fail")
  }

  let bad_blob : BlobResourceContents = {
    blob: "%%%",
    mime_type: Omitted,
    uri: "file:///x",
    meta: omitted_json(),
  }
  try blob_resource_contents_to_json(bad_blob) catch {
    InvalidBase64(path="blob") => ()
    _ => fail("expected blob encoding base64 validation")
  } noraise {
    _ => fail("expected blob encoding to fail")
  }

  try
    content_block_from_json(
      protocol_parse_json(
        "{\"type\":\"resource\",\"resource\":{\"blob\":\"%%%\",\"uri\":\"file:///x\"}}",
      ),
    )
  catch {
    InvalidBase64(path="content.resource.blob") => ()
    _ => fail("expected nested blob base64 validation")
  } noraise {
    _ => fail("expected nested blob decoding to fail")
  }

  try
    blob_resource_contents_from_json(protocol_parse_json("{\"blob\":\"aA==\"}"))
  catch {
    MissingField(path="resource.uri") => ()
    _ => fail("expected blob uri requirement")
  } noraise {
    _ => fail("expected blob without uri to fail")
  }

  try
    embedded_resource_resource_from_json(
      protocol_parse_json("{\"uri\":\"file:///x\"}"),
    )
  catch {
    InvalidField(
      path="resource",
      reason="resource payload must contain text or blob"
    ) => ()
    _ => fail("expected embedded resource payload requirement")
  } noraise {
    _ => fail("expected embedded resource without payload to fail")
  }
}
