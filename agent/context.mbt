///|
/// The closed set of typed results that a Client can return to an Agent.
///
/// Constructor names are deliberately prefixed so this facade cannot be
/// confused with the corresponding wire request or endpoint constructors.
pub(all) enum AgentOutboundReply {
  AgentReplyRequestPermission(RequestPermissionResponse)
  AgentReplyFsReadTextFile(ReadTextFileResult)
  AgentReplyFsWriteTextFile(WriteTextFileResult)
  AgentReplyTerminalCreate(TerminalCreateResult)
  AgentReplyTerminalOutput(TerminalOutputResult)
  AgentReplyTerminalWaitForExit(TerminalWaitForExitResult)
  AgentReplyTerminalKill(TerminalKillResult)
  AgentReplyTerminalRelease(TerminalReleaseResult)
  AgentReplyElicitationCreate(ElicitationCreateResult)
} derive(Eq, Debug)

///|
/// Failures crossing an Agent-to-Client context port.  Runtime adapters may
/// construct these values from negotiated capability gates or transport
/// cancellation, while application code never handles untyped JSON here.
pub(all) suberror AgentContextError {
  AgentContextUnavailable(method_name~ : String)
  AgentContextCancelled(method_name~ : String)
  AgentContextBrokerFailure(method_name~ : String)
  AgentContextReplyMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
/// The request-side composition seam.  It is a one-shot broker, not a queue
/// or a mutable registry; connection state remains owned by the runtime.
pub type AgentContextRequestBroker = async (ClientRequest) -> Result[
  AgentOutboundReply,
  AgentContextError,
]

///|
/// The notification-side composition seam.  Notifications have no response
/// value, so success is represented only by `Unit`.
pub type AgentContextNotificationBroker = async (ClientNotification) -> Result[
  Unit,
  AgentContextError,
]

///|
/// Opaque typed outbound context supplied to one Agent invocation.  It owns
/// the two immutable broker closures plus one read-only `client_info`
/// accessor naming the connecting Client implementation; it contains no
/// connection state, queue, task, global registry, or raw protocol value.
pub struct AgentContext {
  request_broker : AgentContextRequestBroker
  notification_broker : AgentContextNotificationBroker
  client_info : () -> ProtocolNullable[Implementation]
}

///|
/// Construct one immutable context around caller-owned typed transport ports.
/// This is intentionally a one-shot constructor rather than a builder.
/// `client_info` defaults to a constant-`Omitted` accessor; the runtime
/// runner injects the accessor backed by the peer's `initialize` params.
pub fn agent_context(
  request_broker~ : AgentContextRequestBroker,
  notification_broker~ : AgentContextNotificationBroker,
  client_info? : () -> ProtocolNullable[Implementation] = fn() { Omitted },
) -> AgentContext {
  { request_broker, notification_broker, client_info, }
}

///|
fn agent_context_exception(
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
async fn agent_context_request(
  context : AgentContext,
  request : ClientRequest,
) -> AgentOutboundReply raise AgentContextError {
  let method_name = request.method_name()
  let result = try (context.request_broker)(request) catch {
    error => Err(agent_context_exception(method_name~, error))
  } noraise {
    value => value
  }
  match result {
    Ok(reply) => reply
    Err(error) => raise error
  }
}

///|
async fn agent_context_notification(
  context : AgentContext,
  notification : ClientNotification,
) -> Unit raise AgentContextError {
  let method_name = notification.method_name()
  let result = try (context.notification_broker)(notification) catch {
    error => Err(agent_context_exception(method_name~, error))
  } noraise {
    value => value
  }
  match result {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
/// Ask the Client for permission to execute a tool call.
pub async fn AgentContext::request_permission(
  self : AgentContext,
  request : RequestPermissionRequest,
) -> RequestPermissionResponse raise AgentContextError {
  match agent_context_request(self, SessionRequestPermission(request)) {
    AgentReplyRequestPermission(reply) => reply
    _ =>
      raise AgentContextReplyMismatch(method_name="session/request_permission")
  }
}

///|
/// Read one absolute filesystem path through the negotiated Client service.
pub async fn AgentContext::read_text_file(
  self : AgentContext,
  params : ReadTextFileParams,
) -> ReadTextFileResult raise AgentContextError {
  match agent_context_request(self, FsReadTextFile(params)) {
    AgentReplyFsReadTextFile(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="fs/read_text_file")
  }
}

///|
/// Write one absolute filesystem path through the negotiated Client service.
pub async fn AgentContext::write_text_file(
  self : AgentContext,
  params : WriteTextFileParams,
) -> WriteTextFileResult raise AgentContextError {
  match agent_context_request(self, FsWriteTextFile(params)) {
    AgentReplyFsWriteTextFile(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="fs/write_text_file")
  }
}

///|
/// Create a terminal owned by the caller's Client runtime.
pub async fn AgentContext::terminal_create(
  self : AgentContext,
  params : TerminalCreateParams,
) -> TerminalCreateResult raise AgentContextError {
  match agent_context_request(self, TerminalCreate(params)) {
    AgentReplyTerminalCreate(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="terminal/create")
  }
}

///|
/// Read accumulated output from a typed terminal handle.
pub async fn AgentContext::terminal_output(
  self : AgentContext,
  params : TerminalOutputParams,
) -> TerminalOutputResult raise AgentContextError {
  match agent_context_request(self, TerminalOutput(params)) {
    AgentReplyTerminalOutput(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="terminal/output")
  }
}

///|
/// Wait for a typed terminal to exit.
pub async fn AgentContext::terminal_wait_for_exit(
  self : AgentContext,
  params : TerminalWaitForExitParams,
) -> TerminalWaitForExitResult raise AgentContextError {
  match agent_context_request(self, TerminalWaitForExit(params)) {
    AgentReplyTerminalWaitForExit(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="terminal/wait_for_exit")
  }
}

///|
/// Kill a typed terminal process.
pub async fn AgentContext::terminal_kill(
  self : AgentContext,
  params : TerminalKillParams,
) -> TerminalKillResult raise AgentContextError {
  match agent_context_request(self, TerminalKill(params)) {
    AgentReplyTerminalKill(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="terminal/kill")
  }
}

///|
/// Release a typed terminal handle.
pub async fn AgentContext::terminal_release(
  self : AgentContext,
  params : TerminalReleaseParams,
) -> TerminalReleaseResult raise AgentContextError {
  match agent_context_request(self, TerminalRelease(params)) {
    AgentReplyTerminalRelease(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="terminal/release")
  }
}

///|
/// Create either form- or URL-mode elicitation using the stable union.
pub async fn AgentContext::elicitation_create(
  self : AgentContext,
  params : ElicitationCreateParams,
) -> ElicitationCreateResult raise AgentContextError {
  match agent_context_request(self, ElicitationCreate(params)) {
    AgentReplyElicitationCreate(reply) => reply
    _ => raise AgentContextReplyMismatch(method_name="elicitation/create")
  }
}

///|
/// Deliver a typed session update notification.  No response is synthesized.
pub async fn AgentContext::session_update(
  self : AgentContext,
  params : SessionUpdateParams,
) -> Unit raise AgentContextError {
  agent_context_notification(self, SessionUpdate(params))
}

///|
/// Complete a typed elicitation notification.  No response is synthesized.
pub async fn AgentContext::elicitation_complete(
  self : AgentContext,
  params : ElicitationCompleteParams,
) -> Unit raise AgentContextError {
  agent_context_notification(self, ElicitationComplete(params))
}

///|
/// Request cancellation of one in-flight typed request.  The runtime decides
/// how to cancel the task; this facade only emits the typed notification.
pub async fn AgentContext::cancel_request(
  self : AgentContext,
  request_id : RequestId,
) -> Unit raise AgentContextError {
  agent_context_notification(self, CancelRequest(request_id))
}
