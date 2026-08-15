///|
using @agent {type AgentContext, type AgentContextError, agent_context}

///|
using @client {
  type ClientConnection,
  type ClientConnectionError,
  client_connection,
}

///|
using @connection {type RuntimeOutboundChannel}

///|
using @jsonrpc {type JsonRpcResponse}

///|
/// Static `actual` discriminator recorded when a successful reply cannot be
/// decoded into the reply variant owned by the submitted request.  It is a
/// closed static category; no peer payload or raw error text crosses this
/// boundary.
const BrokerChannelMalformedResult : String = "malformed_result"

///|
/// Bind one immutable typed Agent outbound context onto the engine-level
/// outbound channel.  A handler running inside the single owner loop can use
/// the returned context to issue reverse requests (`session/request_permission`,
/// `fs/*`, `terminal/*`, `elicitation/create`) and stream notifications
/// (`session/update`, `elicitation/complete`) through the real engine: ids,
/// envelopes, correlation, and the serial writer queue stay engine-owned.
///
/// The context owns only immutable broker closures over the channel; it holds
/// no connection state, queue, task, or registry, and it introduces no second
/// loop.  Every failure is reported through the typed `AgentContextError`
/// mapping documented on the helpers below; nothing is stringified, dropped,
/// or converted into a success.
pub fn[C] agent_context_over_channel(
  channel~ : RuntimeOutboundChannel[C],
) -> AgentContext {
  agent_context(
    request_broker=async fn(request) {
      broker_channel_agent_request(channel, request)
    },
    notification_broker=async fn(notification) {
      broker_channel_agent_notification(channel, notification)
    },
  )
}

///|
/// One typed Agent-to-Client request through the real single engine.  The
/// error mapping is total and documented case by case:
/// - local params validation failure -> `AgentContextBrokerFailure`: nothing
///   was submitted and the peer never saw a request, so it is neither a
///   cancellation nor a reply mismatch;
/// - cancellation of the submitter while parked -> `AgentContextCancelled`;
/// - any other channel `RuntimeError` (event or writer backpressure, close
///   settle, reader or writer failure) -> `AgentContextBrokerFailure`;
/// - JSON-RPC error reply carrying the ACP `RequestCancelled` code ->
///   `AgentContextCancelled`;
/// - JSON-RPC error reply carrying any other code ->
///   `AgentContextBrokerFailure`;
/// - successful reply whose result fails the method-typed decode ->
///   `AgentContextReplyMismatch`.
async fn[C] broker_channel_agent_request(
  channel : RuntimeOutboundChannel[C],
  request : ClientRequest,
) -> Result[AgentOutboundReply, AgentContextError] {
  let method_name = request.method_name()
  let payload = Ok(broker_client_request_payload(request)) catch {
    _ => Err(AgentContextError::AgentContextBrokerFailure(method_name~))
  }
  match payload {
    Err(error) => Err(error)
    Ok(payload) => {
      let response = Ok(
        channel.submit_request(
          method_name=payload.method_name,
          params=payload.params,
        ),
      ) catch {
        error => Err(broker_channel_agent_exception(method_name~, error))
      }
      match response {
        Err(error) => Err(error)
        Ok(response) =>
          broker_channel_agent_reply(request, response, method_name~)
      }
    }
  }
}

///|
/// One typed Agent-to-Client notification through the real single engine.
/// The ack records enqueue into the serial writer queue only, matching the
/// channel contract; the mapping otherwise mirrors the request side:
/// params failure and every non-cancellation channel error are typed
/// `AgentContextBrokerFailure`, submitter cancellation while parked is typed
/// `AgentContextCancelled`.
async fn[C] broker_channel_agent_notification(
  channel : RuntimeOutboundChannel[C],
  notification : ClientNotification,
) -> Result[Unit, AgentContextError] {
  let method_name = notification.method_name()
  let payload = Ok(broker_client_notification_payload(notification)) catch {
    _ => Err(AgentContextError::AgentContextBrokerFailure(method_name~))
  }
  match payload {
    Err(error) => Err(error)
    Ok(payload) =>
      try {
        channel.submit_notification(
          method_name=payload.method_name,
          params=payload.params,
        )
        Ok(())
      } catch {
        error => Err(broker_channel_agent_exception(method_name~, error))
      }
  }
}

///|
/// Classify one submitter-side channel failure.  Only cancellation while
/// parked becomes a typed cancel; every other `RuntimeError` kind keeps the
/// broker-failure category so no transport failure is masked as cancellation.
fn broker_channel_agent_exception(
  method_name~ : String,
  error : Error,
) -> AgentContextError {
  if @async.is_cancellation_error(error) {
    AgentContextCancelled(method_name~)
  } else {
    AgentContextBrokerFailure(method_name~)
  }
}

///|
/// Decode one engine reply for the request that owns its correlation slot.
/// The peer cannot select a result type by metadata: the request variant
/// owns the decoder, and an undecodable result is a typed mismatch rather
/// than a guess.  A JSON-RPC error reply never reaches the decoder; only its
/// code is classified.
fn broker_channel_agent_reply(
  request : ClientRequest,
  response : JsonRpcResponse,
  method_name~ : String,
) -> Result[AgentOutboundReply, AgentContextError] {
  match response {
    Success(success) =>
      Ok(broker_decode_client_request_result(request, success.result)) catch {
        _ => Err(AgentContextReplyMismatch(method_name~))
      }
    Error(failure) =>
      if failure.error.code == RequestCancelled {
        Err(AgentContextCancelled(method_name~))
      } else {
        Err(AgentContextBrokerFailure(method_name~))
      }
  }
}

///|
/// Bind one immutable typed Client connection facade onto the engine-level
/// outbound channel.  Forward requests (`initialize`, `session/new`, ...)
/// are submitted through the real single engine with the total typed
/// `ClientConnectionError` mapping documented on the helpers below; ids,
/// envelopes, correlation, and the serial writer queue stay engine-owned.
///
/// The notification broker of the stable `ClientConnection` facade is
/// synchronous by contract, while every engine submission must park until
/// the single loop acknowledges it.  No established non-blocking bridge
/// exists in this codebase, so the notification side fails fast with a typed
/// `ClientConnectionUnavailable` carrying the method name: the notification
/// is never silently dropped and no blocking bridge is invented here.
/// Wiring Client notifications is an open item for the client runtime work
/// order.
pub fn[C] client_connection_over_channel(
  channel~ : RuntimeOutboundChannel[C],
) -> ClientConnection {
  client_connection(
    request_broker=async fn(request) {
      broker_channel_client_request(channel, request)
    },
    notification_broker=notification => {
      Err(ClientConnectionUnavailable(method_name=notification.method_name()))
    },
  )
}

///|
/// One typed Client-to-Agent request through the real single engine.  The
/// error mapping is total and documented case by case:
/// - local params validation failure -> `ClientConnectionBrokerFailure`:
///   nothing was submitted and the peer never saw a request;
/// - cancellation of the submitter while parked -> `ClientConnectionCancelled`;
/// - any other channel `RuntimeError` (backpressure, close settle, reader or
///   writer failure) -> `ClientConnectionBrokerFailure`;
/// - JSON-RPC error reply carrying the ACP `RequestCancelled` code ->
///   `ClientConnectionCancelled`;
/// - JSON-RPC error reply carrying any other code ->
///   `ClientConnectionBrokerFailure`;
/// - successful reply whose result fails the method-typed decode ->
///   `ClientConnectionReplyMismatch` with the static `malformed_result`
///   discriminator, because the facade's mismatch error carries an explicit
///   `expected`/`actual` pair while no real method name exists for an
///   undecodable result.
async fn[C] broker_channel_client_request(
  channel : RuntimeOutboundChannel[C],
  request : AgentRequest,
) -> Result[ClientReply, ClientConnectionError] {
  let method_name = request.method_name()
  let payload = Ok(broker_agent_request_payload(request)) catch {
    _ => Err(ClientConnectionError::ClientConnectionBrokerFailure(method_name~))
  }
  match payload {
    Err(error) => Err(error)
    Ok(payload) => {
      let response = Ok(
        channel.submit_request(
          method_name=payload.method_name,
          params=payload.params,
        ),
      ) catch {
        error => Err(broker_channel_client_exception(method_name~, error))
      }
      match response {
        Err(error) => Err(error)
        Ok(response) =>
          broker_channel_client_reply(request, response, method_name~)
      }
    }
  }
}

///|
/// Classify one submitter-side channel failure.  Only cancellation while
/// parked becomes a typed cancel; every other `RuntimeError` kind keeps the
/// broker-failure category so no transport failure is masked as cancellation.
fn broker_channel_client_exception(
  method_name~ : String,
  error : Error,
) -> ClientConnectionError {
  if @async.is_cancellation_error(error) {
    ClientConnectionCancelled(method_name~)
  } else {
    ClientConnectionBrokerFailure(method_name~)
  }
}

///|
/// Decode one engine reply for the request that owns its correlation slot.
/// The request variant owns the decoder; an undecodable result is reported
/// as a typed mismatch instead of guessing a reply variant, and a JSON-RPC
/// error reply is classified by code alone.
fn broker_channel_client_reply(
  request : AgentRequest,
  response : JsonRpcResponse,
  method_name~ : String,
) -> Result[ClientReply, ClientConnectionError] {
  match response {
    Success(success) =>
      Ok(broker_decode_agent_request_result(request, success.result)) catch {
        _ =>
          Err(
            ClientConnectionReplyMismatch(
              method_name~,
              expected=method_name,
              actual=BrokerChannelMalformedResult,
            ),
          )
      }
    Error(failure) =>
      if failure.error.code == RequestCancelled {
        Err(ClientConnectionCancelled(method_name~))
      } else {
        Err(ClientConnectionBrokerFailure(method_name~))
      }
  }
}
