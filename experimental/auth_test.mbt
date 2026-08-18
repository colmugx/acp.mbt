///|
test "v2 auth method agent round-trips the typed payload" {
  let decoded = model_test_round_trip(
    "{\"type\":\"agent\",\"methodId\":\"local\",\"name\":\"Local\",\"description\":\"Built-in\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_auth_method(value),
    experimental_v2_encode_auth_method,
  )
  assert_true(
    decoded
    is Known(
      { method_id: "local", name: "Local", description: Some("Built-in"), .. }
    ),
  )
}

///|
test "v2 auth method rejects illegal known payloads" {
  let decode = source => {
    experimental_v2_decode_auth_method(experimental_v2_parse_json(source))
  }
  try decode("{\"type\":\"agent\",\"methodId\":\"\",\"name\":\"n\"}") catch {
    InvalidField(path="authMethod.methodId", reason="id must not be empty") =>
      ()
    _ => fail("expected InvalidField for an empty methodId")
  } noraise {
    _ => fail("expected InvalidField for an empty methodId")
  }
  try decode("{\"type\":\"agent\",\"methodId\":\"m\"}") catch {
    MissingField(path="authMethod.name") => ()
    _ => fail("expected MissingField for an absent name")
  } noraise {
    _ => fail("expected MissingField for an absent name")
  }
  try
    decode("{\"type\":\"agent\",\"methodId\":\"m\",\"name\":\"n\",\"extra\":1}")
  catch {
    UnknownField(path="authMethod.extra") => ()
    _ => fail("expected UnknownField for a foreign agent-method field")
  } noraise {
    _ => fail("expected UnknownField for a foreign agent-method field")
  }
  try decode("{\"methodId\":\"m\",\"name\":\"n\"}") catch {
    MissingField(path="authMethod.type") => ()
    _ => fail("expected MissingField for an absent discriminator")
  } noraise {
    _ => fail("expected MissingField for an absent discriminator")
  }
}

///|
test "v2 auth method extension and future tags keep raw payloads" {
  let extension_source = "{\"type\":\"_sso\",\"methodId\":\"s\",\"name\":\"SSO\",\"cfg\":true}"
  let extension = experimental_v2_decode_auth_method(
    experimental_v2_parse_json(extension_source),
  )
  assert_true(extension is Extension(tag="_sso", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_auth_method(extension),
    ),
    extension_source,
  )
  let future_source = "{\"type\":\"oauth2\",\"anything\":[1,2,null]}"
  let future = experimental_v2_decode_auth_method(
    experimental_v2_parse_json(future_source),
  )
  assert_true(future is Future(tag="oauth2", ..))
  assert_eq(
    experimental_v2_stringify_json(experimental_v2_encode_auth_method(future)),
    future_source,
  )
}

///|
test "v2 login params round-trip and validate the method id" {
  let decoded = model_test_round_trip(
    "{\"methodId\":\"local\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_login_params(value),
    experimental_v2_encode_login_params,
  )
  assert_eq(decoded.method_id, "local")
  try
    experimental_v2_decode_login_params(
      experimental_v2_parse_json("{\"methodId\":\"\"}"),
    )
  catch {
    InvalidField(path="auth/login.methodId", reason="id must not be empty") =>
      ()
    _ => fail("expected InvalidField for an empty methodId")
  } noraise {
    _ => fail("expected InvalidField for an empty methodId")
  }
  try
    experimental_v2_decode_login_params(
      experimental_v2_parse_json("{\"methodId\":\"m\",\"extra\":1}"),
    )
  catch {
    UnknownField(path="auth/login.extra") => ()
    _ => fail("expected UnknownField for a foreign login field")
  } noraise {
    _ => fail("expected UnknownField for a foreign login field")
  }
}

///|
test "v2 auth results and logout params are strict meta-only shapes" {
  assert_true(
    model_test_round_trip(
      "{\"_meta\":{\"t\":1}}",
      value => experimental_v2_decode_login_result(value),
      experimental_v2_encode_login_result,
    ).meta
    is Some(Object(_)),
  )
  assert_true(
    experimental_v2_decode_logout_params(experimental_v2_parse_json("{}")).meta
    is None,
  )
  assert_true(
    model_test_round_trip(
      "{}",
      value => experimental_v2_decode_logout_result(value),
      experimental_v2_encode_logout_result,
    ).meta
    is None,
  )
  try
    experimental_v2_decode_logout_result(
      experimental_v2_parse_json("{\"extra\":1}"),
    )
  catch {
    UnknownField(path="auth/logout.extra") => ()
    _ => fail("expected UnknownField for a foreign logout result field")
  } noraise {
    _ => fail("expected UnknownField for a foreign logout result field")
  }
}
