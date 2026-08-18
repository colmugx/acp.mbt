///|
/// Structured failures raised while decoding the ACP v2 stable-baseline data
/// model.  Paths are wire-property paths (with array indexes where
/// applicable).  No helper in this package turns an invalid value into a
/// default value.
pub(all) suberror ExperimentalV2DecodeError {
  JsonParse(message~ : String)
  ExpectedObject(path~ : String)
  ExpectedArray(path~ : String)
  ExpectedString(path~ : String)
  ExpectedBoolean(path~ : String)
  ExpectedNumber(path~ : String)
  MissingField(path~ : String)
  UnknownField(path~ : String)
  InvalidField(path~ : String, reason~ : String)
  InvalidDiscriminator(path~ : String, value~ : String)
  InvalidPath(path~ : String, value~ : String)
  InvalidBase64(path~ : String)
} derive(Eq, Debug)

///|
/// Parse one JSON value for the v2 data-model codecs.
pub fn experimental_v2_parse_json(
  source : String,
) -> Json raise ExperimentalV2DecodeError {
  @json.parse(source) catch {
    error => raise JsonParse(message=error.to_string())
  }
}

///|
/// Stringify one v2 JSON value without adding a framing newline.
pub fn experimental_v2_stringify_json(value : Json) -> String {
  value.stringify()
}

///|
/// v2 patch tri-state: `PatchOmitted` = key absent = unchanged,
/// `PatchNull` = explicit JSON null = clear, `PatchValue` = replace.
/// Never collapse it into a plain optional/nullable: omitted and null carry
/// different patch semantics in v2.
pub(all) enum ExperimentalV2Patch[T] {
  PatchOmitted
  PatchNull
  PatchValue(T)
} derive(Eq, Debug)

///|
/// Read one field as a raw patch tri-state.
pub fn experimental_v2_patch_field(
  fields : Map[String, Json],
  key : String,
) -> ExperimentalV2Patch[Json] {
  match fields.get(key) {
    None => PatchOmitted
    Some(Null) => PatchNull
    Some(value) => PatchValue(value)
  }
}

///|
/// Decode one patch field through a typed decoder.  `path` is the wire path
/// of the field itself; it is handed to the decoder so value errors carry it.
pub fn[T] experimental_v2_decode_patch(
  fields : Map[String, Json],
  key : String,
  path~ : String,
  decode : (Json, String) -> T raise ExperimentalV2DecodeError,
) -> ExperimentalV2Patch[T] raise ExperimentalV2DecodeError {
  match experimental_v2_patch_field(fields, key) {
    PatchOmitted => PatchOmitted
    PatchNull => PatchNull
    PatchValue(value) => PatchValue(decode(value, path))
  }
}

///|
/// Encode one patch field: `PatchOmitted` skips the key entirely,
/// `PatchNull` writes JSON null, `PatchValue` writes the encoded value.
pub fn[T] experimental_v2_put_patch(
  fields : Map[String, Json],
  key : String,
  value : ExperimentalV2Patch[T],
  encode : (T) -> Json raise ExperimentalV2DecodeError,
) -> Unit raise ExperimentalV2DecodeError {
  match value {
    PatchOmitted => ()
    PatchNull => fields[key] = Json::null()
    PatchValue(value) => fields[key] = encode(value)
  }
}

///|
/// Require a JSON object at `path`.
pub fn experimental_v2_require_object(
  value : Json,
  path~ : String,
) -> Map[String, Json] raise ExperimentalV2DecodeError {
  match value {
    Object(fields) => fields
    _ => raise ExpectedObject(path~)
  }
}

///|
/// Decode a JSON string at `path`.
pub fn experimental_v2_decode_string(
  value : Json,
  path~ : String,
) -> String raise ExperimentalV2DecodeError {
  match value {
    String(text) => text
    _ => raise ExpectedString(path~)
  }
}

///|
/// Reject fields outside `allowed`; the error path is `prefix.key` (or bare
/// `key` when the prefix is empty).
pub fn experimental_v2_reject_unknown(
  fields : Map[String, Json],
  allowed : ArrayView[String],
  prefix~ : String,
) -> Unit raise ExperimentalV2DecodeError {
  for key, _ in fields {
    if !allowed.contains(key) {
      let path = if prefix == "" { key } else { prefix + "." + key }
      raise UnknownField(path~)
    }
  }
}

///|
/// Top-level `_meta` of a v2 upsert is a patch tri-state: omitted =
/// unchanged, null = clear, object = replace.
pub fn experimental_v2_top_meta(
  fields : Map[String, Json],
  path~ : String,
) -> ExperimentalV2Patch[Json] raise ExperimentalV2DecodeError {
  match experimental_v2_patch_field(fields, "_meta") {
    PatchValue(value) => experimental_v2_meta_object(value, path)
    other => other
  }
}

///|
/// Nested `_meta` treats omission == null: both collapse to `None`.
pub fn experimental_v2_nested_meta(
  fields : Map[String, Json],
  path~ : String,
) -> Json? raise ExperimentalV2DecodeError {
  match experimental_v2_top_meta(fields, path~) {
    PatchOmitted | PatchNull => None
    PatchValue(value) => Some(value)
  }
}

///|
/// Encode the top-level `_meta` patch tri-state.
pub fn experimental_v2_put_top_meta(
  fields : Map[String, Json],
  value : ExperimentalV2Patch[Json],
) -> Unit raise ExperimentalV2DecodeError {
  match value {
    PatchOmitted => ()
    PatchNull => fields["_meta"] = Json::null()
    PatchValue(value) =>
      match value {
        Object(_) => fields["_meta"] = value
        _ =>
          raise InvalidField(
            path="_meta",
            reason="_meta must be an object or null",
          )
      }
  }
}

///|
fn experimental_v2_meta_object(
  value : Json,
  path : String,
) -> ExperimentalV2Patch[Json] raise ExperimentalV2DecodeError {
  match value {
    Object(_) => PatchValue(value)
    _ => raise InvalidField(path~, reason="_meta must be an object or null")
  }
}

///|
/// v2 ids (session/message/tool-call/plan/option/method/config/group) are
/// non-empty strings; the empty id that can address nothing is a typed
/// failure.
pub fn experimental_v2_validate_id(
  value : String,
  field_path~ : String,
) -> String raise ExperimentalV2DecodeError {
  if value == "" {
    raise InvalidField(path=field_path, reason="id must not be empty")
  }
  value
}

///|
fn experimental_v2_path_is_absolute(path : String) -> Bool {
  if path.has_prefix("/") || path.has_prefix("\\\\") {
    true
  } else {
    match (path.get_char(0), path.get_char(1), path.get_char(2)) {
      (Some(first), Some(':'), Some('/' | '\\')) =>
        (first >= 'A' && first <= 'Z') || (first >= 'a' && first <= 'z')
      _ => false
    }
  }
}

///|
pub fn experimental_v2_validate_absolute_path(
  path : String,
  field_path~ : String,
) -> String raise ExperimentalV2DecodeError {
  if experimental_v2_path_is_absolute(path) {
    path
  } else {
    raise InvalidPath(path=field_path, value=path)
  }
}

///|
/// Validate one RFC 4648 base64 payload on both decode and encode paths.
pub fn experimental_v2_validate_base64(
  value : String,
  field_path~ : String,
) -> String raise ExperimentalV2DecodeError {
  ignore(
    @base64.decode(value) catch {
      _ => raise InvalidBase64(path=field_path)
    },
  )
  value
}

///|
fn experimental_v2_decode_finite_number(
  value : Json,
  path~ : String,
) -> Double raise ExperimentalV2DecodeError {
  match value {
    Number(number, ..) =>
      if number.is_nan() || number.is_inf() {
        raise InvalidField(path~, reason="number must be finite")
      } else {
        number
      }
    _ => raise ExpectedNumber(path~)
  }
}

///|
fn experimental_v2_decode_uint32(
  value : Json,
  path~ : String,
) -> UInt raise ExperimentalV2DecodeError {
  match value {
    Number(number, ..) =>
      if number == number.floor() && number >= 0.0 && number <= 4294967295.0 {
        number.to_uint()
      } else {
        raise InvalidField(path~, reason="expected a uint32 integer")
      }
    _ => raise ExpectedNumber(path~)
  }
}

///|
/// Decode a signed 64-bit integer without trusting a rounded `Double`: a
/// number beyond the exact binary integer range must retain its original
/// JSON text in `repr`, and only a plain (optionally negative) digit run is
/// accepted there; exponent or decimal reprs are typed failures.
fn experimental_v2_decode_int64(
  value : Json,
  path~ : String,
) -> Int64 raise ExperimentalV2DecodeError {
  match value {
    Number(number, repr~) =>
      match repr {
        Some(text) => experimental_v2_parse_int64_repr(text, path~)
        None =>
          if number.is_nan() ||
            number.is_inf() ||
            number != number.floor() ||
            number.abs() > 9007199254740991.0 {
            raise InvalidField(path~, reason="expected a signed 64-bit integer")
          } else {
            number.to_int64()
          }
      }
    _ => raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
}

///|
/// Encode an exact int64 number: the original decimal text rides along as
/// `repr` so values beyond the binary double range stringify losslessly.
fn experimental_v2_encode_int64(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
fn experimental_v2_parse_int64_repr(
  text : String,
  path~ : String,
) -> Int64 raise ExperimentalV2DecodeError {
  if text == "-9223372036854775808" {
    return -9223372036854775807L - 1L
  }
  let chars = text.to_array()
  let length = chars.length()
  let negative = length > 0 && chars[0] == '-'
  let mut index = if negative { 1 } else { 0 }
  if index >= length {
    raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
  let bound : Int64 = 9223372036854775807L
  let mut value : Int64 = 0L
  while index < length {
    let ch = chars[index]
    if ch < '0' || ch > '9' {
      raise InvalidField(path~, reason="expected a signed 64-bit integer")
    }
    let digit = (ch.to_int() - '0'.to_int()).to_int64()
    if value > (bound - digit) / 10L {
      raise InvalidField(path~, reason="signed 64-bit integer out of range")
    }
    value = value * 10L + digit
    index += 1
  }
  if negative {
    -value
  } else {
    value
  }
}
