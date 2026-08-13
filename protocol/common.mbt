///|
/// A three-state field used when the wire protocol distinguishes an omitted
/// property from an explicit JSON null.
pub(all) enum ProtocolNullable[T] {
  Omitted
  Null
  Value(T)
} derive(Eq, Debug)

///|
/// Roles used by ACP annotations.
pub(all) enum Role {
  User
  Assistant
} derive(Eq, Debug)

///|
/// Stable ACP identifiers are strings on the wire.
pub type SessionId = String

///|
pub type MessageId = String

///|
pub type ToolCallId = String

///|
pub type TerminalId = String

///|
pub type PermissionOptionId = String

///|
pub type SessionConfigId = String

///|
pub type SessionConfigValueId = String

///|
pub type SessionConfigGroupId = String

///|
pub type SessionModeId = String

///|
/// Structured failures raised while decoding the stable ACP data model.
///
/// The path is always a wire-property path (with array indexes where
/// applicable).  No decoder in this package turns an invalid value into a
/// default value.
pub(all) suberror ProtocolDecodeError {
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
/// Parse one JSON value for the protocol data-model codecs.
pub fn protocol_parse_json(source : String) -> Json raise ProtocolDecodeError {
  @json.parse(source) catch {
    error => raise JsonParse(message=error.to_string())
  }
}

///|
/// Stringify one protocol JSON value without adding a framing newline.
pub fn protocol_stringify_json(value : Json) -> String {
  value.stringify()
}

///|
pub fn protocol_field(
  fields : Map[String, Json],
  key : String,
) -> ProtocolNullable[Json] {
  match fields.get(key) {
    None => Omitted
    Some(Null) => Null
    Some(value) => Value(value)
  }
}

///|
pub fn protocol_require_object(
  value : Json,
  path~ : String,
) -> Map[String, Json] raise ProtocolDecodeError {
  match value {
    Object(fields) => fields
    _ => raise ExpectedObject(path~)
  }
}

///|
pub fn protocol_require_array(
  value : Json,
  path~ : String,
) -> Array[Json] raise ProtocolDecodeError {
  match value {
    Array(values) => values
    _ => raise ExpectedArray(path~)
  }
}

///|
pub fn protocol_required(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> Json raise ProtocolDecodeError {
  match fields.get(key) {
    Some(value) => value
    None => raise MissingField(path~)
  }
}

///|
pub fn protocol_required_string(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> String raise ProtocolDecodeError {
  match protocol_required(fields, key, path~) {
    String(value) => value
    _ => raise ExpectedString(path~)
  }
}

///|
pub fn protocol_decode_string(
  value : Json,
  path~ : String,
) -> String raise ProtocolDecodeError {
  match value {
    String(text) => text
    _ => raise ExpectedString(path~)
  }
}

///|
fn protocol_decode_number(
  value : Json,
  path~ : String,
) -> Double raise ProtocolDecodeError {
  match value {
    Number(number, ..) => number
    _ => raise ExpectedNumber(path~)
  }
}

///|
pub fn protocol_decode_boolean(
  value : Json,
  path~ : String,
) -> Bool raise ProtocolDecodeError {
  match value {
    True => true
    False => false
    _ => raise ExpectedBoolean(path~)
  }
}

///|
fn protocol_decode_int64(
  value : Json,
  path~ : String,
) -> Int64 raise ProtocolDecodeError {
  match value {
    String(_) =>
      @json.from_json(value) catch {
        _ =>
          raise InvalidField(path~, reason="expected a signed 64-bit integer")
      }
    Number(number, ..) => protocol_decode_number_int64(number, path~)
    _ => raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
}

///|
fn protocol_decode_number_int64(
  number : Double,
  path~ : String,
) -> Int64 raise ProtocolDecodeError {
  if number.is_nan() || number.is_inf() || number != number.floor() {
    raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
  if number < -9223372036854775808.0 || number >= 9223372036854775808.0 {
    raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
  number.to_int64()
}

///|
fn protocol_decode_uint64(
  value : Json,
  path~ : String,
) -> UInt64 raise ProtocolDecodeError {
  match value {
    String(_) =>
      @json.from_json(value) catch {
        _ =>
          raise InvalidField(
            path~,
            reason="expected a non-negative 64-bit integer",
          )
      }
    Number(number, ..) => protocol_decode_number_uint64(number, path~)
    _ =>
      raise InvalidField(path~, reason="expected a non-negative 64-bit integer")
  }
}

///|
fn protocol_decode_number_uint64(
  number : Double,
  path~ : String,
) -> UInt64 raise ProtocolDecodeError {
  if number.is_nan() || number.is_inf() || number != number.floor() {
    raise InvalidField(path~, reason="expected a non-negative 64-bit integer")
  }
  if number < 0.0 || number >= 18446744073709551616.0 {
    raise InvalidField(path~, reason="expected a non-negative 64-bit integer")
  }
  number.to_uint64()
}

///|
fn protocol_decode_wire_uint64(
  value : Json,
  path~ : String,
) -> UInt64 raise ProtocolDecodeError {
  match value {
    Number(number, ..) => protocol_decode_number_uint64(number, path~)
    _ => raise InvalidField(path~, reason="expected a non-negative integer")
  }
}

///|
fn protocol_encode_uint64(value : UInt64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub fn protocol_nullable_string(
  fields : Map[String, Json],
  key : String,
  path~ : String,
) -> ProtocolNullable[String] raise ProtocolDecodeError {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(protocol_decode_string(value, path~))
  }
}

///|
fn protocol_nullable_json(
  fields : Map[String, Json],
  key : String,
) -> ProtocolNullable[Json] {
  match protocol_field(fields, key) {
    Omitted => Omitted
    Null => Null
    Value(value) => Value(value)
  }
}

///|
pub fn protocol_meta(
  fields : Map[String, Json],
  path~ : String,
) -> ProtocolNullable[Json] raise ProtocolDecodeError {
  match protocol_nullable_json(fields, "_meta") {
    Value(value) =>
      match value {
        Object(_) => Value(value)
        _ => raise InvalidField(path~, reason="_meta must be an object or null")
      }
    other => other
  }
}

///|
pub fn[T] protocol_put_nullable(
  fields : Map[String, Json],
  key : String,
  value : ProtocolNullable[T],
  encode : (T) -> Json,
) -> Unit {
  match value {
    Omitted => ()
    Null => fields[key] = Json::null()
    Value(value) => fields[key] = encode(value)
  }
}

///|
pub fn protocol_put_meta(
  fields : Map[String, Json],
  value : ProtocolNullable[Json],
) -> Unit raise ProtocolDecodeError {
  match value {
    Omitted => ()
    Null => fields["_meta"] = Json::null()
    Value(value) =>
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
pub fn protocol_reject_unknown(
  fields : Map[String, Json],
  allowed : ArrayView[String],
  prefix~ : String,
) -> Unit raise ProtocolDecodeError {
  for key, _ in fields {
    if !allowed.contains(key) {
      let path = if prefix == "" { key } else { prefix + "." + key }
      raise UnknownField(path~)
    }
  }
}

///|
fn protocol_path_is_absolute(path : String) -> Bool {
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
pub fn protocol_validate_absolute_path(
  path : String,
  field_path~ : String,
) -> String raise ProtocolDecodeError {
  if protocol_path_is_absolute(path) {
    path
  } else {
    raise InvalidPath(path=field_path, value=path)
  }
}

///|
fn protocol_validate_base64(
  value : String,
  field_path~ : String,
) -> String raise ProtocolDecodeError {
  ignore(
    @base64.decode(value) catch {
      _ => raise InvalidBase64(path=field_path)
    },
  )
  value
}

///|
fn protocol_encode_role(role : Role) -> Json {
  match role {
    User => Json::string("user")
    Assistant => Json::string("assistant")
  }
}

///|
fn protocol_decode_role(
  value : Json,
  path~ : String,
) -> Role raise ProtocolDecodeError {
  match value {
    String("user") => User
    String("assistant") => Assistant
    String(value) => raise InvalidDiscriminator(path~, value~)
    _ => raise ExpectedString(path~)
  }
}
