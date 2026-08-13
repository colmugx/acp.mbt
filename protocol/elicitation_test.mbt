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
