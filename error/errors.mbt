///|
/// Canonical checked failures returned by application-owned handlers and typed
/// outbound ports on either endpoint side.
pub(all) suberror HandlerError {
  Application(message~ : String)
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
