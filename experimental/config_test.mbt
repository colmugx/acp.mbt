///|
test "v2 config category decodes known extension and future values" {
  assert_eq(
    experimental_v2_decode_config_category(Json::string("mode")),
    CategoryMode,
  )
  assert_eq(
    experimental_v2_decode_config_category(Json::string("model")),
    CategoryModel,
  )
  assert_eq(
    experimental_v2_decode_config_category(Json::string("model_config")),
    CategoryModelConfig,
  )
  assert_eq(
    experimental_v2_decode_config_category(Json::string("thought_level")),
    CategoryThoughtLevel,
  )
  assert_eq(
    experimental_v2_decode_config_category(Json::string("_custom")),
    CategoryExtension(tag="_custom"),
  )
  assert_eq(
    experimental_v2_decode_config_category(Json::string("weird")),
    CategoryFuture(raw="weird"),
  )
  let categories : Array[ExperimentalV2ConfigCategory] = [
    CategoryMode,
    CategoryModel,
    CategoryModelConfig,
    CategoryThoughtLevel,
    CategoryExtension(tag="_custom"),
    CategoryFuture(raw="weird"),
  ]
  for category in categories {
    assert_eq(
      experimental_v2_decode_config_category(
        experimental_v2_encode_config_category(category),
      ),
      category,
    )
  }
  try experimental_v2_decode_config_category(Json::number(1.0)) catch {
    ExpectedString(path="category") => ()
    _ => fail("expected ExpectedString for a non-string category")
  } noraise {
    _ => fail("expected ExpectedString for a non-string category")
  }
}

///|
test "v2 config select option round-trips optional fields" {
  let decoded = model_test_round_trip(
    "{\"value\":\"opus\",\"name\":\"Opus\",\"description\":\"Fast\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_config_select_option(value),
    experimental_v2_encode_config_select_option,
  )
  assert_eq(decoded.value, "opus")
  assert_eq(decoded.description, Some("Fast"))
  assert_true(
    experimental_v2_decode_config_select_option(
      experimental_v2_parse_json(
        "{\"value\":\"v\",\"name\":\"V\",\"description\":null}",
      ),
    ).description
    is None,
  )
  try
    experimental_v2_decode_config_select_option(
      experimental_v2_parse_json("{\"value\":\"\",\"name\":\"V\"}"),
    )
  catch {
    InvalidField(path="selectOption.value", reason="id must not be empty") => ()
    _ => fail("expected InvalidField for an empty option value id")
  } noraise {
    _ => fail("expected InvalidField for an empty option value id")
  }
}

///|
test "v2 config select options split ungrouped grouped and empty" {
  let decode = source => {
    experimental_v2_decode_config_select_options(
      experimental_v2_parse_json(source),
    )
  }
  assert_true(decode("[]") is OptionsUngrouped([]))
  assert_true(
    decode("[{\"value\":\"v\",\"name\":\"V\"}]") is OptionsUngrouped([_]),
  )
  assert_true(
    decode("[{\"groupId\":\"g\",\"name\":\"G\",\"options\":[]}]")
    is OptionsGrouped([_]),
  )
  try decode("[{}]") catch {
    InvalidField(
      path="options[0]",
      reason="select options must be option values or groups"
    ) => ()
    _ => fail("expected InvalidField for an ambiguous options item")
  } noraise {
    _ => fail("expected InvalidField for an ambiguous options item")
  }
  try decode("[\"x\"]") catch {
    InvalidField(path="options[0]", reason=_) => ()
    _ => fail("expected InvalidField for a non-object options item")
  } noraise {
    _ => fail("expected InvalidField for a non-object options item")
  }
  try
    decode(
      "[{\"groupId\":\"g\",\"name\":\"G\",\"options\":[]},{\"value\":\"v\",\"name\":\"V\"}]",
    )
  catch {
    UnknownField(path="options[1].value") => ()
    _ => fail("expected UnknownField for an option mixed into groups")
  } noraise {
    _ => fail("expected UnknownField for an option mixed into groups")
  }
  let grouped = model_test_round_trip(
    "[{\"groupId\":\"g\",\"name\":\"G\",\"options\":[{\"value\":\"m1\",\"name\":\"M1\"}]}]",
    value => experimental_v2_decode_config_select_options(value),
    experimental_v2_encode_config_select_options,
  )
  assert_true(grouped is OptionsGrouped([{ options: [_], .. }]))
}

///|
test "v2 config option boolean payload round-trips" {
  let decoded = model_test_round_trip(
    "{\"type\":\"boolean\",\"configId\":\"verbose\",\"name\":\"Verbose\",\"description\":null,\"category\":\"mode\",\"currentValue\":true,\"_meta\":{}}",
    value => experimental_v2_decode_config_option(value),
    experimental_v2_encode_config_option,
  )
  assert_true(
    decoded
    is Known(
      {
        config_id: "verbose",
        category: Some(CategoryMode),
        payload: PayloadBoolean({ current_value: true }),
        ..,
      }
    ),
  )
}

///|
test "v2 config option select payload round-trips grouped options" {
  let decoded = model_test_round_trip(
    "{\"type\":\"select\",\"configId\":\"model\",\"name\":\"Model\",\"category\":\"model\",\"currentValue\":\"m1\",\"options\":[{\"groupId\":\"g\",\"name\":\"G\",\"options\":[{\"value\":\"m1\",\"name\":\"M1\",\"description\":\"d\"},{\"value\":\"m2\",\"name\":\"M2\"}]}]}",
    value => experimental_v2_decode_config_option(value),
    experimental_v2_encode_config_option,
  )
  assert_true(
    decoded
    is Known(
      {
        payload: PayloadSelect(
          {
            current_value: "m1",
            options: OptionsGrouped([{ options: [_, _], .. }]),
          }
        ),
        ..,
      }
    ),
  )
}

///|
test "v2 config option requires selector and payload fields" {
  let decode = source => {
    experimental_v2_decode_config_option(experimental_v2_parse_json(source))
  }
  try
    decode("{\"type\":\"boolean\",\"name\":\"N\",\"currentValue\":true}")
  catch {
    MissingField(path="configOption.configId") => ()
    _ => fail("expected MissingField for an absent configId")
  } noraise {
    _ => fail("expected MissingField for an absent configId")
  }
  try
    decode(
      "{\"type\":\"boolean\",\"configId\":\"\",\"name\":\"N\",\"currentValue\":true}",
    )
  catch {
    InvalidField(path="configOption.configId", reason="id must not be empty") =>
      ()
    _ => fail("expected InvalidField for an empty configId")
  } noraise {
    _ => fail("expected InvalidField for an empty configId")
  }
  try
    decode(
      "{\"type\":\"select\",\"configId\":\"c\",\"name\":\"N\",\"currentValue\":\"v\"}",
    )
  catch {
    MissingField(path="configOption.options") => ()
    _ => fail("expected MissingField for absent select options")
  } noraise {
    _ => fail("expected MissingField for absent select options")
  }
  try
    decode(
      "{\"type\":\"boolean\",\"configId\":\"c\",\"name\":\"N\",\"currentValue\":\"yes\"}",
    )
  catch {
    ExpectedBoolean(path="configOption.currentValue") => ()
    _ => fail("expected ExpectedBoolean for a non-boolean currentValue")
  } noraise {
    _ => fail("expected ExpectedBoolean for a non-boolean currentValue")
  }
  try
    decode(
      "{\"type\":\"select\",\"configId\":\"c\",\"name\":\"N\",\"currentValue\":\"v\",\"options\":[],\"weird\":1}",
    )
  catch {
    UnknownField(path="configOption.weird") => ()
    _ => fail("expected UnknownField for a foreign option field")
  } noraise {
    _ => fail("expected UnknownField for a foreign option field")
  }
}

///|
test "v2 config option unknown type stays raw" {
  let source = "{\"type\":\"slider\",\"configId\":\"c\",\"name\":\"N\",\"currentValue\":5}"
  let decoded = experimental_v2_decode_config_option(
    experimental_v2_parse_json(source),
  )
  assert_true(decoded is Future(tag="slider", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_config_option(decoded),
    ),
    source,
  )
}

///|
test "v2 set config option id and boolean payloads round-trip" {
  let by_id = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"configId\":\"model\",\"type\":\"id\",\"value\":\"m1\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_set_config_option(value),
    experimental_v2_encode_set_config_option,
  )
  assert_true(
    by_id
    is Known(
      { session_id: "s1", config_id: "model", value: ConfigValueId("m1"), .. }
    ),
  )
  let by_bool = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"configId\":\"verbose\",\"type\":\"boolean\",\"value\":false}",
    value => experimental_v2_decode_set_config_option(value),
    experimental_v2_encode_set_config_option,
  )
  assert_true(by_bool is Known({ value: ConfigValueBoolean(false), .. }))
}

///|
test "v2 set config option rejects malformed known payloads" {
  let decode = source => {
    experimental_v2_decode_set_config_option(experimental_v2_parse_json(source))
  }
  try
    decode("{\"sessionId\":\"s1\",\"configId\":\"c\",\"value\":\"v\"}")
  catch {
    MissingField(path="set_config_option.type") => ()
    _ => fail("expected MissingField for an absent value type")
  } noraise {
    _ => fail("expected MissingField for an absent value type")
  }
  try
    decode("{\"sessionId\":\"s1\",\"configId\":\"c\",\"type\":\"id\"}")
  catch {
    MissingField(path="set_config_option.value") => ()
    _ => fail("expected MissingField for an absent value")
  } noraise {
    _ => fail("expected MissingField for an absent value")
  }
  try
    decode(
      "{\"sessionId\":\"s1\",\"configId\":\"c\",\"type\":\"id\",\"value\":true}",
    )
  catch {
    ExpectedString(path="set_config_option.value") => ()
    _ => fail("expected ExpectedString for a boolean id value")
  } noraise {
    _ => fail("expected ExpectedString for a boolean id value")
  }
  try
    decode(
      "{\"sessionId\":\"s1\",\"configId\":\"c\",\"type\":\"boolean\",\"value\":\"yes\"}",
    )
  catch {
    ExpectedBoolean(path="set_config_option.value") => ()
    _ => fail("expected ExpectedBoolean for a string boolean value")
  } noraise {
    _ => fail("expected ExpectedBoolean for a string boolean value")
  }
  try decode("{\"configId\":\"c\",\"type\":\"id\",\"value\":\"v\"}") catch {
    MissingField(path="set_config_option.sessionId") => ()
    _ => fail("expected MissingField for an absent sessionId")
  } noraise {
    _ => fail("expected MissingField for an absent sessionId")
  }
}

///|
test "v2 set config option unknown value type stays raw" {
  let source = "{\"sessionId\":\"s1\",\"configId\":\"c\",\"type\":\"slider\",\"value\":{\"min\":0}}"
  let decoded = experimental_v2_decode_set_config_option(
    experimental_v2_parse_json(source),
  )
  assert_true(decoded is Future(tag="slider", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_set_config_option(decoded),
    ),
    source,
  )
}

///|
test "v2 set config result requires the complete configOptions array" {
  let decoded = model_test_round_trip(
    "{\"configOptions\":[{\"type\":\"boolean\",\"configId\":\"verbose\",\"name\":\"Verbose\",\"currentValue\":false},{\"type\":\"select\",\"configId\":\"model\",\"name\":\"Model\",\"currentValue\":\"m1\",\"options\":[{\"value\":\"m1\",\"name\":\"M1\"}]}],\"_meta\":{}}",
    value => experimental_v2_decode_set_config_option_result(value),
    experimental_v2_encode_set_config_option_result,
  )
  assert_true(decoded.config_options is [Known(_), Known(_)])
  try
    experimental_v2_decode_set_config_option_result(
      experimental_v2_parse_json("{}"),
    )
  catch {
    MissingField(path="set_config_option.configOptions") => ()
    _ => fail("expected MissingField for absent configOptions")
  } noraise {
    _ => fail("expected MissingField for absent configOptions")
  }
  try
    experimental_v2_decode_set_config_option_result(
      experimental_v2_parse_json("{\"configOptions\":[],\"currentValues\":{}}"),
    )
  catch {
    UnknownField(path="set_config_option.currentValues") => ()
    _ => fail("expected UnknownField for a foreign result field")
  } noraise {
    _ => fail("expected UnknownField for a foreign result field")
  }
}
