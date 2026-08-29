///|
/// The closed set of typed results returned by stable Client-to-Agent
/// requests.  Constructor names are prefixed so this reply union cannot be
/// confused with the corresponding request constructors.
pub(all) enum ClientReply {
  ClientReplyInitialize(InitializeResult)
  ClientReplyAuthenticate(AuthenticateResult)
  ClientReplyLogout(LogoutResult)
  ClientReplyNewSession(NewSessionResult)
  ClientReplyLoadSession(LoadSessionResult)
  ClientReplyResumeSession(ResumeSessionResult)
  ClientReplyForkSession(ForkSessionResult)
  ClientReplyListSessions(ListSessionsResult)
  ClientReplyDeleteSession(DeleteSessionResult)
  ClientReplyCloseSession(CloseSessionResult)
  ClientReplySetMode(SetSessionModeResult)
  ClientReplySetConfigOption(SetSessionConfigOptionResult)
  ClientReplyPrompt(PromptResult)
} derive(Eq, Debug)

///|
/// Return the exact request method associated with a typed reply.
pub fn ClientReply::method_name(self : ClientReply) -> String {
  match self {
    ClientReplyInitialize(_) => "initialize"
    ClientReplyAuthenticate(_) => "authenticate"
    ClientReplyLogout(_) => "logout"
    ClientReplyNewSession(_) => "session/new"
    ClientReplyLoadSession(_) => "session/load"
    ClientReplyResumeSession(_) => "session/resume"
    ClientReplyForkSession(_) => "session/fork"
    ClientReplyListSessions(_) => "session/list"
    ClientReplyDeleteSession(_) => "session/delete"
    ClientReplyCloseSession(_) => "session/close"
    ClientReplySetMode(_) => "session/set_mode"
    ClientReplySetConfigOption(_) => "session/set_config_option"
    ClientReplyPrompt(_) => "session/prompt"
  }
}

///|
/// Explicit failures crossing the Client-to-Agent typed connection facade.
/// Runtime adapters may return these values from negotiated capability gates
/// or transport cancellation; the facade never converts them into success.
pub(all) suberror ClientConnectionError {
  ClientConnectionUnsupportedVersion(method_name~ : String, version~ : Int)
  ClientConnectionUnavailable(method_name~ : String)
  ClientConnectionCancelled(method_name~ : String)
  ClientConnectionBrokerFailure(method_name~ : String)
  ClientConnectionReplyMismatch(
    method_name~ : String,
    expected~ : String,
    actual~ : String
  )
} derive(Eq, Debug)

///|
/// Stable v1 exposes only protocol version 1.  Reject an incompatible typed
/// request or broker result explicitly instead of silently negotiating a
/// version this facade cannot implement.
fn client_connection_require_v1(
  method_name : String,
  version : Int,
) -> Unit raise ClientConnectionError {
  if version != 1 {
    raise ClientConnectionUnsupportedVersion(method_name~, version~)
  }
}

///|
/// A one-shot typed request transport.  It owns no request identifiers or
/// connection state; those remain with the runtime that implements it.
pub type ClientRequestBroker = async (AgentRequest) -> Result[
  ClientReply,
  ClientConnectionError,
]

///|
/// A one-shot typed notification transport.  Notifications have no reply,
/// and this facade deliberately keeps this port synchronous: a runtime may
/// accept the immutable notification intent into a bounded queue (or fail
/// fast); `Ok` does not claim that transport I/O has completed.
pub type ClientNotificationBroker = (AgentNotification) -> Result[
  Unit,
  ClientConnectionError,
]

///|
/// Opaque typed Client connection facade.  Only immutable broker closures are
/// retained; no mutable protocol state, request-id table, capability flags,
/// queue, task, global, or service locator is stored here.
pub struct ClientConnection {
  request_broker : ClientRequestBroker
  notification_broker : ClientNotificationBroker
}

///|
/// Construct one immutable Client connection around caller-owned typed
/// transport ports.  This is intentionally a one-shot constructor rather than
/// a builder or registration API.
pub fn client_connection(
  request_broker~ : ClientRequestBroker,
  notification_broker~ : ClientNotificationBroker,
) -> ClientConnection {
  { request_broker, notification_broker, }
}

///|
async fn client_connection_request(
  connection : ClientConnection,
  request : AgentRequest,
  method_name : String,
) -> ClientReply raise ClientConnectionError {
  let result = try (connection.request_broker)(request) catch {
    error =>
      if @async.is_cancellation_error(error) {
        Err(ClientConnectionCancelled(method_name~))
      } else {
        Err(ClientConnectionBrokerFailure(method_name~))
      }
  } noraise {
    value => value
  }
  match result {
    Ok(reply) => reply
    Err(error) => raise error
  }
}

///|
fn client_connection_notification(
  connection : ClientConnection,
  notification : AgentNotification,
) -> Unit raise ClientConnectionError {
  match (connection.notification_broker)(notification) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
pub async fn ClientConnection::initialize(
  self : ClientConnection,
  params : InitializeParams,
) -> InitializeResult raise ClientConnectionError {
  client_connection_require_v1("initialize", params.protocol_version)
  match client_connection_request(self, Initialize(params), "initialize") {
    ClientReplyInitialize(result) => {
      client_connection_require_v1("initialize", result.protocol_version)
      result
    }
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="initialize",
        expected="initialize",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::authenticate(
  self : ClientConnection,
  params : AuthenticateParams,
) -> AuthenticateResult raise ClientConnectionError {
  match client_connection_request(self, Authenticate(params), "authenticate") {
    ClientReplyAuthenticate(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="authenticate",
        expected="authenticate",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::logout(
  self : ClientConnection,
  params : LogoutParams,
) -> LogoutResult raise ClientConnectionError {
  match client_connection_request(self, Logout(params), "logout") {
    ClientReplyLogout(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="logout",
        expected="logout",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::new_session(
  self : ClientConnection,
  params : NewSessionParams,
) -> NewSessionResult raise ClientConnectionError {
  match client_connection_request(self, SessionNew(params), "session/new") {
    ClientReplyNewSession(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/new",
        expected="session/new",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::load_session(
  self : ClientConnection,
  params : LoadSessionParams,
) -> LoadSessionResult raise ClientConnectionError {
  match client_connection_request(self, SessionLoad(params), "session/load") {
    ClientReplyLoadSession(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/load",
        expected="session/load",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::resume_session(
  self : ClientConnection,
  params : ResumeSessionParams,
) -> ResumeSessionResult raise ClientConnectionError {
  match
    client_connection_request(self, SessionResume(params), "session/resume") {
    ClientReplyResumeSession(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/resume",
        expected="session/resume",
        actual=reply.method_name(),
      )
  }
}

///|
/// Send `session/fork` and settle the forked session id.  Upstream unstable
/// (RFD session-fork, Draft); callers must first observe the `session.fork`
/// capability marker in the agent's initialize result.
pub async fn ClientConnection::fork_session(
  self : ClientConnection,
  params : ForkSessionParams,
) -> ForkSessionResult raise ClientConnectionError {
  match client_connection_request(self, SessionFork(params), "session/fork") {
    ClientReplyForkSession(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/fork",
        expected="session/fork",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::list_sessions(
  self : ClientConnection,
  params : ListSessionsParams,
) -> ListSessionsResult raise ClientConnectionError {
  match client_connection_request(self, SessionList(params), "session/list") {
    ClientReplyListSessions(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/list",
        expected="session/list",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::delete_session(
  self : ClientConnection,
  params : DeleteSessionParams,
) -> DeleteSessionResult raise ClientConnectionError {
  match
    client_connection_request(self, SessionDelete(params), "session/delete") {
    ClientReplyDeleteSession(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/delete",
        expected="session/delete",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::close_session(
  self : ClientConnection,
  params : CloseSessionParams,
) -> CloseSessionResult raise ClientConnectionError {
  match client_connection_request(self, SessionClose(params), "session/close") {
    ClientReplyCloseSession(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/close",
        expected="session/close",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::set_mode(
  self : ClientConnection,
  params : SetSessionModeParams,
) -> SetSessionModeResult raise ClientConnectionError {
  match
    client_connection_request(self, SessionSetMode(params), "session/set_mode") {
    ClientReplySetMode(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/set_mode",
        expected="session/set_mode",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::set_config_option(
  self : ClientConnection,
  params : SetSessionConfigOptionParams,
) -> SetSessionConfigOptionResult raise ClientConnectionError {
  match
    client_connection_request(
      self,
      SessionSetConfigOption(params),
      "session/set_config_option",
    ) {
    ClientReplySetConfigOption(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/set_config_option",
        expected="session/set_config_option",
        actual=reply.method_name(),
      )
  }
}

///|
pub async fn ClientConnection::prompt(
  self : ClientConnection,
  params : PromptParams,
) -> PromptResult raise ClientConnectionError {
  match
    client_connection_request(self, SessionPrompt(params), "session/prompt") {
    ClientReplyPrompt(result) => result
    reply =>
      raise ClientConnectionReplyMismatch(
        method_name="session/prompt",
        expected="session/prompt",
        actual=reply.method_name(),
      )
  }
}

///|
/// Emit the stable `session/cancel` notification.  No response is synthesized.
pub fn ClientConnection::cancel(
  self : ClientConnection,
  params : CancelParams,
) -> Unit raise ClientConnectionError {
  client_connection_notification(self, SessionCancel(params))
}

///|
/// Emit the bidirectional JSON-RPC cancellation notification.  Correlation
/// identifiers remain typed and are not converted through raw JSON.
pub fn ClientConnection::cancel_request(
  self : ClientConnection,
  request_id : RequestId,
) -> Unit raise ClientConnectionError {
  client_connection_notification(self, CancelRequest(request_id))
}
