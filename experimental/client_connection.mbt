///|
/// The closed set of typed Client-to-Agent v2 requests, one constructor per
/// forward wire method.
pub(all) enum ExperimentalV2ClientForwardRequest {
  Initialize(ExperimentalV2InitializeParams)
  AuthLogin(ExperimentalV2LoginParams)
  AuthLogout(ExperimentalV2LogoutParams)
  SessionNew(ExperimentalV2NewSessionParams)
  SessionList(ExperimentalV2ListSessionsParams)
  SessionResume(ExperimentalV2ResumeSessionParams)
  SessionDelete(ExperimentalV2DeleteSessionParams)
  SessionClose(ExperimentalV2CloseSessionParams)
  SessionPrompt(ExperimentalV2PromptParams)
  SessionSetConfigOption(ExperimentalV2SetConfigOptionParams)
} derive(Eq, Debug)

///|
/// Return the forward wire method name of one typed request.
pub fn ExperimentalV2ClientForwardRequest::method_name(
  self : ExperimentalV2ClientForwardRequest,
) -> String {
  match self {
    Initialize(_) => "initialize"
    AuthLogin(_) => "auth/login"
    AuthLogout(_) => "auth/logout"
    SessionNew(_) => "session/new"
    SessionList(_) => "session/list"
    SessionResume(_) => "session/resume"
    SessionDelete(_) => "session/delete"
    SessionClose(_) => "session/close"
    SessionPrompt(_) => "session/prompt"
    SessionSetConfigOption(_) => "session/set_config_option"
  }
}

///|
/// The closed set of typed results returned by forward v2 requests.
/// Constructor names are prefixed so this reply union cannot be confused with
/// the request constructors.
pub(all) enum ExperimentalV2ClientForwardReply {
  ReplyInitialize(ExperimentalV2InitializeResult)
  ReplyAuthLogin(ExperimentalV2LoginResult)
  ReplyAuthLogout(ExperimentalV2LogoutResult)
  ReplyNewSession(ExperimentalV2NewSessionResult)
  ReplyListSessions(ExperimentalV2ListSessionsResult)
  ReplyResumeSession(ExperimentalV2ResumeSessionResult)
  ReplyDeleteSession(ExperimentalV2DeleteSessionResult)
  ReplyCloseSession(ExperimentalV2CloseSessionResult)
  ReplyPrompt(ExperimentalV2PromptResult)
  ReplySetConfigOption(ExperimentalV2SetConfigOptionResult)
} derive(Eq, Debug)

///|
/// Return the forward wire method name that owns one typed reply.
pub fn ExperimentalV2ClientForwardReply::method_name(
  self : ExperimentalV2ClientForwardReply,
) -> String {
  match self {
    ReplyInitialize(_) => "initialize"
    ReplyAuthLogin(_) => "auth/login"
    ReplyAuthLogout(_) => "auth/logout"
    ReplyNewSession(_) => "session/new"
    ReplyListSessions(_) => "session/list"
    ReplyResumeSession(_) => "session/resume"
    ReplyDeleteSession(_) => "session/delete"
    ReplyCloseSession(_) => "session/close"
    ReplyPrompt(_) => "session/prompt"
    ReplySetConfigOption(_) => "session/set_config_option"
  }
}

///|
/// The typed Client-to-Agent v2 notifications: the session-scoped cancel and
/// the bidirectional engine-level `$/cancel_request`.
pub(all) enum ExperimentalV2ClientForwardNotification {
  SessionCancel(ExperimentalV2CancelSessionParams)
  CancelRequest(ExperimentalV2RequestId)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2ClientForwardNotification::method_name(
  self : ExperimentalV2ClientForwardNotification,
) -> String {
  match self {
    SessionCancel(_) => "session/cancel"
    CancelRequest(_) => "$/cancel_request"
  }
}

///|
/// Explicit failures crossing the Client-to-Agent typed v2 connection facade.
/// `UnsupportedVersion` mirrors the Client state machine's terminal
/// negotiation failure: v2 has no downgrade path, so a non-version-2
/// initialize exchange is a typed failure, never a silent negotiation.
pub(all) suberror ExperimentalV2ClientConnectionError {
  UnsupportedVersion(method_name~ : String, offered~ : Int)
  Unavailable(method_name~ : String)
  Cancelled(method_name~ : String)
  BrokerFailure(method_name~ : String)
  ReplyMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
/// A one-shot typed forward-request transport.  It owns no request
/// identifiers or connection state; those remain with the runtime that
/// implements it.
pub type ExperimentalV2ClientForwardRequestBroker = async (
  ExperimentalV2ClientForwardRequest,
) -> Result[
  ExperimentalV2ClientForwardReply,
  ExperimentalV2ClientConnectionError,
]

///|
/// A one-shot typed notification transport.  Notifications have no reply,
/// and this facade deliberately keeps this port synchronous: a runtime may
/// accept the immutable notification intent into a bounded queue (or fail
/// fast); `Ok` does not claim that transport I/O has completed.
pub type ExperimentalV2ClientForwardNotificationBroker = (
  ExperimentalV2ClientForwardNotification,
) -> Result[Unit, ExperimentalV2ClientConnectionError]

///|
/// Opaque typed v2 Client connection facade.  Only immutable broker closures
/// are retained; no mutable protocol state, request-id table, capability
/// flags, queue, task, global, or service locator is stored here.
pub struct ExperimentalV2ClientConnection {
  request_broker : ExperimentalV2ClientForwardRequestBroker
  notification_broker : ExperimentalV2ClientForwardNotificationBroker
}

///|
/// Construct one immutable v2 Client connection around caller-owned typed
/// transport ports.  This is intentionally a one-shot constructor rather than
/// a builder or registration API.
pub fn experimental_v2_client_connection(
  request_broker~ : ExperimentalV2ClientForwardRequestBroker,
  notification_broker~ : ExperimentalV2ClientForwardNotificationBroker,
) -> ExperimentalV2ClientConnection {
  { request_broker, notification_broker }
}

///|
async fn experimental_v2_client_connection_request(
  connection : ExperimentalV2ClientConnection,
  request : ExperimentalV2ClientForwardRequest,
) -> ExperimentalV2ClientForwardReply raise ExperimentalV2ClientConnectionError {
  let method_name = request.method_name()
  let result = try (connection.request_broker)(request) catch {
    error =>
      if @async.is_cancellation_error(error) {
        Err(ExperimentalV2ClientConnectionError::Cancelled(method_name~))
      } else {
        Err(BrokerFailure(method_name~))
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
fn experimental_v2_client_connection_notification(
  connection : ExperimentalV2ClientConnection,
  notification : ExperimentalV2ClientForwardNotification,
) -> Unit raise ExperimentalV2ClientConnectionError {
  match (connection.notification_broker)(notification) {
    Ok(_) => ()
    Err(error) => raise error
  }
}

///|
fn experimental_v2_client_connection_require_v2(
  method_name : String,
  version : Int,
) -> Unit raise ExperimentalV2ClientConnectionError {
  if version != experimental_v2_protocol_version {
    raise UnsupportedVersion(method_name~, offered=version)
  }
}

///|
/// Run the `initialize` exchange.  The pinned version 2 is required on both
/// the outgoing params and the received result; any other offered version is
/// the typed `UnsupportedVersion` failure the Client state machine defines,
/// because v2 has no downgrade path.
pub async fn ExperimentalV2ClientConnection::initialize(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2InitializeParams,
) -> ExperimentalV2InitializeResult raise ExperimentalV2ClientConnectionError {
  experimental_v2_client_connection_require_v2(
    "initialize",
    params.protocol_version,
  )
  match experimental_v2_client_connection_request(self, Initialize(params)) {
    ReplyInitialize(result) => {
      experimental_v2_client_connection_require_v2(
        "initialize",
        result.protocol_version,
      )
      result
    }
    reply =>
      raise ReplyMismatch(method_name="initialize: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::auth_login(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2LoginParams,
) -> ExperimentalV2LoginResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, AuthLogin(params)) {
    ReplyAuthLogin(result) => result
    reply =>
      raise ReplyMismatch(method_name="auth/login: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::auth_logout(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2LogoutParams,
) -> ExperimentalV2LogoutResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, AuthLogout(params)) {
    ReplyAuthLogout(result) => result
    reply =>
      raise ReplyMismatch(method_name="auth/logout: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::new_session(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2NewSessionParams,
) -> ExperimentalV2NewSessionResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, SessionNew(params)) {
    ReplyNewSession(result) => result
    reply =>
      raise ReplyMismatch(method_name="session/new: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::list_sessions(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2ListSessionsParams,
) -> ExperimentalV2ListSessionsResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, SessionList(params)) {
    ReplyListSessions(result) => result
    reply =>
      raise ReplyMismatch(method_name="session/list: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::resume_session(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2ResumeSessionParams,
) -> ExperimentalV2ResumeSessionResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, SessionResume(params)) {
    ReplyResumeSession(result) => result
    reply =>
      raise ReplyMismatch(method_name="session/resume: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::delete_session(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2DeleteSessionParams,
) -> ExperimentalV2DeleteSessionResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, SessionDelete(params)) {
    ReplyDeleteSession(result) => result
    reply =>
      raise ReplyMismatch(method_name="session/delete: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::close_session(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2CloseSessionParams,
) -> ExperimentalV2CloseSessionResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, SessionClose(params)) {
    ReplyCloseSession(result) => result
    reply =>
      raise ReplyMismatch(method_name="session/close: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::prompt(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2PromptParams,
) -> ExperimentalV2PromptResult raise ExperimentalV2ClientConnectionError {
  match experimental_v2_client_connection_request(self, SessionPrompt(params)) {
    ReplyPrompt(result) => result
    reply =>
      raise ReplyMismatch(method_name="session/prompt: " + reply.method_name())
  }
}

///|
pub async fn ExperimentalV2ClientConnection::set_config_option(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2SetConfigOptionParams,
) -> ExperimentalV2SetConfigOptionResult raise ExperimentalV2ClientConnectionError {
  match
    experimental_v2_client_connection_request(
      self,
      SessionSetConfigOption(params),
    ) {
    ReplySetConfigOption(result) => result
    reply =>
      raise ReplyMismatch(
        method_name="session/set_config_option: " + reply.method_name(),
      )
  }
}

///|
/// Emit the stable `session/cancel` notification.  No response is
/// synthesized.
pub fn ExperimentalV2ClientConnection::cancel_session(
  self : ExperimentalV2ClientConnection,
  params : ExperimentalV2CancelSessionParams,
) -> Unit raise ExperimentalV2ClientConnectionError {
  experimental_v2_client_connection_notification(self, SessionCancel(params))
}

///|
/// Emit the bidirectional JSON-RPC cancellation notification.  Correlation
/// identifiers remain typed and are not converted through raw JSON.
pub fn ExperimentalV2ClientConnection::cancel_request(
  self : ExperimentalV2ClientConnection,
  request_id : ExperimentalV2RequestId,
) -> Unit raise ExperimentalV2ClientConnectionError {
  experimental_v2_client_connection_notification(
    self,
    CancelRequest(request_id),
  )
}
