///|
test "v2 text audio and image content round-trip with annotations" {
  let text = model_test_round_trip(
    "{\"type\":\"text\",\"text\":\"hello\",\"annotations\":{\"audience\":[\"user\",\"assistant\"],\"lastModified\":\"2025-01-12T15:00:58Z\",\"priority\":0.5,\"_meta\":{\"k\":1}},\"_meta\":{\"m\":2}}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  assert_true(text is Known(BlockText(_)))
  let audio = model_test_round_trip(
    "{\"type\":\"audio\",\"data\":\"aGVsbG8=\",\"mimeType\":\"audio/wav\"}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  assert_true(audio is Known(BlockAudio(_)))
  let image = model_test_round_trip(
    "{\"type\":\"image\",\"data\":\"AA==\",\"mimeType\":\"image/png\",\"uri\":\"https://example.test/a.png\",\"annotations\":{\"priority\":0}}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  guard image is Known(BlockImage(payload)) else {
    fail("expected a known image block")
  }
  assert_eq(payload.uri, Some("https://example.test/a.png"))
  assert_true(payload.annotations is Some({ priority: Some(0.0), .. }))
}

///|
test "v2 annotations priority boundaries 0 and 1 accepted out of range rejected" {
  for priority in [0.0, 1.0] {
    let decoded = experimental_v2_decode_content_block(
      experimental_v2_parse_json(
        "{\"type\":\"text\",\"text\":\"t\",\"annotations\":{\"priority\":\{priority}}}",
      ),
    )
    assert_true(
      decoded
      is Known(BlockText({ annotations: Some({ priority: Some(_), .. }), .. })),
    )
  }
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"type\":\"text\",\"text\":\"t\",\"annotations\":{\"priority\":1.5}}",
      InvalidField(
        path="content.annotations.priority",
        reason="priority must be within 0 and 1",
      ),
    ),
    (
      "{\"type\":\"text\",\"text\":\"t\",\"annotations\":{\"priority\":-0.1}}",
      InvalidField(
        path="content.annotations.priority",
        reason="priority must be within 0 and 1",
      ),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_content_block(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected InvalidField for an out-of-range priority")
    }
  }
  try
    experimental_v2_encode_annotations({
      audience: None,
      last_modified: None,
      priority: Some(2.0),
      meta: None,
    })
  catch {
    InvalidField(path="priority", reason="priority must be within 0 and 1") =>
      ()
    _ => fail("expected InvalidField for an out-of-range priority on encode")
  } noraise {
    _ => fail("expected InvalidField for an out-of-range priority on encode")
  }
}

///|
test "v2 content base64 payloads reject invalid input with path" {
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"type\":\"image\",\"data\":\"not base64!\",\"mimeType\":\"image/png\"}",
      InvalidBase64(path="content.data"),
    ),
    (
      "{\"type\":\"audio\",\"data\":\"a\",\"mimeType\":\"audio/wav\"}",
      InvalidBase64(path="content.data"),
    ),
    (
      "{\"type\":\"resource\",\"resource\":{\"blob\":\"====\",\"uri\":\"file:///x\"}}",
      InvalidBase64(path="content.resource.blob"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_content_block(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected InvalidBase64 for a malformed payload")
    }
  }
  try
    experimental_v2_encode_image_content({
      data: ">>>",
      mime_type: "image/png",
      uri: None,
      annotations: None,
      meta: None,
    })
  catch {
    InvalidBase64(path="data") => ()
    _ => fail("expected InvalidBase64 for malformed data on encode")
  } noraise {
    _ => fail("expected InvalidBase64 for malformed data on encode")
  }
}

///|
test "v2 resource link round-trips icons and open audience roles" {
  let decoded = model_test_round_trip(
    "{\"type\":\"resource_link\",\"name\":\"doc\",\"uri\":\"file:///doc\",\"title\":\"Doc\",\"description\":\"read me\",\"icons\":[{\"src\":\"https://example.test/i.svg\",\"mimeType\":\"image/svg+xml\",\"sizes\":[\"any\"],\"theme\":\"dark\"},{\"src\":\"https://example.test/i.png\",\"sizes\":[\"48x48\",\"96x96\"]},{\"src\":\"https://example.test/i-l.png\",\"theme\":\"light\"},{\"src\":\"https://example.test/i-x.png\",\"theme\":\"_high\"},{\"src\":\"https://example.test/i-f.png\",\"theme\":\"weird\"}],\"mimeType\":\"text/plain\",\"size\":123,\"annotations\":{\"audience\":[\"user\",\"_role\",\"sys\"]}}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  guard decoded is Known(BlockResourceLink(link)) else {
    fail("expected a known resource link block")
  }
  assert_eq(link.size, Some(123L))
  guard link.icons is Some([first, second, ..]) else {
    fail("expected decoded icons")
  }
  assert_true(first.theme is Some(IconThemeDark))
  assert_eq(first.sizes, Some(["any"]))
  assert_true(second.theme is None)
  assert_true(
    link.annotations
    is Some(
      {
        audience: Some(
          [RoleUser, RoleExtension(tag="_role"), RoleFuture(raw="sys")]
        ),
        ..,
      }
    ),
  )
}

///|
test "v2 resource link icon requires src and rejects unknown fields" {
  try
    experimental_v2_decode_content_block(
      experimental_v2_parse_json(
        "{\"type\":\"resource_link\",\"name\":\"n\",\"uri\":\"file:///n\",\"icons\":[{\"sizes\":[\"48x48\"]}]}",
      ),
    )
  catch {
    MissingField(path="content.icons[0].src") => ()
    _ => fail("expected MissingField for an icon without src")
  } noraise {
    _ => fail("expected MissingField for an icon without src")
  }
  try
    experimental_v2_decode_content_block(
      experimental_v2_parse_json(
        "{\"type\":\"resource_link\",\"name\":\"n\",\"uri\":\"file:///n\",\"icons\":[{\"src\":\"https://i\",\"fallback\":\"x\"}]}",
      ),
    )
  catch {
    UnknownField(path="content.icons[0].fallback") => ()
    _ => fail("expected UnknownField for an unexpected icon field")
  } noraise {
    _ => fail("expected UnknownField for an unexpected icon field")
  }
}

///|
test "v2 resource link int64 size keeps precision beyond binary double range" {
  let decoded = model_test_round_trip(
    "{\"type\":\"resource_link\",\"name\":\"big\",\"uri\":\"file:///big\",\"size\":9007199254740993}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  guard decoded is Known(BlockResourceLink(link)) else {
    fail("expected a known resource link block")
  }
  assert_eq(link.size, Some(9007199254740993L))
}

///|
test "v2 embedded resource dispatches text and blob payloads" {
  let text = model_test_round_trip(
    "{\"type\":\"resource\",\"resource\":{\"text\":\"body\",\"uri\":\"file:///a\",\"mimeType\":\"text/plain\"}}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  assert_true(text is Known(BlockResource({ resource: ResourceText(_), .. })))
  let blob = model_test_round_trip(
    "{\"type\":\"resource\",\"resource\":{\"blob\":\"aGVsbG8=\",\"uri\":\"file:///b\"}}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  assert_true(blob is Known(BlockResource({ resource: ResourceBlob(_), .. })))
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"text\":\"a\",\"blob\":\"b\",\"uri\":\"file:///x\"}",
      InvalidField(
        path="resource",
        reason="resource payload cannot contain both text and blob",
      ),
    ),
    (
      "{\"uri\":\"file:///x\"}",
      InvalidField(
        path="resource",
        reason="resource payload must contain text or blob",
      ),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_embedded_resource_resource(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected InvalidField for an ambiguous resource payload")
    }
  }
}

///|
test "v2 content block open fallback preserves extension and future tags" {
  let extension = model_test_round_trip(
    "{\"type\":\"_custom\",\"payload\":7}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  assert_true(extension is Extension(tag="_custom", ..))
  let future = model_test_round_trip(
    "{\"type\":\"hologram\",\"rows\":[]}",
    value => experimental_v2_decode_content_block(value),
    experimental_v2_encode_content_block,
  )
  assert_true(future is Future(tag="hologram", ..))
  try
    experimental_v2_decode_content_block(
      experimental_v2_parse_json("{\"text\":\"no tag\"}"),
    )
  catch {
    MissingField(path="content.type") => ()
    _ => fail("expected MissingField for a content block without type")
  } noraise {
    _ => fail("expected MissingField for a content block without type")
  }
}

///|
test "v2 content wrapper and chunk round-trip and validate ids" {
  let wrapper = model_test_round_trip(
    "{\"content\":{\"type\":\"text\",\"text\":\"wrapped\"},\"_meta\":{\"w\":1}}",
    value => experimental_v2_decode_content(value),
    experimental_v2_encode_content,
  )
  assert_true(wrapper.content is Known(BlockText(_)))
  let chunk = model_test_round_trip(
    "{\"messageId\":\"m1\",\"content\":{\"type\":\"text\",\"text\":\"part\"}}",
    value => experimental_v2_decode_content_chunk(value),
    experimental_v2_encode_content_chunk,
  )
  assert_eq(chunk.message_id, "m1")
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"content\":{\"type\":\"text\",\"text\":\"t\"}}",
      MissingField(path="contentChunk.messageId"),
    ),
    (
      "{\"messageId\":\"\",\"content\":{\"type\":\"text\",\"text\":\"t\"}}",
      InvalidField(path="contentChunk.messageId", reason="id must not be empty"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_content_chunk(experimental_v2_parse_json(source))
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed content chunk")
    }
  }
}
