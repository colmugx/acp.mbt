///|
/// Return the signed integer represented by an error code.
pub fn JsonRpcErrorCode::to_int(self : JsonRpcErrorCode) -> Int {
  match self {
    ParseError => -32700
    InvalidRequest => -32600
    MethodNotFound => -32601
    InvalidParams => -32602
    InternalError => -32603
    RequestCancelled => -32800
    AuthRequired => -32000
    ResourceNotFound => -32002
    Custom(code) => code
  }
}

///|
/// Decode a signed integer error code, retaining unknown values as `Custom`.
pub fn JsonRpcErrorCode::from_int(code : Int) -> JsonRpcErrorCode {
  match code {
    -32700 => ParseError
    -32600 => InvalidRequest
    -32601 => MethodNotFound
    -32602 => InvalidParams
    -32603 => InternalError
    -32800 => RequestCancelled
    -32000 => AuthRequired
    -32002 => ResourceNotFound
    _ => Custom(code)
  }
}

///|
/// Validate the range required by the JSON-RPC error-code field.
fn validate_error_code(code : JsonRpcErrorCode) -> Unit raise JsonRpcCodecError {
  let value = code.to_int()
  if value < -2147483648 || value > 2147483647 {
    raise InvalidError(reason="error.code must be a signed 32-bit integer")
  }
}

///|
/// The standard message associated with a known code.
pub fn JsonRpcErrorCode::default_message(self : JsonRpcErrorCode) -> String {
  match self {
    ParseError => "Parse error"
    InvalidRequest => "Invalid Request"
    MethodNotFound => "Method not found"
    InvalidParams => "Invalid params"
    InternalError => "Internal error"
    RequestCancelled => "Request cancelled"
    AuthRequired => "Authentication required"
    ResourceNotFound => "Resource not found"
    Custom(_) => "Application error"
  }
}

///|
/// Construct an error object with an explicit message and optional data.
pub fn JsonRpcError::new(
  code~ : JsonRpcErrorCode,
  message~ : String,
  data? : Json,
) -> JsonRpcError {
  { code, message, data, }
}

///|
/// Construct a parse-error object using the standard message.
pub fn JsonRpcError::parse_error(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::ParseError
  { code, message: code.default_message(), data, }
}

///|
/// Construct an invalid-request object using the standard message.
pub fn JsonRpcError::invalid_request(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::InvalidRequest
  { code, message: code.default_message(), data, }
}

///|
/// Construct a method-not-found object using the standard message.
pub fn JsonRpcError::method_not_found(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::MethodNotFound
  { code, message: code.default_message(), data, }
}

///|
/// Construct an invalid-params object using the standard message.
pub fn JsonRpcError::invalid_params(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::InvalidParams
  { code, message: code.default_message(), data, }
}

///|
/// Construct an internal-error object using the standard message.
pub fn JsonRpcError::internal_error(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::InternalError
  { code, message: code.default_message(), data, }
}

///|
/// Construct a request-cancelled object using the standard message.
pub fn JsonRpcError::request_cancelled(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::RequestCancelled
  { code, message: code.default_message(), data, }
}

///|
/// Construct an authentication-required object using the standard message.
pub fn JsonRpcError::auth_required(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::AuthRequired
  { code, message: code.default_message(), data, }
}

///|
/// Construct a resource-not-found object using the standard message.
pub fn JsonRpcError::resource_not_found(data? : Json) -> JsonRpcError {
  let code = JsonRpcErrorCode::ResourceNotFound
  { code, message: code.default_message(), data, }
}
