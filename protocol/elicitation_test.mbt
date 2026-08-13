///|
fn elicitation_test_meta() -> ProtocolNullable[Json] {
  Value({ "source": Json::string("test") })
}

///|
fn elicitation_test_schema() -> Json raise ProtocolDecodeError {
  protocol_parse_json(
    "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"title\":\"Name\",\"minLength\":1},\"count\":{\"type\":\"integer\",\"minimum\":-2,\"maximum\":5}},\"required\":[\"name\"]}",
  )
}

///|
fn elicitation_test_form_with_schema(schema : Json) -> Json {
  Json::object({
    "mode": Json::string("form"),
    "message": Json::string("m"),
    "requestId": Json::string("r"),
    "requestedSchema": schema,
  })
}

///|
fn elicitation_test_array_schema_with_min_items(min_items : Json) -> Json {
  Json::object({
    "type": Json::string("object"),
    "properties": Json::object({
      "items": Json::object({
        "type": Json::string("array"),
        "minItems": min_items,
        "items": Json::object({ "type": Json::string("string") }),
      }),
    }),
  })
}

///|
test "elicitation form and URL unions preserve scope and schema" {
  let form : ElicitationCreateParams = Form({
    scope: Request(String("request-1")),
    message: "Provide details",
    requested_schema: elicitation_test_schema(),
    meta: elicitation_test_meta(),
  })
  let decoded_form = elicitation_create_params_from_json(
    elicitation_create_params_to_json(form),
  ) catch {
    InvalidField(path~, reason~) => fail(path + ":" + reason)
    _ => fail("unexpected protocol decode error")
  }
  assert_eq(decoded_form, form)

  let url : ElicitationCreateParams = Url({
    scope: Session(session_id="session-1", tool_call_id=Value("tool-1")),
    elicitation_id: "elicitation-1",
    message: "Open the approval page",
    url: "https://example.test/approve/1",
    meta: Null,
  })
  assert_eq(
    elicitation_create_params_from_json(elicitation_create_params_to_json(url)),
    url,
  )

  let session_without_tool : ElicitationCreateParams = Form({
    scope: Session(session_id="session-1", tool_call_id=Omitted),
    message: "Provide details",
    requested_schema: elicitation_test_schema(),
    meta: Omitted,
  })
  assert_eq(
    elicitation_create_params_from_json(
      elicitation_create_params_to_json(session_without_tool),
    ),
    session_without_tool,
  )
}

///|
test "elicitation actions and complete notification round trip" {
  let actions : Array[ElicitationAction] = [Accept, Decline, Cancel]
  for action in actions {
    let result : ElicitationCreateResult = {
      action,
      meta: elicitation_test_meta(),
    }
    assert_eq(
      elicitation_create_result_from_json(
        elicitation_create_result_to_json(result),
      ),
      result,
    )
  }

  let complete : ElicitationCompleteParams = {
    elicitation_id: "elicitation-1",
    meta: Null,
  }
  assert_eq(
    elicitation_complete_params_from_json(
      elicitation_complete_params_to_json(complete),
    ),
    complete,
  )
}

///|
test "elicitation validation rejects unknown modes scopes and schema fields" {
  try
    elicitation_create_params_from_json(
      protocol_parse_json(
        "{\"mode\":\"other\",\"message\":\"m\",\"requestId\":\"r\"}",
      ),
    )
  catch {
    InvalidDiscriminator(path="elicitation/create.mode", value="other") => ()
    _ => fail("expected mode rejection")
  } noraise {
    _ => fail("expected mode rejection")
  }

  try
    elicitation_create_params_from_json(
      protocol_parse_json(
        "{\"mode\":\"form\",\"message\":\"m\",\"requestId\":\"r\",\"sessionId\":\"s\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{}}}",
      ),
    )
  catch {
    InvalidField(path="elicitation/create", reason=_) => ()
    _ => fail("expected mutually exclusive scope rejection")
  } noraise {
    _ => fail("expected mutually exclusive scope rejection")
  }

  try
    elicitation_create_params_from_json(
      protocol_parse_json(
        "{\"mode\":\"form\",\"message\":\"m\",\"requestId\":\"r\",\"requestedSchema\":{\"type\":\"object\",\"properties\":{},\"extra\":true}}",
      ),
    )
  catch {
    UnknownField(path="elicitation/create.requestedSchema.extra") => ()
    _ => fail("expected schema unknown field rejection")
  } noraise {
    _ => fail("expected schema unknown field rejection")
  }

  try
    elicitation_create_result_from_json(
      protocol_parse_json("{\"action\":\"maybe\"}"),
    )
  catch {
    InvalidDiscriminator(path="elicitation/create.action", value="maybe") => ()
    _ => fail("expected action rejection")
  } noraise {
    _ => fail("expected action rejection")
  }

  try
    elicitation_complete_params_from_json(
      protocol_parse_json("{\"elicitationId\":\"\"}"),
    )
  catch {
    InvalidField(path="elicitation/complete.elicitationId", reason=_) => ()
    _ => fail("expected empty elicitation id rejection")
  } noraise {
    _ => fail("expected empty elicitation id rejection")
  }
}

///|
test "elicitation array integer validators preserve exact JSON numbers" {
  let large = Json::number(9007199254740993.0, repr="9007199254740993")
  let maximum = Json::number(
    18446744073709551615.0,
    repr="18446744073709551615",
  )
  for value in [large, maximum, Json::number(1000.0, repr="1e+3")] {
    let schema = elicitation_test_array_schema_with_min_items(value)
    let decoded = elicitation_create_params_from_json(
      elicitation_test_form_with_schema(schema),
    )
    match decoded {
      Form(params) => assert_eq(params.requested_schema, schema)
      Url(_) => fail("expected form elicitation")
    }
  }

  let invalid_values = [
    Json::number(9007199254740993.5, repr="9007199254740993.5"),
    Json::number(-1.0, repr="-1"),
    Json::number(18446744073709551616.0, repr="18446744073709551616"),
    Json::number(0.001, repr="1e-3"),
  ]
  for value in invalid_values {
    try
      elicitation_create_params_from_json(
        elicitation_test_form_with_schema(
          elicitation_test_array_schema_with_min_items(value),
        ),
      )
    catch {
      InvalidField(
        path="elicitation/create.requestedSchema.properties.items.minItems",
        reason=_
      ) => ()
      _ => fail("expected exact minItems rejection")
    } noraise {
      _ => fail("expected exact minItems rejection")
    }
  }

  let repr_less = elicitation_test_array_schema_with_min_items(
    Json::number(9007199254740992.0),
  )
  try
    elicitation_create_params_from_json(
      elicitation_test_form_with_schema(repr_less),
    )
  catch {
    InvalidField(
      path="elicitation/create.requestedSchema.properties.items.minItems",
      reason=_
    ) => ()
    _ => fail("expected imprecise repr-less minItems rejection")
  } noraise {
    _ => fail("expected imprecise repr-less minItems rejection")
  }
}

///|
test "elicitation signed integer validators preserve exact boundaries" {
  let schema = protocol_parse_json(
    "{\"type\":\"object\",\"properties\":{\"count\":{\"type\":\"integer\",\"minimum\":-9223372036854775808,\"maximum\":9223372036854775807}}}",
  )
  let decoded = elicitation_create_params_from_json(
    elicitation_test_form_with_schema(schema),
  )
  match decoded {
    Form(params) => assert_eq(params.requested_schema, schema)
    Url(_) => fail("expected form elicitation")
  }

  for
    value in [
      Json::number(-9223372036854775808.0, repr="-9223372036854775808.5"),
      Json::number(9223372036854775808.0, repr="9223372036854775808"),
      Json::number(-0.001, repr="-1e-3"),
    ] {
    let invalid_schema = Json::object({
      "type": Json::string("object"),
      "properties": Json::object({
        "count": Json::object({
          "type": Json::string("integer"),
          "minimum": value,
        }),
      }),
    })
    try
      elicitation_create_params_from_json(
        elicitation_test_form_with_schema(invalid_schema),
      )
    catch {
      InvalidField(
        path="elicitation/create.requestedSchema.properties.count.minimum",
        reason=_
      ) => ()
      _ => fail("expected exact integer minimum rejection")
    } noraise {
      _ => fail("expected exact integer minimum rejection")
    }
  }
}
