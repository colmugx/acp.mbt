///|
/// The opaque typed payload handed from a v2 broker to the JSON-RPC owner
/// loop.  The loop stays responsible for ids, envelopes, correlation, and
/// transport; this value carries only an exact method and protocol-validated
/// params object.
priv struct ExperimentalV2BrokerPayload {
  method_name : String
  params : Json
}

///|
fn experimental_v2_broker_encode(
  method_name : String,
  encode : () -> Json raise ExperimentalV2DecodeError,
) -> ExperimentalV2BrokerPayload raise ExperimentalV2DecodeError {
  { method_name, params: encode() }
}

///|
/// Bind one immutable typed v2 Agent outbound context onto the engine-level
/// outbound channel.  A handler running inside the single owner loop can use
/// the returned context to issue reverse requests (`session/request_permission`,
/// `elicitation/create`) and stream notifications (`session/update`,
/// `elicitation/complete`) through the real engine: ids, envelopes,
/// correlation, and the serial writer queue stay engine-owned.
///
/// The context owns only immutable broker closures over the channel; it holds
/// no connection state, queue, task, or registry, and it introduces no second
/// loop.  Every failure is reported through the typed
/// `ExperimentalV2AgentContextError` mapping documented on the helpers below;
/// nothing is stringified, dropped, or converted into a success.
pub fn[C] experimental_v2_agent_context_over_channel(
  channel~ : @connection.RuntimeOutboundChannel[C],
) -> ExperimentalV2AgentContext {
  experimental_v2_agent_context(
    request_broker=async fn(request) {
      experimental_v2_broker_agent_request(channel, request)
    },
    notification_broker=async fn(notification) {
      experimental_v2_broker_agent_notification(channel, notification)
    },
  )
}

///|
/// One typed v2 Agent-to-Client request through the real single engine.  The
/// error mapping is total and documented case by case:
/// - local params validation failure -> `ContextBrokerFailure`: nothing was
///   submitted and the peer never saw a request, so it is neither a
///   cancellation nor a reply mismatch;
/// - cancellation of the submitter while parked -> `ContextCancelled`;
/// - any other channel `RuntimeError` (event or writer backpressure,
///   close settle, reader or writer failure) -> `ContextBrokerFailure`;
/// - JSON-RPC error reply carrying the ACP `RequestCancelled` code ->
///   `ContextCancelled`;
/// - JSON-RPC error reply carrying any other code ->
///   `ContextBrokerFailure`;
/// - successful reply whose result fails the method-typed decode ->
///   `ContextReplyMismatch`.
async fn[C] experimental_v2_broker_agent_request(
  channel : @connection.RuntimeOutboundChannel[C],
  request : ExperimentalV2AgentOutboundRequest,
) -> Result[ExperimentalV2AgentOutboundReply, ExperimentalV2AgentContextError] {
  let method_name = request.method_name()
  let payload = try
    experimental_v2_broker_agent_request_payload(request)
  catch {
    _ => None
  } noraise {
    payload => Some(payload)
  }
  match payload {
    None => Err(ContextBrokerFailure(method_name~))
    Some(payload) => {
      let response = try
        channel.submit_request(
          method_name=payload.method_name,
          params=payload.params,
        )
      catch {
        error =>
          Err(experimental_v2_broker_agent_exception(method_name~, error))
      } noraise {
        response => Ok(response)
      }
      match response {
        Err(error) => Err(error)
        Ok(response) =>
          experimental_v2_broker_agent_reply(request, response, method_name~)
      }
    }
  }
}

///|
/// One typed v2 Agent-to-Client notification through the real single engine.
/// The ack records enqueue into the serial writer queue only, matching the
/// channel contract; the mapping otherwise mirrors the request side: params
/// failure and every non-cancellation channel error are typed
/// `ContextBrokerFailure`, submitter cancellation while parked is typed
/// `ContextCancelled`.
async fn[C] experimental_v2_broker_agent_notification(
  channel : @connection.RuntimeOutboundChannel[C],
  notification : ExperimentalV2AgentOutboundNotification,
) -> Result[Unit, ExperimentalV2AgentContextError] {
  let method_name = notification.method_name()
  let payload = try
    experimental_v2_broker_agent_notification_payload(notification)
  catch {
    _ => None
  } noraise {
    payload => Some(payload)
  }
  match payload {
    None => Err(ContextBrokerFailure(method_name~))
    Some(payload) =>
      try {
        channel.submit_notification(
          method_name=payload.method_name,
          params=payload.params,
        )
        Ok(())
      } catch {
        error =>
          Err(experimental_v2_broker_agent_exception(method_name~, error))
      }
  }
}

///|
fn experimental_v2_broker_agent_request_payload(
  request : ExperimentalV2AgentOutboundRequest,
) -> ExperimentalV2BrokerPayload raise ExperimentalV2DecodeError {
  match request {
    RequestPermission(params) =>
      experimental_v2_broker_encode("session/request_permission", () => {
        experimental_v2_encode_request_permission_request(params)
      })
    ElicitationCreate(params) =>
      experimental_v2_broker_encode("elicitation/create", () => {
        experimental_v2_encode_elicitation_create_request(params)
      })
  }
}

///|
fn experimental_v2_broker_agent_notification_payload(
  notification : ExperimentalV2AgentOutboundNotification,
) -> ExperimentalV2BrokerPayload raise ExperimentalV2DecodeError {
  match notification {
    SessionUpdate(params) =>
      experimental_v2_broker_encode("session/update", () => {
        experimental_v2_encode_update_session_notification(params)
      })
    ElicitationComplete(params) =>
      experimental_v2_broker_encode("elicitation/complete", () => {
        experimental_v2_encode_complete_elicitation_notification(params)
      })
  }
}

///|
/// Classify one submitter-side channel failure.  Only cancellation while
/// parked becomes a typed cancel; every other `RuntimeError` kind keeps the
/// broker-failure category so no transport failure is masked as cancellation.
fn experimental_v2_broker_agent_exception(
  method_name~ : String,
  error : Error,
) -> ExperimentalV2AgentContextError {
  if @async.is_cancellation_error(error) {
    ContextCancelled(method_name~)
  } else {
    ContextBrokerFailure(method_name~)
  }
}

///|
/// Decode one engine reply for the request that owns its correlation slot.
/// The peer cannot select a result type by metadata: the request variant owns
/// the decoder, and an undecodable result is a typed mismatch rather than a
/// guess.  A JSON-RPC error reply never reaches the decoder; only its code
/// is classified.
fn experimental_v2_broker_agent_reply(
  request : ExperimentalV2AgentOutboundRequest,
  response : @jsonrpc.JsonRpcResponse,
  method_name~ : String,
) -> Result[ExperimentalV2AgentOutboundReply, ExperimentalV2AgentContextError] {
  match response {
    Success(success) => {
      let decoded = try
        experimental_v2_broker_decode_agent_reply(request, success.result)
      catch {
        _ => None
      } noraise {
        reply => Some(reply)
      }
      match decoded {
        None => Err(ContextReplyMismatch(method_name~))
        Some(reply) => Ok(reply)
      }
    }
    Error(failure) =>
      if failure.error.code == RequestCancelled {
        Err(ContextCancelled(method_name~))
      } else {
        Err(ContextBrokerFailure(method_name~))
      }
  }
}

///|
fn experimental_v2_broker_decode_agent_reply(
  request : ExperimentalV2AgentOutboundRequest,
  value : Json,
) -> ExperimentalV2AgentOutboundReply raise ExperimentalV2DecodeError {
  match request {
    RequestPermission(_) =>
      ReplyRequestPermission(
        experimental_v2_decode_request_permission_response(value),
      )
    ElicitationCreate(_) =>
      ReplyElicitationCreate(
        experimental_v2_decode_elicitation_create_response(value),
      )
  }
}

///|
/// Bind one immutable typed v2 Client connection facade onto the
/// engine-level outbound channel.  Forward requests (`initialize`,
/// `session/new`, ...) are submitted through the real single engine with the
/// total typed `ExperimentalV2ClientConnectionError` mapping documented on
/// the helpers below; ids, envelopes, correlation, and the serial writer
/// queue stay engine-owned.
///
/// The notification broker of the v2 facade is synchronous by contract, so it
/// submits through the channel's synchronous notification offer: no task
/// parks, and the one engine loop still owns the envelope, framing, and the
/// serial writer queue.  `Ok` therefore records only acceptance into the
/// engine's event queue; writer-offer and transport failures stay observable
/// at the connection level through the loop's fail-and-close semantics.
pub fn[C] experimental_v2_client_connection_over_channel(
  channel~ : @connection.RuntimeOutboundChannel[C],
) -> ExperimentalV2ClientConnection {
  experimental_v2_client_connection(
    request_broker=async fn(request) {
      experimental_v2_broker_client_request(channel, request)
    },
    notification_broker=notification => {
      experimental_v2_broker_client_notification(channel, notification)
    },
  )
}

///|
/// One typed v2 Client-to-Agent request through the real single engine.  The
/// error mapping is total and documented case by case:
/// - local params validation failure -> `BrokerFailure`: nothing was
///   submitted and the peer never saw a request;
/// - cancellation of the submitter while parked -> `Cancelled`;
/// - any other channel `RuntimeError` (backpressure, close settle, reader or
///   writer failure) -> `BrokerFailure`;
/// - JSON-RPC error reply carrying the ACP `RequestCancelled` code ->
///   `Cancelled`;
/// - JSON-RPC error reply carrying any other code -> `BrokerFailure`;
/// - successful reply whose result fails the method-typed decode ->
///   `ReplyMismatch`;
/// - a successful `initialize` reply whose offered protocol version is not
///   the pinned 2 -> `UnsupportedVersion`, the Client state machine's
///   terminal negotiation failure.
async fn[C] experimental_v2_broker_client_request(
  channel : @connection.RuntimeOutboundChannel[C],
  request : ExperimentalV2ClientForwardRequest,
) -> Result[
  ExperimentalV2ClientForwardReply,
  ExperimentalV2ClientConnectionError,
] {
  let method_name = request.method_name()
  let payload = try
    experimental_v2_broker_client_request_payload(request)
  catch {
    _ => None
  } noraise {
    payload => Some(payload)
  }
  match payload {
    None => Err(BrokerFailure(method_name~))
    Some(payload) => {
      let response = try
        channel.submit_request(
          method_name=payload.method_name,
          params=payload.params,
        )
      catch {
        error =>
          Err(experimental_v2_broker_client_exception(method_name~, error))
      } noraise {
        response => Ok(response)
      }
      match response {
        Err(error) => Err(error)
        Ok(response) =>
          experimental_v2_broker_client_reply(request, response, method_name~)
      }
    }
  }
}

///|
/// One typed v2 Client-to-Agent notification submitted synchronously through
/// the real single engine.  The error mapping is total and documented case by
/// case:
/// - local params validation failure -> `BrokerFailure`: nothing was
///   submitted and the peer never saw a notification;
/// - `EventQueueClosed` (including any submission attempted after the engine
///   began shutting down) -> `Unavailable`: no live connection remains that
///   could admit the notification;
/// - `EventQueueBackpressure` -> `BrokerFailure`: the connection is live but
///   its event-queue capacity is exhausted;
/// - any other channel-side failure of the closed sync error set keeps the
///   broker-failure category, mirroring the request side, so no transport
///   failure is masked as cancellation or availability.
fn[C] experimental_v2_broker_client_notification(
  channel : @connection.RuntimeOutboundChannel[C],
  notification : ExperimentalV2ClientForwardNotification,
) -> Result[Unit, ExperimentalV2ClientConnectionError] {
  let method_name = notification.method_name()
  let payload = try
    experimental_v2_broker_client_notification_payload(notification)
  catch {
    _ => None
  } noraise {
    payload => Some(payload)
  }
  match payload {
    None => Err(BrokerFailure(method_name~))
    Some(payload) =>
      match
        channel.submit_notification_sync(
          method_name=payload.method_name,
          params=payload.params,
        ) {
        Ok(_) => Ok(())
        Err(EventQueueClosed) => Err(Unavailable(method_name~))
        Err(EventQueueBackpressure(_)) | Err(_) =>
          Err(BrokerFailure(method_name~))
      }
  }
}

///|
fn experimental_v2_broker_client_request_payload(
  request : ExperimentalV2ClientForwardRequest,
) -> ExperimentalV2BrokerPayload raise ExperimentalV2DecodeError {
  match request {
    Initialize(params) =>
      experimental_v2_broker_encode("initialize", () => {
        experimental_v2_encode_initialize_params(params)
      })
    AuthLogin(params) =>
      experimental_v2_broker_encode("auth/login", () => {
        experimental_v2_encode_login_params(params)
      })
    AuthLogout(params) =>
      experimental_v2_broker_encode("auth/logout", () => {
        experimental_v2_encode_logout_params(params)
      })
    SessionNew(params) =>
      experimental_v2_broker_encode("session/new", () => {
        experimental_v2_encode_new_session_params(params)
      })
    SessionList(params) =>
      experimental_v2_broker_encode("session/list", () => {
        experimental_v2_encode_list_sessions_params(params)
      })
    SessionResume(params) =>
      experimental_v2_broker_encode("session/resume", () => {
        experimental_v2_encode_resume_session_params(params)
      })
    SessionDelete(params) =>
      experimental_v2_broker_encode("session/delete", () => {
        experimental_v2_encode_delete_session_params(params)
      })
    SessionClose(params) =>
      experimental_v2_broker_encode("session/close", () => {
        experimental_v2_encode_close_session_params(params)
      })
    SessionPrompt(params) =>
      experimental_v2_broker_encode("session/prompt", () => {
        experimental_v2_encode_prompt_params(params)
      })
    SessionSetConfigOption(params) =>
      experimental_v2_broker_encode("session/set_config_option", () => {
        experimental_v2_encode_set_config_option(params)
      })
  }
}

///|
fn experimental_v2_broker_client_notification_payload(
  notification : ExperimentalV2ClientForwardNotification,
) -> ExperimentalV2BrokerPayload raise ExperimentalV2DecodeError {
  match notification {
    SessionCancel(params) =>
      experimental_v2_broker_encode("session/cancel", () => {
        experimental_v2_encode_cancel_session_params(params)
      })
    CancelRequest(request_id) =>
      experimental_v2_broker_encode("$/cancel_request", () => {
        Json::object({
          "requestId": experimental_v2_encode_request_id(request_id),
        })
      })
  }
}

///|
/// Classify one submitter-side channel failure.  Only cancellation while
/// parked becomes a typed cancel; every other `RuntimeError` kind keeps the
/// broker-failure category so no transport failure is masked as cancellation.
fn experimental_v2_broker_client_exception(
  method_name~ : String,
  error : Error,
) -> ExperimentalV2ClientConnectionError {
  if @async.is_cancellation_error(error) {
    Cancelled(method_name~)
  } else {
    BrokerFailure(method_name~)
  }
}

///|
/// Decode one engine reply for the request that owns its correlation slot.
/// The request variant owns the decoder; an undecodable result is reported as
/// a typed mismatch instead of guessing a reply variant, and a JSON-RPC error
/// reply is classified by code alone.  The `initialize` reply additionally
/// enforces the pinned protocol version: any other offered version is the
/// Client state machine's terminal `UnsupportedVersion` failure, because v2
/// has no downgrade path.
fn experimental_v2_broker_client_reply(
  request : ExperimentalV2ClientForwardRequest,
  response : @jsonrpc.JsonRpcResponse,
  method_name~ : String,
) -> Result[
  ExperimentalV2ClientForwardReply,
  ExperimentalV2ClientConnectionError,
] {
  match response {
    Success(success) => {
      let decoded = try
        experimental_v2_broker_decode_client_reply(request, success.result)
      catch {
        _ => None
      } noraise {
        reply => Some(reply)
      }
      match decoded {
        None => Err(ReplyMismatch(method_name~))
        Some(ReplyInitialize(result)) =>
          if result.protocol_version == experimental_v2_protocol_version {
            Ok(ReplyInitialize(result))
          } else {
            Err(
              UnsupportedVersion(method_name~, offered=result.protocol_version),
            )
          }
        Some(reply) => Ok(reply)
      }
    }
    Error(failure) =>
      if failure.error.code == RequestCancelled {
        Err(Cancelled(method_name~))
      } else {
        Err(BrokerFailure(method_name~))
      }
  }
}

///|
fn experimental_v2_broker_decode_client_reply(
  request : ExperimentalV2ClientForwardRequest,
  value : Json,
) -> ExperimentalV2ClientForwardReply raise ExperimentalV2DecodeError {
  match request {
    Initialize(_) =>
      ReplyInitialize(experimental_v2_decode_initialize_result(value))
    AuthLogin(_) => ReplyAuthLogin(experimental_v2_decode_login_result(value))
    AuthLogout(_) =>
      ReplyAuthLogout(experimental_v2_decode_logout_result(value))
    SessionNew(_) =>
      ReplyNewSession(experimental_v2_decode_new_session_result(value))
    SessionList(_) =>
      ReplyListSessions(experimental_v2_decode_list_sessions_result(value))
    SessionResume(_) =>
      ReplyResumeSession(experimental_v2_decode_resume_session_result(value))
    SessionDelete(_) =>
      ReplyDeleteSession(experimental_v2_decode_delete_session_result(value))
    SessionClose(_) =>
      ReplyCloseSession(experimental_v2_decode_close_session_result(value))
    SessionPrompt(_) => ReplyPrompt(experimental_v2_decode_prompt_result(value))
    SessionSetConfigOption(_) =>
      ReplySetConfigOption(
        experimental_v2_decode_set_config_option_result(value),
      )
  }
}
