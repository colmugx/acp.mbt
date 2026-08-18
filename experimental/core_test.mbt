///|
/// Parse a compact JSON object fixture into its fields.
fn core_test_object_fields(
  source : String,
) -> Map[String, Json] raise ExperimentalV2DecodeError {
  experimental_v2_require_object(
    experimental_v2_parse_json(source),
    path="fixture",
  )
}

///|
/// Closed test payload `{"type":"alpha"|"beta","count":<integer>}` used to
/// exercise the generic open-union wrapper.
fn core_test_decode_known(
  tag : String,
  payload : Json,
) -> (String, Int) raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(payload, path="update")
  match fields.get("count") {
    Some(Number(count, ..)) =>
      if count == count.floor() {
        (tag, count.to_int())
      } else {
        raise InvalidField(path="update.count", reason="expected an integer")
      }
    _ => raise InvalidField(path="update.count", reason="expected an integer")
  }
}

///|
fn core_test_encode_known(known : (String, Int)) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["type"] = Json::string(known.0)
  fields["count"] = Json::number(known.1.to_double())
  Json::object(fields)
}

///|
test "v2 patch decode distinguishes omitted null and value" {
  let decode = (value, path) => experimental_v2_decode_string(value, path~)
  assert_eq(
    experimental_v2_decode_patch(
      core_test_object_fields("{}"),
      "title",
      decode,
      path="title",
    ),
    PatchOmitted,
  )
  assert_eq(
    experimental_v2_decode_patch(
      core_test_object_fields("{\"title\":null}"),
      "title",
      decode,
      path="title",
    ),
    PatchNull,
  )
  assert_eq(
    experimental_v2_decode_patch(
      core_test_object_fields("{\"title\":\"draft\"}"),
      "title",
      decode,
      path="title",
    ),
    PatchValue("draft"),
  )
}

///|
test "v2 patch encode writes value explicit null or nothing" {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_patch(fields, "title", PatchValue("draft"), Json::string)
  assert_true(fields.get("title") is Some(String("draft")))
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_patch(fields, "title", PatchNull, Json::string)
  assert_true(fields.get("title") is Some(Null))
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_patch(fields, "title", PatchOmitted, Json::string)
  assert_true(fields.get("title") is None)
}

///|
test "v2 patch value round-trips through decode and encode" {
  let decode = (value, path) => experimental_v2_decode_string(value, path~)
  let patch = experimental_v2_decode_patch(
    core_test_object_fields("{\"title\":\"draft\"}"),
    "title",
    decode,
    path="title",
  )
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_patch(fields, "title", patch, Json::string)
  assert_eq(
    experimental_v2_stringify_json(Json::object(fields)),
    "{\"title\":\"draft\"}",
  )
}

///|
test "v2 patch decode propagates typed value errors with path" {
  let decode = (value, path) => experimental_v2_decode_string(value, path~)
  try
    experimental_v2_decode_patch(
      core_test_object_fields("{\"title\":3}"),
      "title",
      decode,
      path="update.title",
    )
  catch {
    ExpectedString(path="update.title") => ()
    _ => fail("expected ExpectedString for a non-string patch value")
  } noraise {
    _ => fail("expected ExpectedString for a non-string patch value")
  }
}

///|
test "v2 open union decodes a known tag with its typed payload" {
  let value = experimental_v2_parse_json("{\"type\":\"alpha\",\"count\":2}")
  assert_eq(
    experimental_v2_decode_open(
      value,
      tag_key="type",
      ["alpha", "beta"],
      core_test_decode_known,
      path="update",
    ),
    Known(("alpha", 2)),
  )
}

///|
test "v2 open union raises a typed error for an illegal known payload" {
  let value = experimental_v2_parse_json(
    "{\"type\":\"alpha\",\"count\":\"two\"}",
  )
  try
    experimental_v2_decode_open(
      value,
      tag_key="type",
      ["alpha", "beta"],
      core_test_decode_known,
      path="update",
    )
  catch {
    InvalidField(path="update.count", reason=_) => ()
    _ => fail("expected a typed error for an illegal known payload")
  } noraise {
    _ => fail("expected a typed error for an illegal known payload")
  }
}

///|
test "v2 open union keeps underscore tags as extension with raw payload" {
  // The tag is deliberately not the first key: replay must preserve order.
  let source = "{\"count\":2,\"type\":\"_custom\"}"
  let decoded = experimental_v2_decode_open(
    experimental_v2_parse_json(source),
    tag_key="type",
    ["alpha", "beta"],
    core_test_decode_known,
    path="update",
  )
  assert_true(decoded is Extension(tag="_custom", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_open(
        decoded,
        tag_key="type",
        core_test_encode_known,
      ),
    ),
    source,
  )
}

///|
test "v2 open union keeps unknown future tags with raw payload" {
  let source = "{\"type\":\"futureThing\",\"items\":[1,2,null]}"
  let decoded = experimental_v2_decode_open(
    experimental_v2_parse_json(source),
    tag_key="type",
    ["alpha", "beta"],
    core_test_decode_known,
    path="update",
  )
  assert_true(decoded is Future(tag="futureThing", ..))
  assert_eq(
    experimental_v2_stringify_json(
      experimental_v2_encode_open(
        decoded,
        tag_key="type",
        core_test_encode_known,
      ),
    ),
    source,
  )
}

///|
test "v2 open union unknown tags do not collide" {
  let decode = value => {
    experimental_v2_decode_open(
      value,
      tag_key="type",
      ["alpha", "beta"],
      core_test_decode_known,
      path="update",
    )
  }
  let first = decode(
    experimental_v2_parse_json("{\"type\":\"_custom\",\"v\":1}"),
  )
  let second = decode(
    experimental_v2_parse_json("{\"type\":\"_custom\",\"v\":2}"),
  )
  let third = decode(
    experimental_v2_parse_json("{\"type\":\"futureThing\",\"v\":1}"),
  )
  assert_false(first == second)
  assert_false(first == third)
  assert_false(second == third)
}

///|
test "v2 open union rejects non-object values and malformed tags" {
  try
    experimental_v2_decode_open(
      Json::string("alpha"),
      tag_key="type",
      ["alpha"],
      core_test_decode_known,
      path="update",
    )
  catch {
    ExpectedObject(path="update") => ()
    _ => fail("expected ExpectedObject for a non-object union value")
  } noraise {
    _ => fail("expected ExpectedObject for a non-object union value")
  }
  try
    experimental_v2_decode_open(
      experimental_v2_parse_json("{\"count\":2}"),
      tag_key="type",
      ["alpha"],
      core_test_decode_known,
      path="update",
    )
  catch {
    MissingField(path="update.type") => ()
    _ => fail("expected MissingField for an absent tag")
  } noraise {
    _ => fail("expected MissingField for an absent tag")
  }
  try
    experimental_v2_decode_open(
      experimental_v2_parse_json("{\"type\":3}"),
      tag_key="type",
      ["alpha"],
      core_test_decode_known,
      path="update",
    )
  catch {
    ExpectedString(path="update.type") => ()
    _ => fail("expected ExpectedString for a non-string tag")
  } noraise {
    _ => fail("expected ExpectedString for a non-string tag")
  }
}

///|
test "v2 open union encode fails fast on an inconsistent raw payload" {
  let mismatch : ExperimentalV2Open[(String, Int)] = Extension(
    tag="_custom",
    raw=experimental_v2_parse_json("{\"type\":\"alpha\"}"),
  )
  try
    experimental_v2_encode_open(
      mismatch,
      tag_key="type",
      core_test_encode_known,
    )
  catch {
    InvalidField(path="type", reason=_) => ()
    _ => fail("expected a typed error for a mismatched raw tag")
  } noraise {
    _ => fail("expected a typed error for a mismatched raw tag")
  }
  let untagged : ExperimentalV2Open[(String, Int)] = Future(
    tag="futureThing",
    raw=experimental_v2_parse_json("{\"count\":2}"),
  )
  try
    experimental_v2_encode_open(
      untagged,
      tag_key="type",
      core_test_encode_known,
    )
  catch {
    InvalidField(path="type", reason=_) => ()
    _ => fail("expected a typed error for a raw payload without the tag")
  } noraise {
    _ => fail("expected a typed error for a raw payload without the tag")
  }
}

///|
test "v2 reject unknown reports the offending key and path" {
  try
    experimental_v2_reject_unknown(
      core_test_object_fields("{\"a\":1,\"extra\":2}"),
      ["a"],
      prefix="params.update",
    )
  catch {
    UnknownField(path="params.update.extra") => ()
    _ => fail("expected UnknownField with key and path")
  } noraise {
    _ => fail("expected UnknownField with key and path")
  }
  try
    experimental_v2_reject_unknown(
      core_test_object_fields("{\"extra\":1}"),
      ["a"],
      prefix="",
    )
  catch {
    UnknownField(path="extra") => ()
    _ => fail("expected UnknownField with a bare key for an empty prefix")
  } noraise {
    _ => fail("expected UnknownField with a bare key for an empty prefix")
  }
  experimental_v2_reject_unknown(
    core_test_object_fields("{\"a\":1,\"_meta\":null}"),
    ["a", "_meta"],
    prefix="params.update",
  )
}

///|
test "v2 meta top-level tri-state and nested omission-equals-null on one fixture" {
  let omitted = core_test_object_fields("{\"title\":\"t\"}")
  let nulled = core_test_object_fields("{\"title\":\"t\",\"_meta\":null}")
  let valued = core_test_object_fields("{\"title\":\"t\",\"_meta\":{\"k\":1}}")
  assert_eq(experimental_v2_top_meta(omitted, path="update"), PatchOmitted)
  assert_eq(experimental_v2_top_meta(nulled, path="update"), PatchNull)
  assert_true(
    experimental_v2_top_meta(valued, path="update") is PatchValue(Object(_)),
  )
  assert_true(experimental_v2_nested_meta(omitted, path="update.part") is None)
  assert_true(experimental_v2_nested_meta(nulled, path="update.part") is None)
  assert_true(
    experimental_v2_nested_meta(valued, path="update.part") is Some(Object(_)),
  )
}

///|
test "v2 meta rejects non-object values at both levels" {
  try
    experimental_v2_top_meta(
      core_test_object_fields("{\"_meta\":3}"),
      path="update",
    )
  catch {
    InvalidField(path="update", reason="_meta must be an object or null") => ()
    _ => fail("expected a typed error for a non-object top-level _meta")
  } noraise {
    _ => fail("expected a typed error for a non-object top-level _meta")
  }
  try
    experimental_v2_nested_meta(
      core_test_object_fields("{\"_meta\":\"x\"}"),
      path="update.part",
    )
  catch {
    InvalidField(path="update.part", reason="_meta must be an object or null") =>
      ()
    _ => fail("expected a typed error for a non-object nested _meta")
  } noraise {
    _ => fail("expected a typed error for a non-object nested _meta")
  }
}

///|
test "v2 top-level meta encodes all three patch states" {
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_top_meta(
    fields,
    PatchValue(experimental_v2_parse_json("{\"k\":1}")),
  )
  assert_true(fields.get("_meta") is Some(Object(_)))
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_top_meta(fields, PatchNull)
  assert_true(fields.get("_meta") is Some(Null))
  let fields : Map[String, Json] = Map([])
  experimental_v2_put_top_meta(fields, PatchOmitted)
  assert_true(fields.get("_meta") is None)
  try
    experimental_v2_put_top_meta(fields, PatchValue(Json::string("x")))
  catch {
    InvalidField(path="_meta", reason=_) => ()
    _ => fail("expected a typed error for a non-object encoded _meta")
  } noraise {
    _ => fail("expected a typed error for a non-object encoded _meta")
  }
}

///|
test "v2 id validation rejects the empty id and keeps non-empty ids" {
  assert_eq(
    experimental_v2_validate_id("sess-1", field_path="update.sessionId"),
    "sess-1",
  )
  try experimental_v2_validate_id("", field_path="update.sessionId") catch {
    InvalidField(path="update.sessionId", reason="id must not be empty") => ()
    _ => fail("expected a typed error for an empty id")
  } noraise {
    _ => fail("expected a typed error for an empty id")
  }
}

///|
test "v2 absolute path validation accepts absolute and rejects relative" {
  assert_eq(
    experimental_v2_validate_absolute_path(
      "/tmp/a",
      field_path="session/new.cwd",
    ),
    "/tmp/a",
  )
  assert_eq(
    experimental_v2_validate_absolute_path(
      "C:\\x",
      field_path="session/new.cwd",
    ),
    "C:\\x",
  )
  try
    experimental_v2_validate_absolute_path(
      "relative/x",
      field_path="session/new.cwd",
    )
  catch {
    InvalidPath(path="session/new.cwd", value="relative/x") => ()
    _ => fail("expected a typed error for a relative path")
  } noraise {
    _ => fail("expected a typed error for a relative path")
  }
  try
    experimental_v2_validate_absolute_path("", field_path="session/new.cwd")
  catch {
    InvalidPath(path="session/new.cwd", value="") => ()
    _ => fail("expected a typed error for an empty path")
  } noraise {
    _ => fail("expected a typed error for an empty path")
  }
}
