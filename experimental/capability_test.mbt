///|
test "v2 marker helpers collapse omitted and null to unsupported" {
  let fields = model_test_fields("{\"a\":null,\"b\":{}}")
  fn decode(
    value : Json,
    path : String,
  ) -> ExperimentalV2MarkerPayload raise ExperimentalV2DecodeError {
    experimental_v2_decode_marker_payload(value, path~)
  }
  assert_true(
    experimental_v2_decode_marker(fields, "a", path="a", decode)
    is MarkerUnsupported,
  )
  assert_true(
    experimental_v2_decode_marker(fields, "missing", path="missing", decode)
    is MarkerUnsupported,
  )
  assert_true(
    experimental_v2_decode_marker(fields, "b", path="b", decode)
    is MarkerSupported({ meta: None }),
  )
  let payload : ExperimentalV2MarkerPayload = { meta: None }
  let encoded : Map[String, Json] = Map([])
  experimental_v2_put_marker(encoded, "b", MarkerSupported(payload), payload => {
    experimental_v2_encode_marker_payload(payload)
  })
  experimental_v2_put_marker(encoded, "a", MarkerUnsupported, payload => {
    experimental_v2_encode_marker_payload(payload)
  })
  assert_true(encoded.get("a") is None)
  assert_true(encoded.get("b") is Some(Object(_)))
}

///|
test "v2 marker payload rejects unknown fields and non-object meta" {
  try
    experimental_v2_decode_marker_payload(
      experimental_v2_parse_json("{\"nope\":1}"),
    )
  catch {
    UnknownField(path="capability.nope") => ()
    _ => fail("expected UnknownField for a foreign marker payload field")
  } noraise {
    _ => fail("expected UnknownField for a foreign marker payload field")
  }
  try
    experimental_v2_decode_marker_payload(
      experimental_v2_parse_json("{\"_meta\":\"x\"}"),
    )
  catch {
    InvalidField(path="capability._meta", reason=_) => ()
    _ => fail("expected InvalidField for a non-object marker meta")
  } noraise {
    _ => fail("expected InvalidField for a non-object marker meta")
  }
}

///|
test "v2 client capabilities marker tri-case for elicitation" {
  let decode = source => {
    experimental_v2_decode_client_capabilities(
      experimental_v2_parse_json(source),
    )
  }
  assert_true(decode("{}") is { elicitation: MarkerUnsupported, meta: None })
  assert_true(
    decode("{\"elicitation\":null}") is { elicitation: MarkerUnsupported, .. },
  )
  assert_true(
    decode("{\"elicitation\":{}}")
    is {
      elicitation: MarkerSupported(
        { form: MarkerUnsupported, url: MarkerUnsupported, meta: None }
      ),
      ..,
    },
  )
  let decoded = decode(
    "{\"elicitation\":{\"form\":{},\"url\":{\"_meta\":{\"k\":1}}}}",
  )
  assert_true(
    decoded.elicitation
    is MarkerSupported(
      {
        form: MarkerSupported({ meta: None }),
        url: MarkerSupported({ meta: Some(Object(_)) }),
        ..,
      }
    ),
  )
  assert_eq(
    decoded,
    decode(
      experimental_v2_stringify_json(
        experimental_v2_encode_client_capabilities(decoded),
      ),
    ),
  )
  // An explicit wire null encodes back as an omission, not as null.
  let nulled = decode("{\"elicitation\":null}")
  let encoded = experimental_v2_require_object(
    experimental_v2_encode_client_capabilities(nulled),
    path="capabilities",
  )
  assert_true(encoded.get("elicitation") is None)
}

///|
test "v2 agent capabilities decode the full session tree" {
  let decoded = model_test_round_trip(
    "{\"session\":{\"prompt\":{\"image\":{},\"audio\":null,\"embeddedContext\":{}},\"mcp\":{\"stdio\":{},\"http\":{}},\"delete\":{},\"additionalDirectories\":{}},\"auth\":{}}",
    value => experimental_v2_decode_agent_capabilities(value),
    experimental_v2_encode_agent_capabilities,
  )
  assert_true(
    decoded.session
    is MarkerSupported(
      {
        prompt: MarkerSupported(
          {
            image: MarkerSupported(_),
            audio: MarkerUnsupported,
            embedded_context: MarkerSupported(_),
            ..,
          }
        ),
        mcp: MarkerSupported(
          { stdio: MarkerSupported(_), http: MarkerSupported(_), .. }
        ),
        delete: MarkerSupported(_),
        additional_directories: MarkerSupported(_),
        ..,
      }
    ),
  )
  assert_true(decoded.auth is MarkerSupported({ meta: None }))
}

///|
test "v2 capabilities reject v1 field names and foreign markers" {
  try
    experimental_v2_decode_client_capabilities(
      experimental_v2_parse_json("{\"fs\":{}}"),
    )
  catch {
    UnknownField(path="capabilities.fs") => ()
    _ => fail("expected UnknownField for the removed v1 fs capability")
  } noraise {
    _ => fail("expected UnknownField for the removed v1 fs capability")
  }
  try
    experimental_v2_decode_agent_capabilities(
      experimental_v2_parse_json(
        "{\"session\":{\"prompt\":{\"image\":{}},\"list\":{}}}",
      ),
    )
  catch {
    UnknownField(path="capabilities.session.list") => ()
    _ => fail("expected UnknownField for the v1-style list marker")
  } noraise {
    _ => fail("expected UnknownField for the v1-style list marker")
  }
  try
    experimental_v2_decode_client_capabilities(
      experimental_v2_parse_json("{\"elicitation\":{\"form\":1}}"),
    )
  catch {
    ExpectedObject(path="capabilities.elicitation.form") => ()
    _ => fail("expected ExpectedObject for a non-object form marker")
  } noraise {
    _ => fail("expected ExpectedObject for a non-object form marker")
  }
}
