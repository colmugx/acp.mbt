///|
/// The JSON-RPC protocol version implemented by this package.
pub const JSON_RPC_VERSION : String = "2.0"

///|
/// A JSON-RPC response envelope identifier.
///
/// Response errors may carry null when a request identifier cannot be
/// determined.  Correlatable request and success identifiers use `RequestId`,
/// which also permits null in the pinned ACP v1 schema.
pub(all) enum JsonRpcId {
  String(String)
  Number(Int64)
  Null
} derive(Eq, Debug)

///|
pub extend JsonRpcId with Eq::{not_equal, equal}

///|
pub extend JsonRpcId with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A request identifier that can be correlated to a request.
///
/// ACP's pinned v1 schema permits JSON null as a request identifier.  It is a
/// real identifier value, distinct from an omitted `id` field (which denotes a
/// notification), and therefore remains in the typed correlation domain.
pub(all) enum RequestId {
  String(String)
  Number(Int64)
  Null
} derive(Eq, Debug)

///|
pub extend RequestId with Eq::{not_equal, equal}

///|
pub extend RequestId with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The conventional name for a JSON-RPC response identifier.
pub type ResponseId = JsonRpcId

///|
/// A JSON-RPC request envelope.
pub struct JsonRpcRequest {
  id : RequestId
  method_name : String
  params : Json?
} derive(Eq, Debug)

///|
pub extend JsonRpcRequest with Eq::{not_equal, equal}

///|
pub extend JsonRpcRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A JSON-RPC notification envelope.
pub struct JsonRpcNotification {
  method_name : String
  params : Json?
} derive(Eq, Debug)

///|
pub extend JsonRpcNotification with Eq::{not_equal, equal}

///|
pub extend JsonRpcNotification with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A successful JSON-RPC response envelope.
pub struct JsonRpcSuccess {
  id : RequestId
  result : Json
} derive(Eq, Debug)

///|
pub extend JsonRpcSuccess with Eq::{not_equal, equal}

///|
pub extend JsonRpcSuccess with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An error JSON-RPC response envelope.
pub struct JsonRpcFailure {
  id : JsonRpcId
  error : JsonRpcError
} derive(Eq, Debug)

///|
pub extend JsonRpcFailure with Eq::{not_equal, equal}

///|
pub extend JsonRpcFailure with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The two mutually exclusive JSON-RPC response forms.
pub(all) enum JsonRpcResponse {
  Success(JsonRpcSuccess)
  Error(JsonRpcFailure)
} derive(Eq, Debug)

///|
pub extend JsonRpcResponse with Eq::{not_equal, equal}

///|
pub extend JsonRpcResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A decoded JSON-RPC message.
pub(all) enum JsonRpcMessage {
  Request(JsonRpcRequest)
  Notification(JsonRpcNotification)
  Response(JsonRpcResponse)
} derive(Eq, Debug)

///|
pub extend JsonRpcMessage with Eq::{not_equal, equal}

///|
pub extend JsonRpcMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Standard JSON-RPC and ACP error codes.
///
/// `Custom` preserves an otherwise unknown signed 32-bit wire code instead of
/// mapping it to a success or a known error.
pub(all) enum JsonRpcErrorCode {
  ParseError
  InvalidRequest
  MethodNotFound
  InvalidParams
  InternalError
  RequestCancelled
  AuthRequired
  ResourceNotFound
  Custom(Int32)
} derive(Eq, Debug)

///|
pub extend JsonRpcErrorCode with Eq::{not_equal, equal}

///|
pub extend JsonRpcErrorCode with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The structured error object carried by an error response.
pub struct JsonRpcError {
  code : JsonRpcErrorCode
  message : String
  data : Json?
} derive(Eq, Debug)

///|
pub extend JsonRpcError with Eq::{not_equal, equal}

///|
pub extend JsonRpcError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Errors raised while parsing or validating a JSON-RPC envelope.
///
/// These are local codec errors.  They are intentionally separate from
/// `JsonRpcError`, which is a valid wire error object that can be sent to a
/// peer.
pub(all) suberror JsonRpcCodecError {
  ParseError(message~ : String)
  InvalidRequest(reason~ : String)
  InvalidId(reason~ : String)
  InvalidParams(reason~ : String)
  InvalidError(reason~ : String)
  UnknownField(path~ : String)
  MissingField(path~ : String)
  ConflictingFields(path~ : String)
  InvalidField(path~ : String, reason~ : String)
  InvalidInteger(path~ : String, reason~ : String)
} derive(Eq, Debug)

///|
pub extend JsonRpcCodecError with Eq::{not_equal, equal}

///|
pub extend JsonRpcCodecError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Construct a request envelope.  `params` is omitted when it is `None`.
pub fn JsonRpcRequest::new(
  id~ : RequestId,
  method_name~ : String,
  params? : Json,
) -> JsonRpcRequest raise JsonRpcCodecError {
  validate_params(params)
  { id, method_name, params, }
}

///|
/// Construct a notification envelope.  `params` is omitted when it is `None`.
pub fn JsonRpcNotification::new(
  method_name~ : String,
  params? : Json,
) -> JsonRpcNotification raise JsonRpcCodecError {
  validate_params(params)
  { method_name, params, }
}

///|
/// Construct a successful response envelope.
pub fn JsonRpcResponse::success(
  id~ : RequestId,
  result~ : Json,
) -> JsonRpcResponse {
  Success({ id, result, })
}

///|
/// Construct an error response envelope.
pub fn JsonRpcResponse::error(
  id~ : JsonRpcId,
  error~ : JsonRpcError,
) -> JsonRpcResponse {
  Error({ id, error, })
}

///|
/// Construct a JSON-RPC message from a request envelope.
pub fn JsonRpcMessage::request(request : JsonRpcRequest) -> JsonRpcMessage {
  Request(request)
}

///|
/// Construct a JSON-RPC message from a notification envelope.
pub fn JsonRpcMessage::notification(
  notification : JsonRpcNotification,
) -> JsonRpcMessage {
  Notification(notification)
}

///|
/// Construct a JSON-RPC message from a response envelope.
pub fn JsonRpcMessage::response(response : JsonRpcResponse) -> JsonRpcMessage {
  Response(response)
}
