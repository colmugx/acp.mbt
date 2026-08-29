///|
type JsonRpcRequest = @jsonrpc.JsonRpcRequest

///|
type JsonRpcNotification = @jsonrpc.JsonRpcNotification

///|
type JsonRpcResponse = @jsonrpc.JsonRpcResponse

///|
type JsonRpcError = @jsonrpc.JsonRpcError

///|
/// Failures at the native runtime boundary.
///
/// These errors deliberately carry only failure categories.  Peer payloads,
/// prompts, files, tokens, and environment values never enter a trace or an
/// error string produced by the runtime.
pub(all) suberror RuntimeError {
  InvalidOptions
  ReaderFailed
  ReaderEmptyChunk
  EventQueueClosed
  EventQueueBackpressure(limit~ : Int)
  WriterQueueClosed
  WriterQueueBackpressure(limit~ : Int)
  WriterFailed
  FramingFailed
  JsonRpcDecodeFailed
  JsonRpcEncodeFailed
  ReducerFailed
  TaskControlMissing
  TaskRequestMismatch
  HandlerFailed
  NotificationFailed
  ResponseHandlerFailed
  OutboundCancelUnavailable
  OutboundCancelFailed
  OutboundCompletionFailed
  CloseCleanupFailed(primary_kind~ : String, cleanup_phase~ : String)
}

///|
/// A redacted runtime trace record.  Only routing metadata and a static
/// failure category are exposed to the sink.
pub(all) struct RuntimeTraceEvent {
  direction : String
  phase : String
  request_id : String
  method_name : String
  error_kind : String
}

///|
/// Caller-owned asynchronous input seam. `None` is the only EOF signal.
pub(all) struct RuntimeReaderPort {
  read : async (Int) -> Bytes?
}

///|
/// Caller-owned asynchronous output seam. Each call receives one complete
/// newline-delimited frame and must either write all bytes or raise.
pub(all) struct RuntimeWriterPort {
  write : async (Bytes) -> Unit
}

///|
pub type RuntimeOutboundFailureHandler = async (
  @jsonrpc.RequestId,
  RuntimeOutboundFailure,
) -> Unit

///|
pub type RuntimeCancelOutboundHandler = async (@jsonrpc.RequestId) -> Unit

///|
/// Closed, finite categories for a locally initiated request completion.
/// Arbitrary close strings never cross this boundary.
pub(all) enum RuntimeOutboundFailureKind {
  Protocol
  Framing
  Reader
  Writer
  Handler
  Notification
  EndOfInput
  EventQueue
  Runtime
} derive(Eq, Debug)

///|
/// Result returned by an inbound request handler. A handler failure is raised
/// through the async port and becomes `RuntimeError::HandlerFailed`.
pub(all) enum RuntimeHandlerResult {
  HandlerSuccess(Json)
  HandlerError(JsonRpcError)
}

///|
/// Protocol dispatch seams. They are values rather than globals so tests and
/// composition roots can inject memory or faulting implementations.
pub(all) struct RuntimeHandlerPort {
  request : async (JsonRpcRequest) -> RuntimeHandlerResult
  notification : async (JsonRpcNotification) -> Unit
  response : async (JsonRpcResponse) -> Unit
  /// Called exactly once when a locally initiated pending request is failed
  /// by connection shutdown. The reason is a static reducer close category.
  outbound_failure : RuntimeOutboundFailureHandler?
}

///|
/// Typed completion data for a locally initiated request. The reason is
/// intentionally a category, never a peer payload or arbitrary exception.
pub(all) struct RuntimeOutboundFailure {
  reason : RuntimeOutboundFailureKind
}

///|
/// All per-connection runtime dependencies.
pub(all) struct RuntimePorts {
  reader : RuntimeReaderPort
  writer : RuntimeWriterPort
  handlers : RuntimeHandlerPort
  /// The owner of outbound requests supplies cancellation. Inbound task
  /// controls are runtime-owned and must never be used for this direction.
  cancel_outbound : RuntimeCancelOutboundHandler?
  trace : (RuntimeTraceEvent) -> Unit
}

///|
/// Native runtime bounds. The event and writer queues are intentionally
/// bounded so backpressure is observable instead of becoming unbounded heap
/// growth.
pub(all) struct RuntimeOptions {
  max_frame_bytes : Int
  queue_capacity : Int
  read_chunk_bytes : Int
}

///|
pub fn runtime_default_options() -> RuntimeOptions {
  { max_frame_bytes: 1024 * 1024, queue_capacity: 64, read_chunk_bytes: 4096, }
}

///|
pub fn runtime_validate_options(
  options : RuntimeOptions,
) -> Unit raise RuntimeError {
  if options.max_frame_bytes <= 0 ||
    options.queue_capacity <= 0 ||
    options.read_chunk_bytes <= 0 {
    raise InvalidOptions
  }
}

///|
pub fn runtime_trace_event(
  direction : String,
  phase : String,
  request_id : String,
  method_name : String,
  error_kind : String,
) -> RuntimeTraceEvent {
  { direction, phase, request_id, method_name, error_kind, }
}

///|
pub fn runtime_request_id_text(id : @jsonrpc.RequestId) -> String {
  match id {
    String(value) => value
    Number(value) => value.to_string()
    Null => "null"
  }
}
