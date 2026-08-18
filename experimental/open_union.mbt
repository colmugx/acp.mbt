///|
/// v2 open-union wrapper.  `Known` holds the decoded payload of a tag this
/// baseline understands; `Extension` holds a `_`-prefixed implementation tag
/// with its original JSON object; `Future` holds any other unknown tag the
/// same way.  Extension and Future keep the raw object so proxies can replay
/// it byte-faithfully instead of dropping or guessing at it.
pub(all) enum ExperimentalV2Open[T] {
  Known(T)
  Extension(tag~ : String, raw~ : Json)
  Future(tag~ : String, raw~ : Json)
} derive(Eq, Debug)

///|
/// Decode one open-union value.  `tag_key` names the discriminator field.
/// A known tag decodes through `decode_known` (which must raise on illegal
/// payloads); a `_`-prefixed unknown tag becomes `Extension`; any other
/// unknown tag becomes `Future`.  Unknown tags never become errors and known
/// tags never fall back to raw passthrough.
pub fn[T] experimental_v2_decode_open(
  value : Json,
  tag_key~ : String,
  known_tags : ArrayView[String],
  decode_known : (String, Json) -> T raise ExperimentalV2DecodeError,
  path~ : String,
) -> ExperimentalV2Open[T] raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  let tag_path = if path == "" { tag_key } else { path + "." + tag_key }
  let tag = match fields.get(tag_key) {
    None => raise MissingField(path=tag_path)
    Some(String(tag)) => tag
    Some(_) => raise ExpectedString(path=tag_path)
  }
  if known_tags.contains(tag) {
    Known(decode_known(tag, value))
  } else if tag.has_prefix("_") {
    Extension(tag~, raw=value)
  } else {
    Future(tag~, raw=value)
  }
}

///|
/// Encode one open-union value.  Extension and Future re-emit their original
/// object unchanged; a hand-built value whose raw object lost the variant
/// tag fails fast instead of silently corrupting replay.
pub fn[T] experimental_v2_encode_open(
  value : ExperimentalV2Open[T],
  tag_key~ : String,
  encode_known : (T) -> Json raise ExperimentalV2DecodeError,
) -> Json raise ExperimentalV2DecodeError {
  match value {
    Known(known) => encode_known(known)
    Extension(tag~, raw~) | Future(tag~, raw~) =>
      match raw {
        Object(fields) =>
          match fields.get(tag_key) {
            Some(String(actual)) =>
              if actual == tag {
                raw
              } else {
                raise InvalidField(
                  path=tag_key,
                  reason="open-union raw payload tag does not match its variant",
                )
              }
            _ => raise experimental_v2_open_raw_tag_error(tag_key)
          }
        _ => raise experimental_v2_open_raw_tag_error(tag_key)
      }
  }
}

///|
fn experimental_v2_open_raw_tag_error(
  tag_key : String,
) -> ExperimentalV2DecodeError {
  InvalidField(
    path=tag_key,
    reason="open-union raw payload must carry its tag in \"" + tag_key + "\"",
  )
}

///|
/// Stamp one discriminator into an already-encoded payload object.  Union
/// encoders own the tag; the payload encoders stay pure per their schema
/// definitions.
pub fn experimental_v2_tag_payload(
  payload : Json,
  tag_key~ : String,
  tag~ : String,
) -> Json raise ExperimentalV2DecodeError {
  match payload {
    Object(fields) => {
      fields[tag_key] = Json::string(tag)
      Json::object(fields)
    }
    _ =>
      raise InvalidField(
        path=tag_key,
        reason="tagged payload must encode to an object",
      )
  }
}

///|
/// Remove one discriminator from an encoded payload object so the payload can
/// decode through its own strict field check.  Mirror of
/// `experimental_v2_tag_payload` for inline (flattened) unions such as
/// `sessionUpdate` and `mode`, where the tag and the payload fields share one
/// object.
pub fn experimental_v2_untag_payload(
  value : Json,
  tag_key~ : String,
  path~ : String,
) -> Json raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path~)
  let stripped : Map[String, Json] = Map([])
  for key, field in fields {
    if key != tag_key {
      stripped[key] = field
    }
  }
  Json::object(stripped)
}
