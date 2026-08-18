///|
/// Canonical checked failures returned by application-owned handlers and typed
/// outbound ports on either endpoint side.
///
/// Every payload is a host-authored, already-sanitized string meant for the
/// client to display: the adapter forwards it verbatim onto the JSON-RPC error
/// (`message` plus `data`), so a user can read — and share with a developer —
/// what actually happened. Handlers must not put secrets, raw payloads, or
/// stack traces in these strings.
pub(all) suberror HandlerError {
  Application(message~ : String)
  /// The request's parameters are invalid (unknown id, wrong value shape).
  /// Maps to JSON-RPC `-32602` so clients distinguish user mistakes from
  /// internal failures instead of showing a scary internal error.
  InvalidParams(message~ : String)
  Cancelled
  UnavailableOperation(method_name~ : String)
} derive(Eq, Debug)

///|
/// Failures found while composing an immutable Agent endpoint.
pub(all) suberror AgentCompositionError {
  InvalidImplementation(reason~ : String)
  MissingRequiredService(service_name~ : String)
  InvalidAuthMethods(reason~ : String)
  ConflictingSupport(reason~ : String)
} derive(Eq, Debug)

///|
/// Failures found while composing an immutable Client endpoint.
pub(all) suberror ClientCompositionError {
  InvalidImplementation(reason~ : String)
  MissingRequiredService(service_name~ : String)
  ConflictingSupport(reason~ : String)
} derive(Eq, Debug)
