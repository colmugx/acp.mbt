///|
/// Decode one complete JSON-RPC message from JSON text.
///
/// This function parses exactly one JSON value and then validates its complete
/// envelope.  It does not implement line framing; callers that use stdio must
/// split frames before calling it.
pub fn jsonrpc_decode(
  source : String,
) -> JsonRpcMessage raise JsonRpcCodecError {
  let value = @json.parse(source) catch {
    error => raise ParseError(message=error.to_string())
  }
  jsonrpc_decode_json(value)
}

///|
/// Decode one JSON-RPC message from an already parsed JSON value.
pub fn jsonrpc_decode_json(
  value : Json,
) -> JsonRpcMessage raise JsonRpcCodecError {
  match value {
    Object(fields) => decode_message_object(fields)
    _ => raise InvalidRequest(reason="JSON-RPC envelope must be an object")
  }
}

///|
/// Encode one JSON-RPC message as compact JSON text.
///
/// The returned text contains no framing newline.  Newline-delimited stdio is
/// a runtime concern and must append its own delimiter.
pub fn jsonrpc_encode(
  message : JsonRpcMessage,
) -> String raise JsonRpcCodecError {
  jsonrpc_to_json(message).stringify()
}

///|
/// Encode one JSON-RPC message as a JSON value.
pub fn jsonrpc_to_json(
  message : JsonRpcMessage,
) -> Json raise JsonRpcCodecError {
  match message {
    Request(request) => request_to_json(request)
    Notification(notification) => notification_to_json(notification)
    Response(response) => response_to_json(response)
  }
}

///|
fn request_to_json(request : JsonRpcRequest) -> Json raise JsonRpcCodecError {
  validate_params(request.params)
  let fields : Map[String, Json] = Map([])
  fields["jsonrpc"] = Json::string(JSON_RPC_VERSION)
  fields["id"] = encode_request_id(request.id)
  fields["method"] = Json::string(request.method_name)
  match request.params {
    None => ()
    Some(params) => fields["params"] = params
  }
  Json::object(fields)
}

///|
fn notification_to_json(
  notification : JsonRpcNotification,
) -> Json raise JsonRpcCodecError {
  validate_params(notification.params)
  let fields : Map[String, Json] = Map([])
  fields["jsonrpc"] = Json::string(JSON_RPC_VERSION)
  fields["method"] = Json::string(notification.method_name)
  match notification.params {
    None => ()
    Some(params) => fields["params"] = params
  }
  Json::object(fields)
}

///|
fn response_to_json(response : JsonRpcResponse) -> Json raise JsonRpcCodecError {
  let fields : Map[String, Json] = Map([])
  fields["jsonrpc"] = Json::string(JSON_RPC_VERSION)
  match response {
    Success(success) => {
      fields["id"] = encode_request_id(success.id)
      fields["result"] = success.result
    }
    Error(failure) => {
      fields["id"] = encode_id(failure.id)
      fields["error"] = error_to_json(failure.error)
    }
  }
  Json::object(fields)
}

///|
fn error_to_json(error : JsonRpcError) -> Json raise JsonRpcCodecError {
  let fields : Map[String, Json] = Map([])
  validate_error_code(error.code)
  let code = error.code.to_int()
  fields["code"] = Json::number(code.to_double(), repr=code.to_string())
  fields["message"] = Json::string(error.message)
  match error.data {
    None => ()
    Some(data) => fields["data"] = data
  }
  Json::object(fields)
}

///|
fn encode_id(id : JsonRpcId) -> Json {
  match id {
    String(value) => Json::string(value)
    Number(value) => Json::number(value.to_double(), repr=value.to_string())
    Null => Json::null()
  }
}

///|
fn encode_request_id(id : RequestId) -> Json {
  match id {
    String(value) => Json::string(value)
    Number(value) => Json::number(value.to_double(), repr=value.to_string())
    Null => Json::null()
  }
}

///|
fn validate_params(params : Json?) -> Unit raise JsonRpcCodecError {
  match params {
    None => ()
    Some(value) =>
      match value {
        Array(_) | Object(_) | Null => ()
        _ =>
          raise InvalidParams(reason="params must be an object, array, or null")
      }
  }
}

///|
fn decode_message_object(
  fields : Map[String, Json],
) -> JsonRpcMessage raise JsonRpcCodecError {
  decode_version(fields)
  let has_id = fields.contains("id")
  let has_method = fields.contains("method")
  let has_params = fields.contains("params")
  let has_result = fields.contains("result")
  let has_error = fields.contains("error")
  if has_method {
    if has_result || has_error {
      raise InvalidRequest(
        reason="method envelope cannot contain result or error",
      )
    }
    let method_name = decode_method_name(fields.get("method"), path="method")
    let params = decode_params(fields.get("params"))
    if has_id {
      let id = decode_request_id(fields.get("id"))
      Request({ id, method_name, params, })
    } else {
      Notification({ method_name, params, })
    }
  } else if has_result || has_error {
    if has_params {
      raise InvalidRequest(reason="response envelope cannot contain params")
    }
    if !has_id {
      raise MissingField(path="id")
    }
    if has_result && has_error {
      raise ConflictingFields(path="result,error")
    }
    if has_result {
      let id = decode_request_id(fields.get("id"))
      let result = match fields.get("result") {
        Some(value) => value
        None => raise MissingField(path="result")
      }
      Response(Success({ id, result, }))
    } else {
      let id = decode_id(fields.get("id"))
      let error_value = match fields.get("error") {
        Some(value) => value
        None => raise MissingField(path="error")
      }
      let error = decode_error(error_value)
      Response(Error({ id, error, }))
    }
  } else {
    raise InvalidRequest(reason="message must contain method or result/error")
  }
}

///|
fn decode_version(fields : Map[String, Json]) -> Unit raise JsonRpcCodecError {
  let value = match fields.get("jsonrpc") {
    Some(value) => value
    None => raise MissingField(path="jsonrpc")
  }
  match value {
    String(version) =>
      if version != JSON_RPC_VERSION {
        raise InvalidField(path="jsonrpc", reason="must be exactly \"2.0\"")
      }
    _ => raise InvalidField(path="jsonrpc", reason="must be a string")
  }
}

///|
fn decode_method_name(
  value : Json?,
  path~ : String,
) -> String raise JsonRpcCodecError {
  match value {
    Some(String(method_name)) => method_name
    Some(_) => raise InvalidField(path~, reason="must be a string")
    None => raise MissingField(path~)
  }
}

///|
fn decode_params(value : Json?) -> Json? raise JsonRpcCodecError {
  match value {
    None => None
    Some(params) =>
      match params {
        Array(_) | Object(_) | Null => Some(params)
        _ =>
          raise InvalidParams(reason="params must be an object, array, or null")
      }
  }
}

///|
fn decode_request_id(value : Json?) -> RequestId raise JsonRpcCodecError {
  match value {
    None => raise MissingField(path="id")
    Some(String(value)) => String(value)
    Some(Number(value, repr~)) => Number(decode_request_integer(value, repr))
    Some(Null) => Null
    Some(_) =>
      raise InvalidId(reason="request id must be a string, integer, or null")
  }
}

///|
fn decode_id(value : Json?) -> JsonRpcId raise JsonRpcCodecError {
  match value {
    None => raise MissingField(path="id")
    Some(String(value)) => String(value)
    Some(Null) => Null
    Some(Number(value, repr~)) => Number(decode_request_integer(value, repr))
    Some(_) =>
      raise InvalidId(reason="response id must be a string, integer, or null")
  }
}

///|
priv enum JsonRpcInt64NumberError {
  Malformed
  NonFinite
  Fractional
  OutOfRange
  PrecisionUnavailable
}

///|
/// Decode an integer-valued JSON number without trusting a rounded `Double`.
///
/// The core JSON parser retains the original number text in `repr` whenever a
/// literal cannot be represented by a finite, lossless `Double`.  For those
/// values this function parses the retained decimal text directly.  A finite
/// number without `repr` is accepted only inside the exact binary-integer
/// range; larger values are rejected rather than silently rounded.
fn jsonrpc_int64_number(
  value : Double,
  repr : String?,
) -> Result[Int64, JsonRpcInt64NumberError] {
  match repr {
    Some(text) => jsonrpc_parse_int64_repr(text)
    None =>
      if value.is_nan() || value.is_inf() {
        Err(NonFinite)
      } else if value != value.floor() {
        Err(Fractional)
      } else if value.abs() > 9007199254740991.0 {
        Err(PrecisionUnavailable)
      } else {
        Ok(value.to_int64())
      }
  }
}

///|
fn jsonrpc_parse_int64_repr(
  text : String,
) -> Result[Int64, JsonRpcInt64NumberError] {
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
    if index < length && jsonrpc_is_digit(chars[index]) {
      return Err(Malformed)
    }
  } else if jsonrpc_is_digit(chars[index]) {
    index += 1
    while index < length && jsonrpc_is_digit(chars[index]) {
      index += 1
    }
  } else {
    return Err(Malformed)
  }
  let decimal_index : Int? = if index < length && chars[index] == '.' {
    let decimal = index
    index += 1
    let fraction_start = index
    while index < length && jsonrpc_is_digit(chars[index]) {
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
    while index < length && jsonrpc_is_digit(chars[index]) {
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
    (None, None) => jsonrpc_parse_int64_text(text)
    _ =>
      jsonrpc_parse_int64_decimal(chars, start, decimal_index, exponent_index)
  }
}

///|
fn jsonrpc_is_digit(value : Char) -> Bool {
  let digit = value.to_int() - '0'
  digit >= 0 && digit <= 9
}

///|
fn jsonrpc_parse_int64_text(
  text : String,
) -> Result[Int64, JsonRpcInt64NumberError] {
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
priv enum JsonRpcDecimalShift {
  Finite(negative~ : Bool, magnitude~ : Int)
  Huge(negative~ : Bool)
}

///|
fn jsonrpc_decimal_shift(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> JsonRpcDecimalShift {
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
fn jsonrpc_trim_leading_zeroes(text : String) -> String {
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
fn jsonrpc_parse_int64_decimal(
  chars : Array[Char],
  start : Int,
  decimal_index : Int?,
  exponent_index : Int?,
) -> Result[Int64, JsonRpcInt64NumberError] {
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
  let digits = jsonrpc_trim_leading_zeroes(digits_builder.to_string())
  let shift = match exponent_index {
    Some(index) => jsonrpc_decimal_shift(chars, index + 1, chars.length())
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
    jsonrpc_parse_int64_text(sign + integer_digits)
  } else {
    if digits.length() + scale > 19 {
      return Err(OutOfRange)
    }
    let zeros = "0".repeat(scale)
    let sign = if start == 1 { "-" } else { "" }
    jsonrpc_parse_int64_text(sign + digits + zeros)
  }
}

///|
fn jsonrpc_int64_error_reason(error : JsonRpcInt64NumberError) -> String {
  match error {
    Malformed => "must be a valid JSON number"
    NonFinite => "must be a finite integer"
    Fractional => "must be an integer"
    OutOfRange => "must fit in signed 64-bit integer"
    PrecisionUnavailable =>
      "must be an exactly represented signed 64-bit integer"
  }
}

///|
fn decode_request_integer(
  value : Double,
  repr : String?,
) -> Int64 raise JsonRpcCodecError {
  match jsonrpc_int64_number(value, repr) {
    Ok(integer) => integer
    Err(error) => raise InvalidId(reason=jsonrpc_int64_error_reason(error))
  }
}

///|
pub fn jsonrpc_decode_int64(
  value : Double,
  repr : String?,
  path~ : String,
) -> Int64 raise JsonRpcCodecError {
  match jsonrpc_int64_number(value, repr) {
    Ok(integer) => integer
    Err(error) =>
      raise InvalidInteger(path~, reason=jsonrpc_int64_error_reason(error))
  }
}

///|
fn decode_integer(value : Double) -> Int raise JsonRpcCodecError {
  if value.is_nan() || value.is_inf() {
    raise InvalidId(reason="number must be finite")
  }
  if value != value.floor() {
    raise InvalidId(reason="number must be an integer")
  }
  if value < -2147483648.0 || value > 2147483647.0 {
    raise InvalidId(reason="integer is outside the Int32 range")
  }
  value.to_int()
}

///|
fn decode_error(value : Json) -> JsonRpcError raise JsonRpcCodecError {
  match value {
    Object(fields) => {
      let code_value = match fields.get("code") {
        Some(value) => value
        None => raise InvalidError(reason="error.code is required")
      }
      let code = match code_value {
        Number(value, ..) =>
          decode_integer(value) catch {
            _ =>
              raise InvalidError(reason="error.code must be a finite integer")
          }
        _ => raise InvalidError(reason="error.code must be a number")
      }
      let message = match fields.get("message") {
        Some(String(value)) => value
        Some(_) => raise InvalidError(reason="error.message must be a string")
        None => raise InvalidError(reason="error.message is required")
      }
      let data = fields.get("data")
      { code: JsonRpcErrorCode::from_int(code), message, data, }
    }
    _ => raise InvalidError(reason="error must be an object")
  }
}
