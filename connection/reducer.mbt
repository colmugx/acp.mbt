///|
fn connection_require_open(
  state : ConnectionState,
) -> Unit raise ConnectionError {
  match state.phase {
    ConnectionOpen => ()
    ConnectionClosed(reason~) => raise Closed(reason~)
  }
}

///|
fn connection_outbound_index(
  pending : Array[PendingOutbound],
  id : RequestId,
) -> Int? {
  for index, value in pending.iter2() {
    if value.id == id {
      return Some(index)
    }
  }
  None
}

///|
fn connection_inbound_index(
  pending : Array[PendingInbound],
  id : RequestId,
) -> Int? {
  for index, value in pending.iter2() {
    if value.id == id {
      return Some(index)
    }
  }
  None
}

///|
fn connection_response_id(response : JsonRpcResponse) -> RequestId {
  match response {
    Success(success) => success.id
    Error(failure) =>
      match failure.id {
        String(value) => String(value)
        Number(value) => Number(value)
        Null => Null
      }
  }
}

///|
fn connection_response_id_json(id : RequestId) -> JsonRpcId {
  match id {
    String(value) => String(value)
    Number(value) => Number(value)
    Null => Null
  }
}

///|
fn connection_request_id_json(id : RequestId) -> Json {
  match id {
    String(value) => Json::string(value)
    Number(value) => Json::number(value.to_double(), repr=value.to_string())
    Null => Json::null()
  }
}

///|
fn connection_cancel_notification(
  id : RequestId,
) -> JsonRpcNotification raise ConnectionError {
  let fields : Map[String, Json] = Map([])
  fields["requestId"] = connection_request_id_json(id)
  JsonRpcNotification::new(
    method_name="$/cancel_request",
    params=Json::object(fields),
  ) catch {
    _ =>
      raise InvalidCancellation(
        reason="failed to construct cancellation notification",
      )
  }
}

///|
fn connection_cancel_id(params : Json?) -> RequestId raise ConnectionError {
  match params {
    Some(Object(fields)) => {
      if fields.length() != 1 || !fields.contains("requestId") {
        raise InvalidCancellation(
          reason="$/cancel_request.params must contain only requestId",
        )
      }
      let request_id = match fields.get("requestId") {
        Some(value) => value
        None =>
          raise InvalidCancellation(
            reason="$/cancel_request.params.requestId is required",
          )
      }
      let envelope : Map[String, Json] = Map([])
      envelope["jsonrpc"] = Json::string("2.0")
      envelope["id"] = request_id
      envelope["method"] = Json::string("$/cancel_request")
      let decoded = @jsonrpc.jsonrpc_decode_json(Json::object(envelope)) catch {
        _ =>
          raise InvalidCancellation(
            reason="$/cancel_request.params.requestId must be a string, number, or null",
          )
      }
      match decoded {
        Request(request) => request.id
        _ =>
          raise InvalidCancellation(
            reason="$/cancel_request.params.requestId must be a string, number, or null",
          )
      }
    }
    Some(_) =>
      raise InvalidCancellation(
        reason="$/cancel_request.params must be an object",
      )
    None =>
      raise InvalidCancellation(reason="$/cancel_request.params is required")
  }
}

///|
fn connection_reduce_outgoing_request(
  state : ConnectionState,
  request : JsonRpcRequest,
) -> ConnectionStep raise ConnectionError {
  connection_require_open(state)
  if connection_outbound_index(state.outbound, request.id) is Some(_) ||
    state.settled_outbound.contains(request.id) {
    raise DuplicateOutbound(id=request.id)
  }
  let outbound = Array::copy(state.outbound)
  outbound.push({
    id: request.id,
    method_name: request.method_name,
    cancel_requested: false,
  })
  {
    state: { ..state, outbound, },
    commands: [WriteMessage(JsonRpcMessage::request(request))],
  }
}

///|
fn connection_reduce_outgoing_notification(
  state : ConnectionState,
  notification : JsonRpcNotification,
) -> ConnectionStep raise ConnectionError {
  connection_require_open(state)
  {
    state,
    commands: [WriteMessage(JsonRpcMessage::notification(notification))],
  }
}

///|
fn connection_reduce_incoming_request(
  state : ConnectionState,
  request : JsonRpcRequest,
) -> ConnectionStep raise ConnectionError {
  connection_require_open(state)
  if connection_inbound_index(state.inbound, request.id) is Some(_) ||
    state.settled_inbound.contains(request.id) {
    raise DuplicateInbound(id=request.id)
  }
  let inbound = Array::copy(state.inbound)
  inbound.push({
    id: request.id,
    method_name: request.method_name,
    cancel_requested: false,
  })
  { state: { ..state, inbound, }, commands: [DispatchRequest(request)], }
}

///|
fn connection_reduce_incoming_notification(
  state : ConnectionState,
  notification : JsonRpcNotification,
) -> ConnectionStep raise ConnectionError {
  connection_require_open(state)
  if notification.method_name == "$/cancel_request" {
    let id = connection_cancel_id(notification.params)
    connection_reduce_wire_cancel_inbound(state, id)
  } else {
    { state, commands: [DispatchNotification(notification)], }
  }
}

///|
/// Apply one inbound wire `$/cancel_request` with best-effort semantics.
///
/// ACP v1 makes the cancellation best-effort: the receiver MAY cancel the
/// matching activity and the only MUST is that the original request
/// eventually receives its response; the contract is silent on ids that were
/// never seen or already settled. Real ACP clients routinely send cancels
/// that race with an already-delivered response, so a well-formed cancel of
/// a non-live id is a traced no-op — no state change, no response, no close —
/// and the connection keeps serving traffic:
/// - never-seen id -> `CancelUnknownRequest`;
/// - already-settled id (the settle-then-cancel race) -> `CancelAlreadySettled`;
/// - live pending already carrying a cancel mark (a repeated best-effort
///   cancel) -> `CancelAlreadyCancelled`.
///
/// A cancel for a genuinely live pending keeps the exact live semantics of
/// `connection_reduce_cancel_inbound` (typed cancel mark plus the native
/// `CancelInboundTask` intent). Malformed cancellation params still fail
/// fast in `connection_cancel_id`: an invalid frame is a protocol violation,
/// not a benign race. The local `CancelInbound` event is deliberately NOT
/// tolerated: a local caller cancels engine-owned state, so an unknown,
/// settled, or repeated id there remains a fail-fast programming error.
fn connection_reduce_wire_cancel_inbound(
  state : ConnectionState,
  id : RequestId,
) -> ConnectionStep raise ConnectionError {
  match connection_inbound_index(state.inbound, id) {
    Some(index) =>
      if state.inbound[index].cancel_requested {
        {
          state,
          commands: [TraceCancelIgnored(id~, reason=CancelAlreadyCancelled)],
        }
      } else {
        connection_reduce_cancel_inbound(state, id)
      }
    None =>
      if state.settled_inbound.contains(id) {
        {
          state,
          commands: [TraceCancelIgnored(id~, reason=CancelAlreadySettled)],
        }
      } else {
        {
          state,
          commands: [TraceCancelIgnored(id~, reason=CancelUnknownRequest)],
        }
      }
  }
}

///|
fn connection_reduce_incoming_response(
  state : ConnectionState,
  response : JsonRpcResponse,
) -> ConnectionStep raise ConnectionError {
  let id = connection_response_id(response)
  match connection_outbound_index(state.outbound, id) {
    Some(index) => {
      let outbound = Array::copy(state.outbound)
      let _ = outbound.remove(index)
      let settled_outbound = Array::copy(state.settled_outbound)
      settled_outbound.push(id)
      {
        state: { ..state, outbound, settled_outbound, },
        commands: [CompleteOutbound(id~, response~)],
      }
    }
    None =>
      match state.phase {
        ConnectionClosed(_) => {
          if state.settled_outbound.contains(id) {
            raise LateResponse(id~)
          }
          raise UnknownResponse(id~)
        }
        ConnectionOpen => {
          if state.settled_outbound.contains(id) {
            raise DuplicateResponse(id~)
          }
          raise UnknownResponse(id~)
        }
      }
  }
}

///|
fn connection_reduce_cancel_outbound(
  state : ConnectionState,
  id : RequestId,
) -> ConnectionStep raise ConnectionError {
  connection_require_open(state)
  match connection_outbound_index(state.outbound, id) {
    None => {
      if state.settled_outbound.contains(id) {
        raise DuplicateCancellation(id~)
      }
      raise UnknownCancellation(id~)
    }
    Some(index) => {
      let outbound = Array::copy(state.outbound)
      let _ = outbound.remove(index)
      let settled_outbound = Array::copy(state.settled_outbound)
      settled_outbound.push(id)
      let notification = connection_cancel_notification(id)
      {
        state: { ..state, outbound, settled_outbound, },
        commands: [
          WriteMessage(JsonRpcMessage::notification(notification)),
          CancelOutboundTask(id~),
        ],
      }
    }
  }
}

///|
fn connection_reduce_cancel_inbound(
  state : ConnectionState,
  id : RequestId,
) -> ConnectionStep raise ConnectionError {
  connection_require_open(state)
  match connection_inbound_index(state.inbound, id) {
    None => {
      if state.settled_inbound.contains(id) {
        raise DuplicateCancellation(id~)
      }
      raise UnknownCancellation(id~)
    }
    Some(index) => {
      let inbound = Array::copy(state.inbound)
      let pending = inbound[index]
      if pending.cancel_requested {
        raise DuplicateCancellation(id~)
      }
      inbound[index] = { ..pending, cancel_requested: true, }
      { state: { ..state, inbound, }, commands: [CancelInboundTask(id~)], }
    }
  }
}

///|
fn connection_reduce_incoming_completed(
  state : ConnectionState,
  id : RequestId,
  result : Json,
) -> ConnectionStep raise ConnectionError {
  match connection_inbound_index(state.inbound, id) {
    None => {
      if state.settled_inbound.contains(id) {
        raise LateInboundCompletion(id~)
      }
      raise UnknownInboundCompletion(id~)
    }
    Some(index) => {
      let inbound = Array::copy(state.inbound)
      let pending = inbound.remove(index)
      let settled_inbound = Array::copy(state.settled_inbound)
      settled_inbound.push(id)
      let response = if pending.cancel_requested {
        JsonRpcResponse::error(
          id=connection_response_id_json(id),
          error=JsonRpcError::request_cancelled(),
        )
      } else {
        JsonRpcResponse::success(id~, result~)
      }
      {
        state: { ..state, inbound, settled_inbound, },
        commands: [WriteMessage(JsonRpcMessage::response(response))],
      }
    }
  }
}

///|
fn connection_reduce_incoming_failed(
  state : ConnectionState,
  id : RequestId,
  error : JsonRpcError,
) -> ConnectionStep raise ConnectionError {
  match connection_inbound_index(state.inbound, id) {
    None => {
      if state.settled_inbound.contains(id) {
        raise LateInboundCompletion(id~)
      }
      raise UnknownInboundCompletion(id~)
    }
    Some(index) => {
      let inbound = Array::copy(state.inbound)
      let pending = inbound.remove(index)
      let settled_inbound = Array::copy(state.settled_inbound)
      settled_inbound.push(id)
      let response = if pending.cancel_requested {
        JsonRpcResponse::error(
          id=connection_response_id_json(id),
          error=JsonRpcError::request_cancelled(),
        )
      } else {
        JsonRpcResponse::error(id=connection_response_id_json(id), error~)
      }
      {
        state: { ..state, inbound, settled_inbound, },
        commands: [WriteMessage(JsonRpcMessage::response(response))],
      }
    }
  }
}

///|
fn connection_reduce_close(
  state : ConnectionState,
  reason : String,
) -> ConnectionStep raise ConnectionError {
  match state.phase {
    ConnectionClosed(reason=previous_reason) =>
      raise AlreadyClosed(reason=previous_reason)
    ConnectionOpen => {
      let commands : Array[ConnectionCommand] = []
      let settled_outbound = Array::copy(state.settled_outbound)
      for pending in state.outbound {
        settled_outbound.push(pending.id)
        commands.push(FailOutbound(id=pending.id, reason~))
      }
      let settled_inbound = Array::copy(state.settled_inbound)
      for pending in state.inbound {
        settled_inbound.push(pending.id)
        commands.push(
          FailInbound(
            id=pending.id,
            reason~,
            cancelled=pending.cancel_requested,
          ),
        )
      }
      commands.push(Trace(message="connection closed"))
      {
        state: {
          phase: ConnectionClosed(reason~),
          outbound: [],
          inbound: [],
          settled_outbound,
          settled_inbound,
        },
        commands,
      }
    }
  }
}

///|
/// Apply one event without performing any transport or runtime effect.
#warnings("-unused_value")
fn connection_reduce(
  state : ConnectionState,
  event : ConnectionEvent,
) -> ConnectionStep raise ConnectionError {
  match event {
    OutgoingRequest(request) =>
      connection_reduce_outgoing_request(state, request)
    OutgoingNotification(notification) =>
      connection_reduce_outgoing_notification(state, notification)
    IncomingRequest(request) =>
      connection_reduce_incoming_request(state, request)
    IncomingNotification(notification) =>
      connection_reduce_incoming_notification(state, notification)
    IncomingResponse(response) =>
      connection_reduce_incoming_response(state, response)
    IncomingCompleted(id~, result~) =>
      connection_reduce_incoming_completed(state, id, result)
    IncomingFailed(id~, error~) =>
      connection_reduce_incoming_failed(state, id, error)
    CancelOutbound(id~) => connection_reduce_cancel_outbound(state, id)
    CancelInbound(id~) => connection_reduce_cancel_inbound(state, id)
    Close(reason~) => connection_reduce_close(state, reason)
    Eof => connection_reduce_close(state, "eof")
  }
}
