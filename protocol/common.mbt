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
    Number(number, repr~) => protocol_decode_number_int64(number, repr, path~)
    _ => raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
}

///|
fn protocol_decode_number_int64(
  number : Double,
  repr : String?,
  path~ : String,
) -> Int64 raise ProtocolDecodeError {
  match protocol_parse_int64_number(number, repr) {
    Ok(value) => value
    Err(Malformed | NonFinite | Fractional | OutOfRange | PrecisionUnavailable) =>
      raise InvalidField(path~, reason="expected a signed 64-bit integer")
  }
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
    Number(number, repr~) => protocol_decode_number_uint64(number, repr, path~)
    _ =>
      raise InvalidField(path~, reason="expected a non-negative 64-bit integer")
  }
}

///|
fn protocol_decode_number_uint64(
  number : Double,
  repr : String?,
  path~ : String,
) -> UInt64 raise ProtocolDecodeError {
  match protocol_parse_uint64_number(number, repr) {
    Ok(value) => value
    Err(Malformed | NonFinite | Fractional | OutOfRange | PrecisionUnavailable) =>
      raise InvalidField(path~, reason="expected a non-negative 64-bit integer")
  }
}

///|
priv enum ProtocolUInt64NumberError {
  Malformed
  NonFinite
  Fractional
  OutOfRange
  PrecisionUnavailable
}

///|
/// Decode an unsigned integer-valued JSON number without trusting a rounded
/// `Double`.  The JSON parser retains the original decimal representation in
/// `repr` when the value is not losslessly represented by a finite `Double`.
fn protocol_parse_uint64_number(
  number : Double,
  repr : String?,
) -> Result[UInt64, ProtocolUInt64NumberError] {
  match repr {
    Some(text) => protocol_parse_uint64_repr(text)
    None =>
      if number.is_nan() || number.is_inf() {
        Err(NonFinite)
      } else if number != number.floor() {
        Err(Fractional)
      } else if number < 0.0 {
        Err(OutOfRange)
      } else if number > 9007199254740991.0 {
        Err(PrecisionUnavailable)
      } else {
        Ok(number.to_uint64())
      }
  }
}

///|
fn protocol_parse_uint64_repr(
  text : String,
) -> Result[UInt64, ProtocolUInt64NumberError] {
  let chars = text.to_array()
  let length = chars.length()
  if length == 0 {
    return Err(Malformed)
  }
  let mut index = 0
  if chars[index] == '-' {
    index += 1
    if index == length {
      return Err(Malformed)
    }
  }
  let start = index
  if chars[index] == '0' {
    index += 1
    if index < length && protocol_is_digit(chars[index]) {
      return Err(Malformed)
    }
  } else if protocol_is_digit(chars[index]) {
    index += 1
    while index < length && protocol_is_digit(chars[index]) {
      index += 1
    }
  } else {
    return Err(Malformed)
  }
  let decimal_index : Int? = if index < length && chars[index] == '.' {
    let decimal = index
    index += 1
    let fraction_start = index
    while index < length && protocol_is_digit(chars[index]) {
      index += 1
    }
    if index == fraction_start {
      return Err(Malformed)
    }
    Some(decimal)
  } else {
    None
  }
  let exponent_index : Int? = if index < length &&
    (chars[index] == 'e' || chars[index] == 'E') {
    let exponent = index
    index += 1
    if index < length && (chars[index] == '+' || chars[index] == '-') {
      index += 1
    }
    let exponent_start = index
    while index < length && protocol_is_digit(chars[index]) {
      index += 1
    }
    if index == exponent_start {
      return Err(Malformed)
    }
    Some(exponent)
  } else {
    None
  }
  if index != length {
    return Err(Malformed)
  }
  match (decimal_index, exponent_index) {
    (None, None) => protocol_parse_uint64_text(text)
    _ =>
      protocol_parse_uint64_decimal(chars, start, decimal_index, exponent_index)
  }
}

///|
fn protocol_is_digit(value : Char) -> Bool {
  let digit = value.to_int() - '0'
  digit >= 0 && digit <= 9
}

///|
fn protocol_parse_uint64_text(
  text : String,
) -> Result[UInt64, ProtocolUInt64NumberError] {
  let chars = text.to_array()
  let length = chars.length()
  if length == 0 {
    return Err(OutOfRange)
  }
  let negative = chars[0] == '-'
  let start = if negative { 1 } else { 0 }
  if start == length {
    return Err(OutOfRange)
  }
  let max_value : UInt64 = 18446744073709551615UL
  let mut value : UInt64 = 0UL
  for index in start..<length {
    let digit = chars[index].to_int() - '0'
    if digit < 0 || digit > 9 {
      return Err(OutOfRange)
    }
    let digit64 = digit.to_uint64()
    if negative {
      if digit64 != 0UL {
        return Err(OutOfRange)
      }
    } else {
      if value > max_value / 10UL ||
        (value == max_value / 10UL && digit64 > 5UL) {
        return Err(OutOfRange)
      }
      value = value * 10UL + digit64
    }
  }
  Ok(value)
}

///|
priv enum ProtocolDecimalShift {
  Finite(negative~ : Bool, magnitude~ : Int)
  Huge(negative~ : Bool)
}

///|
fn protocol_decimal_shift(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> ProtocolDecimalShift {
  let negative = chars[start] == '-'
  let digit_start = if negative || chars[start] == '+' {
    start + 1
  } else {
    start
  }
  let mut magnitude = 0
  let mut huge = false
  for index in digit_start..<end {
    if !huge {
      let digit = chars[index].to_int() - '0'
      if magnitude > 100000 / 10 || magnitude * 10 > 100000 - digit {
        huge = true
      } else {
        magnitude = magnitude * 10 + digit
      }
    }
  }
  if huge {
    Huge(negative~)
  } else {
    Finite(negative~, magnitude~)
  }
}

///|
fn protocol_trim_leading_zeroes(text : String) -> String {
  let chars = text.to_array()
  let mut first = 0
  for index in 0..<chars.length() {
    if chars[index] != '0' {
      first = index
      break
    }
    first = index + 1
  }
  if first == chars.length() {
    "0"
  } else {
    text.sub(start=first).to_owned()
  }
}

///|
fn protocol_parse_uint64_decimal(
  chars : Array[Char],
  start : Int,
  decimal_index : Int?,
  exponent_index : Int?,
) -> Result[UInt64, ProtocolUInt64NumberError] {
  let mantissa_end = match exponent_index {
    Some(index) => index
    None => chars.length()
  }
  let fractional_digits = match decimal_index {
    Some(index) => mantissa_end - index - 1
    None => 0
  }
  let digits_builder = StringBuilder(size_hint=mantissa_end - start)
  let mut nonzero = false
  for index in start..<mantissa_end {
    let digit = chars[index]
    if digit != '.' {
      digits_builder.write_char(digit)
      if digit != '0' {
        nonzero = true
      }
    }
  }
  if !nonzero {
    return Ok(0UL)
  }
  let digits = protocol_trim_leading_zeroes(digits_builder.to_string())
  let shift = match exponent_index {
    Some(index) => protocol_decimal_shift(chars, index + 1, chars.length())
    None => Finite(negative=false, magnitude=0)
  }
  let scale = match shift {
    Finite(negative=true, magnitude~) => -magnitude - fractional_digits
    Finite(negative=false, magnitude~) => magnitude - fractional_digits
    Huge(negative=true) => return Err(Fractional)
    Huge(negative=false) => return Err(OutOfRange)
  }
  if scale < 0 {
    let remove = -scale
    if remove >= digits.length() {
      return Err(Fractional)
    }
    let digit_chars = digits.to_array()
    for index in (digits.length() - remove)..<digits.length() {
      if digit_chars[index] != '0' {
        return Err(Fractional)
      }
    }
    let integer_digits = digits.sub(end=digits.length() - remove).to_owned()
    let sign = if start == 1 { "-" } else { "" }
    protocol_parse_uint64_text(sign + integer_digits)
  } else {
    if digits.length() + scale > 20 {
      return Err(OutOfRange)
    }
    let zeros = "0".repeat(scale)
    let sign = if start == 1 { "-" } else { "" }
    protocol_parse_uint64_text(sign + digits + zeros)
  }
}

///|
priv enum ProtocolInt64NumberError {
  Malformed
  NonFinite
  Fractional
  OutOfRange
  PrecisionUnavailable
}

///|
/// Decode a signed integer-valued JSON number without trusting a rounded
/// `Double`.  A repr-less Double is accepted only inside the exact binary
/// integer range; larger values must retain their original JSON text.
fn protocol_parse_int64_number(
  number : Double,
  repr : String?,
) -> Result[Int64, ProtocolInt64NumberError] {
  match repr {
    Some(text) => protocol_parse_int64_repr(text)
    None =>
      if number.is_nan() || number.is_inf() {
        Err(NonFinite)
      } else if number != number.floor() {
        Err(Fractional)
      } else if number.abs() > 9007199254740991.0 {
        Err(PrecisionUnavailable)
      } else {
        Ok(number.to_int64())
      }
  }
}

///|
fn protocol_parse_int64_repr(
  text : String,
) -> Result[Int64, ProtocolInt64NumberError] {
  let chars = text.to_array()
  let length = chars.length()
  if length == 0 {
    return Err(Malformed)
  }
  let mut index = 0
  if chars[index] == '-' {
    index += 1
    if index == length {
      return Err(Malformed)
    }
  }
  let start = index
  if chars[index] == '0' {
    index += 1
    if index < length && protocol_is_digit(chars[index]) {
      return Err(Malformed)
    }
  } else if protocol_is_digit(chars[index]) {
    index += 1
    while index < length && protocol_is_digit(chars[index]) {
      index += 1
    }
  } else {
    return Err(Malformed)
  }
  let decimal_index : Int? = if index < length && chars[index] == '.' {
    let decimal = index
    index += 1
    let fraction_start = index
    while index < length && protocol_is_digit(chars[index]) {
      index += 1
    }
    if index == fraction_start {
      return Err(Malformed)
    }
    Some(decimal)
  } else {
    None
  }
  let exponent_index : Int? = if index < length &&
    (chars[index] == 'e' || chars[index] == 'E') {
    let exponent = index
    index += 1
    if index < length && (chars[index] == '+' || chars[index] == '-') {
      index += 1
    }
    let exponent_start = index
    while index < length && protocol_is_digit(chars[index]) {
      index += 1
    }
    if index == exponent_start {
      return Err(Malformed)
    }
    Some(exponent)
  } else {
    None
  }
  if index != length {
    return Err(Malformed)
  }
  match (decimal_index, exponent_index) {
    (None, None) => protocol_parse_int64_text(text)
    _ =>
      protocol_parse_int64_decimal(chars, start, decimal_index, exponent_index)
  }
}

///|
fn protocol_parse_int64_text(
  text : String,
) -> Result[Int64, ProtocolInt64NumberError] {
  let chars = text.to_array()
  let length = chars.length()
  if length == 0 {
    return Err(OutOfRange)
  }
  let negative = chars[0] == '-'
  let start = if negative { 1 } else { 0 }
  if start == length {
    return Err(OutOfRange)
  }
  let min_value : Int64 = -9223372036854775808L
  let max_value : Int64 = 9223372036854775807L
  let mut value : Int64 = 0L
  for index in start..<length {
    let digit = chars[index].to_int() - '0'
    if digit < 0 || digit > 9 {
      return Err(OutOfRange)
    }
    let digit64 = digit.to_int64()
    if negative {
      if value < min_value / 10L || (value == min_value / 10L && digit64 > 8L) {
        return Err(OutOfRange)
      }
      value = value * 10L - digit64
    } else {
      if value > max_value / 10L || (value == max_value / 10L && digit64 > 7L) {
        return Err(OutOfRange)
      }
      value = value * 10L + digit64
    }
  }
  Ok(value)
}

///|
fn protocol_parse_int64_decimal(
  chars : Array[Char],
  start : Int,
  decimal_index : Int?,
  exponent_index : Int?,
) -> Result[Int64, ProtocolInt64NumberError] {
  let mantissa_end = match exponent_index {
    Some(index) => index
    None => chars.length()
  }
  let fractional_digits = match decimal_index {
    Some(index) => mantissa_end - index - 1
    None => 0
  }
  let digits_builder = StringBuilder(size_hint=mantissa_end - start)
  let mut nonzero = false
  for index in start..<mantissa_end {
    let digit = chars[index]
    if digit != '.' {
      digits_builder.write_char(digit)
      if digit != '0' {
        nonzero = true
      }
    }
  }
  if !nonzero {
    return Ok(0L)
  }
  let digits = protocol_trim_leading_zeroes(digits_builder.to_string())
  let shift = match exponent_index {
    Some(index) => protocol_decimal_shift(chars, index + 1, chars.length())
    None => Finite(negative=false, magnitude=0)
  }
  let scale = match shift {
    Finite(negative=true, magnitude~) => -magnitude - fractional_digits
    Finite(negative=false, magnitude~) => magnitude - fractional_digits
    Huge(negative=true) => return Err(Fractional)
    Huge(negative=false) => return Err(OutOfRange)
  }
  if scale < 0 {
    let remove = -scale
    if remove >= digits.length() {
      return Err(Fractional)
    }
    let digit_chars = digits.to_array()
    for index in (digits.length() - remove)..<digits.length() {
      if digit_chars[index] != '0' {
        return Err(Fractional)
      }
    }
    let integer_digits = digits.sub(end=digits.length() - remove).to_owned()
    let sign = if start == 1 { "-" } else { "" }
    protocol_parse_int64_text(sign + integer_digits)
  } else {
    if digits.length() + scale > 19 {
      return Err(OutOfRange)
    }
    let zeros = "0".repeat(scale)
    let sign = if start == 1 { "-" } else { "" }
    protocol_parse_int64_text(sign + digits + zeros)
  }
}

///|
fn protocol_decode_wire_uint64(
  value : Json,
  path~ : String,
) -> UInt64 raise ProtocolDecodeError {
  match value {
    Number(number, repr~) => protocol_decode_number_uint64(number, repr, path~)
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
