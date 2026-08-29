///|
test "v2 elicitation create form round-trips the property DSL" {
  let request = model_test_round_trip(
    "{\"mode\":\"form\",\"message\":\"Configure the run\",\"requestedSchema\":{\"type\":\"object\",\"title\":\"Run config\",\"description\":\"Pick settings\",\"properties\":{\"name\":{\"type\":\"string\",\"title\":\"Name\",\"minLength\":1,\"maxLength\":64,\"pattern\":\"^[a-z]+$\",\"format\":\"email\",\"default\":\"a@b.c\"},\"framework\":{\"type\":\"string\",\"oneOf\":[{\"const\":\"jest\",\"title\":\"Jest\"},{\"const\":\"mocha\",\"title\":\"Mocha\",\"description\":\"Classic\"}]},\"ratio\":{\"type\":\"number\",\"minimum\":0.5,\"maximum\":2.5,\"default\":1.5},\"count\":{\"type\":\"integer\",\"minimum\":-9223372036854775808,\"maximum\":9223372036854775807,\"default\":42},\"verbose\":{\"type\":\"boolean\",\"title\":\"Verbose\",\"default\":true},\"tags\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":5,\"items\":{\"type\":\"string\",\"enum\":[\"fast\",\"slow\"]},\"default\":[\"fast\"]},\"stack\":{\"type\":\"array\",\"items\":{\"anyOf\":[{\"const\":\"node\",\"title\":\"Node\"}]}}},\"required\":[\"name\",\"framework\"]},\"sessionId\":\"s1\",\"toolCallId\":\"tc1\",\"_meta\":{\"r\":1}}",
    value => experimental_v2_decode_elicitation_create_request(value),
    experimental_v2_encode_elicitation_create_request,
  )
  guard request
    is Known(
      {
        message: "Configure the run",
        mode: ElicitationForm(
          {
            scope: ScopeSession(
              { session_id: "s1", tool_call_id: Some("tc1"), }
            ),
            ..
          }
        ),
        meta: Some(Object(_)),
      }
    ) else {
    fail("expected a decoded form elicitation with a session scope")
  }
  guard request
    is Known({ mode: ElicitationForm({ requested_schema, .. }), .. }) else {
    fail("expected a form mode payload")
  }
  assert_eq(requested_schema.title, Some("Run config"))
  assert_eq(requested_schema.required, Some(["name", "framework"]))
  guard requested_schema.properties.get("count")
    is Some(
      Known(PropertyInteger({ minimum: Some(minimum), default: Some(42), .. }))
    ) else {
    fail("expected an integer property with int64 bounds")
  }
  assert_eq(minimum, -9223372036854775807L - 1L)
  guard requested_schema.properties.get("tags")
    is Some(
      Known(
        PropertyMultiSelect(
          {
            items: MultiSelectItemsString({ enum_values: ["fast", "slow"], .. }),
            default: Some(["fast"]),
            ..
          }
        )
      )
    ) else {
    fail("expected a multi-select property with string items")
  }
  guard requested_schema.properties.get("stack")
    is Some(
      Known(
        PropertyMultiSelect(
          {
            items: MultiSelectItemsTitled(
              { any_of: [{ value: "node", title: "Node", .. }], .. }
            ),
            ..
          }
        )
      )
    ) else {
    fail("expected a multi-select property with titled items")
  }
  guard requested_schema.properties.get("framework")
    is Some(
      Known(
        PropertyString(
          {
            one_of: Some(
              [
                { value: "jest", title: "Jest", .. },
                {
                  value: "mocha",
                  title: "Mocha",
                  description: Some("Classic"),
                  ..
                },
              ]
            ),
            ..
          }
        )
      )
    ) else {
    fail("expected a single-select string property with titled options")
  }
  // A request scope with a numeric JSON-RPC id round-trips too.
  let request_scoped = model_test_round_trip(
    "{\"mode\":\"form\",\"message\":\"Auth\",\"requestedSchema\":{\"properties\":{}},\"requestId\":7}",
    value => experimental_v2_decode_elicitation_create_request(value),
    experimental_v2_encode_elicitation_create_request,
  )
  assert_true(
    request_scoped
    is Known(
      {
        mode: ElicitationForm(
          { scope: ScopeRequest({ request_id: RequestIdNumber(7L), }), .. }
        ),
        ..
      }
    ),
  )
}

///|
test "v2 elicitation create url round-trips" {
  let request = model_test_round_trip(
    "{\"mode\":\"url\",\"message\":\"Log in\",\"elicitationId\":\"e1\",\"url\":\"https://example.test/login\",\"sessionId\":\"s1\"}",
    value => experimental_v2_decode_elicitation_create_request(value),
    experimental_v2_encode_elicitation_create_request,
  )
  assert_true(
    request
    is Known(
      {
        message: "Log in",
        mode: ElicitationUrl(
          {
            elicitation_id: "e1",
            url: "https://example.test/login",
            scope: ScopeSession({ session_id: "s1", tool_call_id: None, }),
          }
        ),
        meta: None,
      }
    ),
  )
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"mode\":\"url\",\"elicitationId\":\"e1\",\"url\":\"https://x\",\"sessionId\":\"s1\"}",
      MissingField(path="elicitation/create.message"),
    ),
    (
      "{\"mode\":\"url\",\"message\":\"m\",\"url\":\"https://x\",\"sessionId\":\"s1\"}",
      MissingField(path="elicitation/create.elicitationId"),
    ),
    (
      "{\"mode\":\"url\",\"message\":\"m\",\"elicitationId\":\"e1\",\"sessionId\":\"s1\"}",
      MissingField(path="elicitation/create.url"),
    ),
    (
      "{\"mode\":\"form\",\"message\":\"m\",\"sessionId\":\"s1\"}",
      MissingField(path="elicitation/create.requestedSchema"),
    ),
    (
      "{\"mode\":\"form\",\"message\":\"m\",\"requestedSchema\":{},\"sessionId\":\"s1\",\"surprise\":1}",
      UnknownField(path="elicitation/create.surprise"),
    ),
    (
      "{\"mode\":\"form\",\"message\":\"m\",\"requestedSchema\":{},\"sessionId\":\"\"}",
      InvalidField(
        path="elicitation/create.sessionId",
        reason="id must not be empty",
      ),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_elicitation_create_request(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed elicitation request")
    }
  }
}

///|
test "v2 elicitation create scope disambiguation and request ids" {
  for
    source in [
      "{\"mode\":\"url\",\"message\":\"m\",\"elicitationId\":\"e1\",\"url\":\"https://x\",\"sessionId\":\"s1\",\"requestId\":\"abc\"}",
      "{\"mode\":\"url\",\"message\":\"m\",\"elicitationId\":\"e1\",\"url\":\"https://x\",\"sessionId\":\"s1\",\"requestId\":3}",
    ] {
    try
      experimental_v2_decode_elicitation_create_request(
        experimental_v2_parse_json(source),
      )
    catch {
      InvalidField(
        path="elicitation/create",
        reason="elicitation scope must carry either sessionId or requestId, not both"
      ) => ()
      _ => fail("expected InvalidField for an ambiguous elicitation scope")
    } noraise {
      _ => fail("expected InvalidField for an ambiguous elicitation scope")
    }
  }
  try
    experimental_v2_decode_elicitation_create_request(
      experimental_v2_parse_json(
        "{\"mode\":\"url\",\"message\":\"m\",\"elicitationId\":\"e1\",\"url\":\"https://x\"}",
      ),
    )
  catch {
    InvalidField(
      path="elicitation/create",
      reason="elicitation scope must carry sessionId or requestId"
    ) => ()
    _ => fail("expected InvalidField for a missing elicitation scope")
  } noraise {
    _ => fail("expected InvalidField for a missing elicitation scope")
  }
  for wire_id in ["\"abc\"", "null", "9223372036854775807"] {
    let request = model_test_round_trip(
      "{\"mode\":\"url\",\"message\":\"m\",\"elicitationId\":\"e1\",\"url\":\"https://x\",\"requestId\":\{wire_id}}",
      value => experimental_v2_decode_elicitation_create_request(value),
      experimental_v2_encode_elicitation_create_request,
    )
    assert_true(
      request
      is Known({ mode: ElicitationUrl({ scope: ScopeRequest(_), .. }), .. }),
    )
  }
  try
    experimental_v2_decode_elicitation_create_request(
      experimental_v2_parse_json(
        "{\"mode\":\"url\",\"message\":\"m\",\"elicitationId\":\"e1\",\"url\":\"https://x\",\"requestId\":1.5}",
      ),
    )
  catch {
    InvalidField(
      path="elicitation/create.requestId",
      reason="expected a signed 64-bit integer"
    ) => ()
    _ => fail("expected InvalidField for a fractional request id")
  } noraise {
    _ => fail("expected InvalidField for a fractional request id")
  }
}

///|
test "v2 elicitation property DSL rejects illegal field definitions" {
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    ("{\"type\":\"array\"}", MissingField(path="property.items")),
    (
      "{\"type\":\"string\",\"enum\":[]}",
      InvalidField(
        path="property.enum",
        reason="option lists must contain at least one entry",
      ),
    ),
    (
      "{\"type\":\"string\",\"oneOf\":[]}",
      InvalidField(
        path="property.oneOf",
        reason="option lists must contain at least one entry",
      ),
    ),
    (
      "{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[]}}",
      InvalidField(
        path="property.items.enum",
        reason="option lists must contain at least one entry",
      ),
    ),
    (
      "{\"type\":\"array\",\"items\":{\"anyOf\":[]}}",
      InvalidField(
        path="property.items.anyOf",
        reason="option lists must contain at least one entry",
      ),
    ),
    (
      "{\"type\":\"array\",\"items\":{\"unexpected\":true}}",
      InvalidField(
        path="property.items",
        reason="multi-select items must carry a typed enum list or a titled anyOf list",
      ),
    ),
    (
      "{\"type\":\"string\",\"minLength\":-1}",
      InvalidField(
        path="property.minLength",
        reason="expected a uint32 integer",
      ),
    ),
    (
      "{\"type\":\"integer\",\"minimum\":1.5}",
      InvalidField(
        path="property.minimum",
        reason="expected a signed 64-bit integer",
      ),
    ),
    ("{\"type\":\"string\",\"extra\":1}", UnknownField(path="property.extra")),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_elicitation_property(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for an illegal property definition")
    }
  }
  // minItems holds on encode too, so an illegible schema cannot be sent.
  try
    experimental_v2_encode_elicitation_property(
      Known(
        PropertyString({
          title: None,
          description: None,
          min_length: None,
          max_length: None,
          pattern: None,
          format: None,
          default: None,
          enum_values: Some([]),
          one_of: None,
          meta: None,
        }),
      ),
    )
  catch {
    InvalidField(
      path="enum",
      reason="option lists must contain at least one entry"
    ) => ()
    _ => fail("expected InvalidField for an empty enum on encode")
  } noraise {
    _ => fail("expected InvalidField for an empty enum on encode")
  }
  try
    experimental_v2_decode_elicitation_schema(
      experimental_v2_parse_json("{\"type\":\"string\"}"),
    )
  catch {
    InvalidField(
      path="requestedSchema.type",
      reason="elicitation schema type must be \"object\""
    ) => ()
    _ => fail("expected InvalidField for a non-object schema type")
  } noraise {
    _ => fail("expected InvalidField for a non-object schema type")
  }
  try
    experimental_v2_decode_elicitation_schema(
      experimental_v2_parse_json("{\"properties\":null}"),
    )
  catch {
    ExpectedObject(path="requestedSchema.properties") => ()
    _ => fail("expected ExpectedObject for a null properties map")
  } noraise {
    _ => fail("expected ExpectedObject for a null properties map")
  }
}

///|
test "v2 elicitation keeps unknown property and item kinds raw" {
  for
    source in [
      "{\"type\":\"_matrix\",\"rows\":3}", "{\"type\":\"signature\",\"bytes\":\"AA==\"}",
    ] {
    let property = model_test_round_trip(
      source,
      value => experimental_v2_decode_elicitation_property(value),
      experimental_v2_encode_elicitation_property,
    )
    assert_eq(
      experimental_v2_encode_elicitation_property(property),
      experimental_v2_parse_json(source),
    )
  }
  for
    source in [
      "{\"type\":\"_table\",\"cells\":[]}", "{\"type\":\"tree\",\"leaves\":[]}",
    ] {
    let items = model_test_round_trip(
      source,
      value => experimental_v2_decode_multi_select_items(value),
      experimental_v2_encode_multi_select_items,
    )
    assert_eq(
      experimental_v2_encode_multi_select_items(items),
      experimental_v2_parse_json(source),
    )
  }
  // Unknown string formats are annotations, never failures.
  let formatted = model_test_round_trip(
    "{\"type\":\"string\",\"format\":\"phone\"}",
    value => experimental_v2_decode_elicitation_property(value),
    experimental_v2_encode_elicitation_property,
  )
  assert_true(
    formatted
    is Known(PropertyString({ format: Some(FormatOther("phone")), .. })),
  )
  // Titled items carry no type discriminator at all.
  let titled = model_test_round_trip(
    "{\"anyOf\":[{\"const\":\"a\",\"title\":\"A\"}]}",
    value => experimental_v2_decode_multi_select_items(value),
    experimental_v2_encode_multi_select_items,
  )
  assert_true(titled is MultiSelectItemsTitled(_))
}

///|
test "v2 elicitation create response action shapes" {
  let accepted = model_test_round_trip(
    "{\"action\":\"accept\",\"content\":{\"name\":\"Ada\",\"count\":42,\"big\":9223372036854775807,\"ratio\":2.5,\"flag\":true,\"tags\":[\"a\",\"b\"]},\"_meta\":{\"a\":1}}",
    value => experimental_v2_decode_elicitation_create_response(value),
    experimental_v2_encode_elicitation_create_response,
  )
  guard accepted
    is Known(
      {
        action: ActionAccept({ content: Some(content), }),
        meta: Some(Object(_)),
      }
    ) else {
    fail("expected an accept action with content")
  }
  assert_eq(content.get("name"), Some(ContentString("Ada")))
  assert_eq(content.get("count"), Some(ContentInteger(42L)))
  assert_eq(content.get("big"), Some(ContentInteger(9223372036854775807L)))
  assert_eq(content.get("ratio"), Some(ContentNumber(2.5)))
  assert_eq(content.get("flag"), Some(ContentBoolean(true)))
  assert_eq(content.get("tags"), Some(ContentStringArray(["a", "b"])))
  let bare_accept = model_test_round_trip(
    "{\"action\":\"accept\"}",
    value => experimental_v2_decode_elicitation_create_response(value),
    experimental_v2_encode_elicitation_create_response,
  )
  assert_true(
    bare_accept is Known({ action: ActionAccept({ content: None, }), .. }),
  )
  for action in ["decline", "cancel"] {
    let response = model_test_round_trip(
      "{\"action\":\"\{action}\"}",
      value => experimental_v2_decode_elicitation_create_response(value),
      experimental_v2_encode_elicitation_create_response,
    )
    assert_true(
      response is Known({ action: ActionDecline | ActionCancel, meta: None, }),
    )
  }
  // Unknown actions keep their raw result object.
  for
    source in [
      "{\"action\":\"_deferred\",\"until\":\"later\"}", "{\"action\":\"escalated\",\"to\":\"human\"}",
    ] {
    let response = model_test_round_trip(
      source,
      value => experimental_v2_decode_elicitation_create_response(value),
      experimental_v2_encode_elicitation_create_response,
    )
    assert_eq(
      experimental_v2_encode_elicitation_create_response(response),
      experimental_v2_parse_json(source),
    )
  }
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"action\":\"accept\",\"content\":{\"nested\":{\"x\":1}}}",
      InvalidField(
        path="elicitation/create.content.nested",
        reason="elicitation content values must be strings, numbers, booleans, or string arrays",
      ),
    ),
    (
      "{\"action\":\"accept\",\"content\":[]}",
      ExpectedObject(path="elicitation/create.content"),
    ),
    ("{}", MissingField(path="elicitation/create.action")),
    (
      "{\"action\":\"decline\",\"extra\":1}",
      UnknownField(path="elicitation/create.extra"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_elicitation_create_response(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed elicitation response")
    }
  }
}

///|
test "v2 elicitation complete notification round-trips" {
  let notification = model_test_round_trip(
    "{\"elicitationId\":\"e1\",\"_meta\":{\"c\":1}}",
    value => experimental_v2_decode_complete_elicitation_notification(value),
    experimental_v2_encode_complete_elicitation_notification,
  )
  assert_true(notification is { elicitation_id: "e1", meta: Some(Object(_)), })
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    ("{}", MissingField(path="elicitation/complete.elicitationId")),
    (
      "{\"elicitationId\":\"\"}",
      InvalidField(
        path="elicitation/complete.elicitationId",
        reason="id must not be empty",
      ),
    ),
    (
      "{\"elicitationId\":\"e1\",\"extra\":true}",
      UnknownField(path="elicitation/complete.extra"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_complete_elicitation_notification(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ =>
        fail("expected a typed failure for a malformed complete notification")
    }
  }
}

///|
test "v2 elicitation create keeps unknown modes raw" {
  for
    source in [
      "{\"mode\":\"_oauth\",\"message\":\"Connect\",\"sessionId\":\"s1\",\"challenge\":\"xyz\"}",
      "{\"mode\":\"qr\",\"message\":\"Scan\",\"requestId\":9,\"matrix\":[[1,0]]}",
    ] {
    let request = model_test_round_trip(
      source,
      value => experimental_v2_decode_elicitation_create_request(value),
      experimental_v2_encode_elicitation_create_request,
    )
    assert_eq(
      experimental_v2_encode_elicitation_create_request(request),
      experimental_v2_parse_json(source),
    )
  }
  let extension = experimental_v2_decode_elicitation_create_request(
    experimental_v2_parse_json(
      "{\"mode\":\"_oauth\",\"message\":\"Connect\",\"sessionId\":\"s1\"}",
    ),
  )
  assert_true(extension is Extension(tag="_oauth", ..))
  let future = experimental_v2_decode_elicitation_create_request(
    experimental_v2_parse_json(
      "{\"mode\":\"qr\",\"message\":\"Scan\",\"requestId\":9}",
    ),
  )
  assert_true(future is Future(tag="qr", ..))
}
