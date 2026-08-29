///|
test "v2 initialize params round-trip with every optional field" {
  let decoded = model_test_round_trip(
    "{\"protocolVersion\":2,\"info\":{\"name\":\"client\",\"title\":\"Demo\",\"version\":\"1.0\",\"_meta\":{\"k\":1}},\"capabilities\":{\"elicitation\":{\"form\":{},\"url\":{}}},\"_meta\":{\"t\":2}}",
    value => experimental_v2_decode_initialize_params(value),
    experimental_v2_encode_initialize_params,
  )
  assert_eq(decoded.protocol_version, 2)
  assert_eq(decoded.info.title, Some("Demo"))
  assert_true(decoded.info.meta is Some(Object(_)))
  assert_true(decoded.capabilities.elicitation is MarkerSupported(_))
}

///|
test "v2 initialize params default omitted capabilities to the empty object" {
  let decoded = experimental_v2_decode_initialize_params(
    experimental_v2_parse_json(
      "{\"protocolVersion\":2,\"info\":{\"name\":\"c\",\"version\":\"0\"}}",
    ),
  )
  assert_true(
    decoded.capabilities is { elicitation: MarkerUnsupported, meta: None, },
  )
  let encoded = experimental_v2_require_object(
    experimental_v2_encode_initialize_params(decoded),
    path="encoded",
  )
  assert_true(encoded.get("capabilities") is Some(Object(_)))
}

///|
test "v2 initialize params reject null capabilities and unknown fields" {
  try
    experimental_v2_decode_initialize_params(
      experimental_v2_parse_json(
        "{\"protocolVersion\":2,\"info\":{\"name\":\"c\",\"version\":\"0\"},\"capabilities\":null}",
      ),
    )
  catch {
    ExpectedObject(path="initialize.capabilities") => ()
    _ => fail("expected ExpectedObject for null capabilities")
  } noraise {
    _ => fail("expected ExpectedObject for null capabilities")
  }
  try
    experimental_v2_decode_initialize_params(
      experimental_v2_parse_json(
        "{\"protocolVersion\":2,\"info\":{\"name\":\"c\",\"version\":\"0\"},\"clientInfo\":{}}",
      ),
    )
  catch {
    UnknownField(path="initialize.clientInfo") => ()
    _ => fail("expected UnknownField for the v1-style clientInfo key")
  } noraise {
    _ => fail("expected UnknownField for the v1-style clientInfo key")
  }
}

///|
test "v2 initialize params pin protocolVersion to uint16" {
  let decode_version = source => {
    experimental_v2_decode_initialize_params(experimental_v2_parse_json(source))
  }
  let base = "{\"protocolVersion\":REPLACE,\"info\":{\"name\":\"c\",\"version\":\"0\"}}"
  try decode_version(base.replace(old="REPLACE", new="65536")) catch {
    InvalidField(path="initialize.protocolVersion", reason=_) => ()
    _ => fail("expected InvalidField for a version above uint16")
  } noraise {
    _ => fail("expected InvalidField for a version above uint16")
  }
  try decode_version(base.replace(old="REPLACE", new="-1")) catch {
    InvalidField(path="initialize.protocolVersion", reason=_) => ()
    _ => fail("expected InvalidField for a negative version")
  } noraise {
    _ => fail("expected InvalidField for a negative version")
  }
  try decode_version(base.replace(old="REPLACE", new="1.5")) catch {
    InvalidField(path="initialize.protocolVersion", reason=_) => ()
    _ => fail("expected InvalidField for a fractional version")
  } noraise {
    _ => fail("expected InvalidField for a fractional version")
  }
  try decode_version(base.replace(old="REPLACE", new="\"2\"")) catch {
    ExpectedNumber(path="initialize.protocolVersion") => ()
    _ => fail("expected ExpectedNumber for a string version")
  } noraise {
    _ => fail("expected ExpectedNumber for a string version")
  }
  try decode_version("{\"info\":{\"name\":\"c\",\"version\":\"0\"}}") catch {
    MissingField(path="initialize.protocolVersion") => ()
    _ => fail("expected MissingField for an absent version")
  } noraise {
    _ => fail("expected MissingField for an absent version")
  }
  assert_eq(
    decode_version(base.replace(old="REPLACE", new="65535")).protocol_version,
    65535,
  )
  assert_eq(
    decode_version(base.replace(old="REPLACE", new="0")).protocol_version,
    0,
  )
}

///|
test "v2 initialize params require a present info object" {
  try
    experimental_v2_decode_initialize_params(
      experimental_v2_parse_json("{\"protocolVersion\":2}"),
    )
  catch {
    MissingField(path="initialize.info") => ()
    _ => fail("expected MissingField for an absent info")
  } noraise {
    _ => fail("expected MissingField for an absent info")
  }
  try
    experimental_v2_decode_initialize_params(
      experimental_v2_parse_json("{\"protocolVersion\":2,\"info\":null}"),
    )
  catch {
    ExpectedObject(path="initialize.info") => ()
    _ => fail("expected ExpectedObject for a null info")
  } noraise {
    _ => fail("expected ExpectedObject for a null info")
  }
}

///|
test "v2 implementation round-trips optional title and meta" {
  let decoded = model_test_round_trip(
    "{\"name\":\"agent\",\"title\":null,\"version\":\"1.2\",\"_meta\":{\"os\":\"darwin\"}}",
    value => experimental_v2_decode_implementation(value),
    experimental_v2_encode_implementation,
  )
  assert_true(decoded.title is None)
  assert_true(
    experimental_v2_decode_implementation(
      experimental_v2_parse_json("{\"name\":\"a\",\"version\":\"1\"}"),
    ).title
    is None,
  )
  try
    experimental_v2_decode_implementation(
      experimental_v2_parse_json("{\"name\":\"a\",\"version\":1}"),
    )
  catch {
    ExpectedString(path="info.version") => ()
    _ => fail("expected ExpectedString for a non-string version")
  } noraise {
    _ => fail("expected ExpectedString for a non-string version")
  }
}

///|
test "v2 initialize result round-trips auth methods both known and open" {
  let decoded = model_test_round_trip(
    "{\"protocolVersion\":2,\"info\":{\"name\":\"a\",\"version\":\"1\"},\"capabilities\":{\"session\":{}},\"authMethods\":[{\"type\":\"agent\",\"methodId\":\"local\",\"name\":\"Local\",\"description\":null},{\"type\":\"_sso\",\"methodId\":\"s\",\"name\":\"SSO\",\"cfg\":true}]}",
    value => experimental_v2_decode_initialize_result(value),
    experimental_v2_encode_initialize_result,
  )
  guard decoded.auth_methods is Some([first, second]) else {
    fail("expected two decoded auth methods")
  }
  assert_true(
    first is Known({ method_id: "local", name: "Local", description: None, .. }),
  )
  assert_true(second is Extension(tag="_sso", ..))
  let bare = model_test_round_trip(
    "{\"protocolVersion\":2,\"info\":{\"name\":\"a\",\"version\":\"1\"}}",
    value => experimental_v2_decode_initialize_result(value),
    experimental_v2_encode_initialize_result,
  )
  assert_true(bare.auth_methods is None)
  assert_true(
    bare.capabilities
    is { session: MarkerUnsupported, auth: MarkerUnsupported, meta: None, },
  )
}
