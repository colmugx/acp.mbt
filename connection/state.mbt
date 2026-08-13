///|
using @jsonrpc {
  type RequestId,
  type JsonRpcId,
  type JsonRpcRequest,
  type JsonRpcNotification,
  type JsonRpcResponse,
  type JsonRpcError,
  type JsonRpcMessage,
}

///|
/// The lifecycle of a pure connection reducer.
enum ConnectionPhase {
  ConnectionOpen
  ConnectionClosed(reason~ : String)
} derive(Eq, Debug)

///|
/// A request initiated by the local endpoint and awaiting its peer.
struct PendingOutbound {
  id : RequestId
  method_name : String
  cancel_requested : Bool
} derive(Eq, Debug)

///|
/// A request initiated by the peer and awaiting local handler completion.
struct PendingInbound {
  id : RequestId
  method_name : String
  cancel_requested : Bool
} derive(Eq, Debug)

///|
/// All mutable-looking connection data is carried explicitly in this value.
/// The reducer never mutates an input state's arrays; each transition copies
/// and updates its own arrays before returning a new state.
struct ConnectionState {
  phase : ConnectionPhase
  outbound : Array[PendingOutbound]
  inbound : Array[PendingInbound]
  settled_outbound : Array[RequestId]
  settled_inbound : Array[RequestId]
} derive(Eq, Debug)

///|
/// The initial open state.
#warnings("-unused_value")
fn connection_state() -> ConnectionState {
  {
    phase: ConnectionOpen,
    outbound: [],
    inbound: [],
    settled_outbound: [],
    settled_inbound: [],
  }
}

///|
/// Events are data only.  Effects are represented by `ConnectionCommand` in
/// the reducer output and are interpreted by a runtime outside this package.
#warnings("-unused_constructor")
enum ConnectionEvent {
  OutgoingRequest(JsonRpcRequest)
  OutgoingNotification(JsonRpcNotification)
  IncomingRequest(JsonRpcRequest)
  IncomingNotification(JsonRpcNotification)
  IncomingResponse(JsonRpcResponse)
  IncomingCompleted(id~ : RequestId, result~ : Json)
  IncomingFailed(id~ : RequestId, error~ : JsonRpcError)
  CancelOutbound(id~ : RequestId)
  CancelInbound(id~ : RequestId)
  Close(reason~ : String)
  Eof
} derive(Eq, Debug)

///|
/// Intent-only commands.  No command owns an async task, queue, callback, or
/// dependency environment.
enum ConnectionCommand {
  WriteMessage(JsonRpcMessage)
  DispatchRequest(JsonRpcRequest)
  DispatchNotification(JsonRpcNotification)
  CompleteOutbound(id~ : RequestId, response~ : JsonRpcResponse)
  FailOutbound(id~ : RequestId, reason~ : String)
  FailInbound(id~ : RequestId, reason~ : String, cancelled~ : Bool)
  CancelOutboundTask(id~ : RequestId)
  CancelInboundTask(id~ : RequestId)
  Trace(message~ : String)
} derive(Eq, Debug)

///|
/// A pure transition result.
struct ConnectionStep {
  state : ConnectionState
  commands : Array[ConnectionCommand]
} derive(Eq, Debug)

///|
/// Reducer failures are structured and never converted into silent defaults.
suberror ConnectionError {
  Closed(reason~ : String)
  AlreadyClosed(reason~ : String)
  DuplicateOutbound(id~ : RequestId)
  DuplicateInbound(id~ : RequestId)
  UnknownResponse(id~ : RequestId)
  DuplicateResponse(id~ : RequestId)
  LateResponse(id~ : RequestId)
  InvalidCancellation(reason~ : String)
  UnknownCancellation(id~ : RequestId)
  DuplicateCancellation(id~ : RequestId)
  UnknownInboundCompletion(id~ : RequestId)
  LateInboundCompletion(id~ : RequestId)
} derive(Eq, Debug)
