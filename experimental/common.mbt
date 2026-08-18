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
  encode : (T) -> Json,
) -> Unit {
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
