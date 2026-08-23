///|
/// The typed Agent-to-Client requests a v2 Agent context can issue.
pub(all) enum ExperimentalV2AgentOutboundRequest {
  RequestPermission(ExperimentalV2RequestPermissionRequest)
  ElicitationCreate(ExperimentalV2ElicitationCreateRequest)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2AgentOutboundRequest::method_name(
  self : ExperimentalV2AgentOutboundRequest,
) -> String {
  match self {
    RequestPermission(_) => "session/request_permission"
    ElicitationCreate(_) => "elicitation/create"
  }
}

///|
/// The closed set of typed results a v2 Client can return to an Agent.
pub(all) enum ExperimentalV2AgentOutboundReply {
  ReplyRequestPermission(ExperimentalV2RequestPermissionResponse)
  ReplyElicitationCreate(ExperimentalV2ElicitationCreateResponse)
} derive(Eq, Debug)

///|
/// The typed Agent-to-Client notifications a v2 Agent context can issue.
pub(all) enum ExperimentalV2AgentOutboundNotification {
  SessionUpdate(ExperimentalV2UpdateSessionNotification)
  ElicitationComplete(ExperimentalV2CompleteElicitationNotification)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2AgentOutboundNotification::method_name(
  self : ExperimentalV2AgentOutboundNotification,
) -> String {
  match self {
    SessionUpdate(_) => "session/update"
    ElicitationComplete(_) => "elicitation/complete"
  }
}

///|
/// Failures crossing a v2 Agent-to-Client context port.  Brokers or runtime
/// adapters construct these from negotiated capability gates and transport
/// cancellation; application code never handles untyped JSON here.
pub(all) suberror ExperimentalV2AgentContextError {
  ContextUnavailable(method_name~ : String)
  ContextCancelled(method_name~ : String)
  ContextBrokerFailure(method_name~ : String)
  ContextReplyMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
/// The request-side composition seam: a one-shot typed broker, not a queue or
/// a mutable registry.
pub type ExperimentalV2AgentRequestBroker = async (
  ExperimentalV2AgentOutboundRequest,
) -> Result[ExperimentalV2AgentOutboundReply, ExperimentalV2AgentContextError]

///|
/// The notification-side composition seam.  Notifications carry no response
/// value, so success is `Unit`.
pub type ExperimentalV2AgentNotificationBroker = async (
  ExperimentalV2AgentOutboundNotification,
) -> Result[Unit, ExperimentalV2AgentContextError]

///|
/// Opaque typed outbound context supplied to one v2 Agent invocation.  It
/// owns only the two immutable broker closures; no connection state, queue,
/// task, or raw protocol value crosses this boundary.
pub struct ExperimentalV2AgentContext {
  request_broker : ExperimentalV2AgentRequestBroker
  notification_broker : ExperimentalV2AgentNotificationBroker
}

///|
/// Construct one immutable context around caller-owned typed transport ports.
pub fn experimental_v2_agent_context(
  request_broker~ : ExperimentalV2AgentRequestBroker,
  notification_broker~ : ExperimentalV2AgentNotificationBroker,
) -> ExperimentalV2AgentContext {
  { request_broker, notification_broker }
}

///|
fn experimental_v2_agent_context_exception(
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
async fn experimental_v2_agent_context_request(
  context : ExperimentalV2AgentContext,
  request : ExperimentalV2AgentOutboundRequest,
) -> ExperimentalV2AgentOutboundReply raise ExperimentalV2AgentContextError {
  let method_name = request.method_name()
  let result = try (context.request_broker)(request) catch {
    error => Err(experimental_v2_agent_context_exception(method_name~, error))
  } noraise {
    value => value
  }
  match result {
    Ok(reply) => reply
    Err(error) => raise error
  }
}

///|
async fn experimental_v2_agent_context_notification(
  context : ExperimentalV2AgentContext,
  notification : ExperimentalV2AgentOutboundNotification,
) -> Unit raise ExperimentalV2AgentContextError {
  let method_name = notification.method_name()
  let result = try (context.notification_broker)(notification) catch {
    error => Err(experimental_v2_agent_context_exception(method_name~, error))
  } noraise {
    value => value
  }
  match result {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
/// Ask the Client for permission to execute one operation.
pub async fn ExperimentalV2AgentContext::request_permission(
  self : ExperimentalV2AgentContext,
  request : ExperimentalV2RequestPermissionRequest,
) -> ExperimentalV2RequestPermissionResponse raise ExperimentalV2AgentContextError {
  match
    experimental_v2_agent_context_request(self, RequestPermission(request)) {
    ReplyRequestPermission(reply) => reply
    _ => raise ContextReplyMismatch(method_name="session/request_permission")
  }
}

///|
/// Create either form- or URL-mode elicitation through the stable union.
pub async fn ExperimentalV2AgentContext::elicitation_create(
  self : ExperimentalV2AgentContext,
  request : ExperimentalV2ElicitationCreateRequest,
) -> ExperimentalV2ElicitationCreateResponse raise ExperimentalV2AgentContextError {
  match
    experimental_v2_agent_context_request(self, ElicitationCreate(request)) {
    ReplyElicitationCreate(reply) => reply
    _ => raise ContextReplyMismatch(method_name="elicitation/create")
  }
}

///|
/// Deliver one typed session update notification.  No response is
/// synthesized.
pub async fn ExperimentalV2AgentContext::session_update(
  self : ExperimentalV2AgentContext,
  notification : ExperimentalV2UpdateSessionNotification,
) -> Unit raise ExperimentalV2AgentContextError {
  experimental_v2_agent_context_notification(self, SessionUpdate(notification))
}

///|
/// Deliver one typed elicitation completion notification.  No response is
/// synthesized.
pub async fn ExperimentalV2AgentContext::elicitation_complete(
  self : ExperimentalV2AgentContext,
  notification : ExperimentalV2CompleteElicitationNotification,
) -> Unit raise ExperimentalV2AgentContextError {
  experimental_v2_agent_context_notification(
    self,
    ElicitationComplete(notification),
  )
}

///|
/// Fail-fast request broker: every call answers with a typed
/// `ContextUnavailable`.  Real channel wiring lands with the v2 runtime
/// composition; this broker keeps the typed surface testable end to end.
// Deliberately synchronous body: a broker that never parks still satisfies
// the async broker type.
#warnings("-unused_async")
pub fn experimental_v2_agent_fail_fast_request_broker() -> ExperimentalV2AgentRequestBroker {
  async fn(request) {
    Err(ContextUnavailable(method_name=request.method_name()))
  }
}

///|
/// Fail-fast notification broker: every call answers with a typed
/// `ContextUnavailable`.
#warnings("-unused_async")
pub fn experimental_v2_agent_fail_fast_notification_broker() -> ExperimentalV2AgentNotificationBroker {
  async fn(notification) {
    Err(ContextUnavailable(method_name=notification.method_name()))
  }
}

///|
/// One context wired entirely from the fail-fast brokers.  Handlers running
/// under it can exercise the typed outbound surface, and every attempt fails
/// fast with the method name visible.
pub fn experimental_v2_agent_fail_fast_context() -> ExperimentalV2AgentContext {
  experimental_v2_agent_context(
    request_broker=experimental_v2_agent_fail_fast_request_broker(),
    notification_broker=experimental_v2_agent_fail_fast_notification_broker(),
  )
}
