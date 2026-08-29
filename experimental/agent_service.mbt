///|
/// Typed handler failures crossing the v2 Agent service boundary.  Payloads
/// are host-authored display strings, mirroring the v1 `HandlerError`
/// contract: no secrets, raw payloads, or stack detail.
pub(all) suberror ExperimentalV2AgentHandlerError {
  Application(message~ : String)
  /// Invalid request parameters (unknown id, wrong value shape); maps to
  /// JSON-RPC `-32602`.
  InvalidParams(message~ : String)
  Cancelled
  UnavailableOperation(method_name~ : String)
} derive(Eq, Debug)

///|
/// Normalize one raw handler failure once at the v2 endpoint boundary:
/// cancellation and typed failures keep their shape (the method name is added
/// as context), anything else names itself as an application failure.
// The catch-all is load-bearing: it is the single seam that keeps unexpected
// handler defects typed instead of escaping the owner loop.
#warnings("-fragile_catch_all")
fn experimental_v2_agent_handler_error(
  method_name : String,
  error : Error,
) -> ExperimentalV2AgentHandlerError {
  if @async.is_cancellation_error(error) {
    Cancelled
  } else {
    match error {
      ExperimentalV2AgentHandlerError::Application(message~) =>
        Application(message=method_name + ": " + message)
      ExperimentalV2AgentHandlerError::InvalidParams(message~) =>
        InvalidParams(message=method_name + ": " + message)
      ExperimentalV2AgentHandlerError::Cancelled => Cancelled
      ExperimentalV2AgentHandlerError::UnavailableOperation(method_name~) =>
        UnavailableOperation(method_name~)
      _ =>
        Application(
          message=method_name + ": agent handler failed: " + error.to_string(),
        )
    }
  }
}

///|
async fn[T] experimental_v2_agent_handler_call(
  method_name : String,
  handler : async () -> T,
) -> T raise ExperimentalV2AgentHandlerError {
  handler() catch {
    error => raise experimental_v2_agent_handler_error(method_name, error)
  }
}

///|
/// Typed async handler signatures for the required v2 baseline session
/// operations (the `session` marker's implied method set plus the ungated
/// `session/set_config_option`).
pub type ExperimentalV2AgentNewSessionHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2NewSessionParams,
) -> ExperimentalV2NewSessionResult

///|
pub type ExperimentalV2AgentListSessionsHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2ListSessionsParams,
) -> ExperimentalV2ListSessionsResult

///|
pub type ExperimentalV2AgentResumeSessionHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2ResumeSessionParams,
) -> ExperimentalV2ResumeSessionResult

///|
pub type ExperimentalV2AgentCloseSessionHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2CloseSessionParams,
) -> ExperimentalV2CloseSessionResult

///|
pub type ExperimentalV2AgentPromptHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2PromptParams,
) -> ExperimentalV2PromptResult

///|
pub type ExperimentalV2AgentSetConfigOptionHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2SetConfigOptionParams,
) -> ExperimentalV2SetConfigOptionResult

///|
/// Typed async handler for the `session.delete`-gated optional operation.
pub type ExperimentalV2AgentDeleteSessionHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2DeleteSessionParams,
) -> ExperimentalV2DeleteSessionResult

///|
/// Typed async handler for the `session.fork`-gated optional operation.
/// Upstream unstable (RFD session-fork, Draft).
pub type ExperimentalV2AgentForkSessionHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2ForkSessionParams,
) -> ExperimentalV2ForkSessionResult

///|
/// Typed async handler for `auth/login`.
pub type ExperimentalV2AgentLoginHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2LoginParams,
) -> ExperimentalV2LoginResult

///|
/// Typed async handler for `auth/logout`.
pub type ExperimentalV2AgentLogoutHandler = async (
  ExperimentalV2AgentContext,
  ExperimentalV2LogoutParams,
) -> ExperimentalV2LogoutResult

///|
/// Immutable required/optional session service.  Fields stay private so a
/// half-populated service record cannot exist; optional callbacks are `None`,
/// never a mutable registration phase.
pub struct ExperimentalV2AgentSessionService {
  new_handler : ExperimentalV2AgentNewSessionHandler
  list_handler : ExperimentalV2AgentListSessionsHandler
  resume_handler : ExperimentalV2AgentResumeSessionHandler
  close_handler : ExperimentalV2AgentCloseSessionHandler
  prompt_handler : ExperimentalV2AgentPromptHandler
  set_config_option_handler : ExperimentalV2AgentSetConfigOptionHandler
  delete_handler : ExperimentalV2AgentDeleteSessionHandler?
  fork_handler : ExperimentalV2AgentForkSessionHandler?
}

///|
/// Compose the required v2 baseline session callbacks once.  `delete` is the
/// only optional callback and couples to the `session.delete` capability
/// marker at spec validation.  `fork_session` couples to the `session.fork`
/// marker of the pinned v2 unstable overlay the same way.  Upstream unstable
/// (RFD session-fork, Draft) for `fork_session`.
pub fn experimental_v2_agent_session_service(
  new_session~ : ExperimentalV2AgentNewSessionHandler,
  list~ : ExperimentalV2AgentListSessionsHandler,
  resume_session~ : ExperimentalV2AgentResumeSessionHandler,
  close~ : ExperimentalV2AgentCloseSessionHandler,
  prompt~ : ExperimentalV2AgentPromptHandler,
  set_config_option~ : ExperimentalV2AgentSetConfigOptionHandler,
  delete? : ExperimentalV2AgentDeleteSessionHandler? = None,
  fork_session? : ExperimentalV2AgentForkSessionHandler? = None,
) -> ExperimentalV2AgentSessionService {
  {
    new_handler: new_session,
    list_handler: list,
    resume_handler: resume_session,
    close_handler: close,
    prompt_handler: prompt,
    set_config_option_handler: set_config_option,
    delete_handler: delete,
    fork_handler: fork_session,
  }
}

///|
/// Immutable authentication service.  v2 advertises `auth/login` and
/// `auth/logout` as one surface, so both handlers form a pair; the advertised
/// method list lives on the spec, where its coupling is validated.
pub struct ExperimentalV2AgentAuthService {
  login_handler : ExperimentalV2AgentLoginHandler
  logout_handler : ExperimentalV2AgentLogoutHandler
}

///|
pub fn experimental_v2_agent_auth_service(
  login~ : ExperimentalV2AgentLoginHandler,
  logout~ : ExperimentalV2AgentLogoutHandler,
) -> ExperimentalV2AgentAuthService {
  { login_handler: login, logout_handler: logout, }
}

///|
/// Failures found while composing one immutable v2 Agent endpoint.
pub(all) suberror ExperimentalV2AgentCompositionError {
  InvalidImplementation(reason~ : String)
  EmptyAuthMethods
  DuplicateAuthMethodId(method_id~ : String)
  /// A non-empty `authMethods` advertisement without the auth service, or the
  /// service without the advertisement.
  AuthServiceMismatch(reason~ : String)
  /// The `session.delete` marker and the delete service disagree.
  DeleteServiceMismatch(reason~ : String)
  /// The `session.fork` marker and the fork service disagree.  Upstream
  /// unstable (RFD session-fork, Draft).
  ForkServiceMismatch(reason~ : String)
  /// The required baseline session methods imply a supported `session`
  /// capability marker.
  SessionMarkerMissing
} derive(Eq, Debug)

///|
/// Immutable v2 Agent specification: advertised identity and capabilities
/// plus the service values that must back them.
pub struct ExperimentalV2AgentSpec {
  info : ExperimentalV2Implementation
  capabilities : ExperimentalV2AgentCapabilities
  sessions : ExperimentalV2AgentSessionService
  auth_methods : Array[ExperimentalV2AuthMethod]?
  auth : ExperimentalV2AgentAuthService?
}

///|
fn experimental_v2_agent_duplicate_method_id(
  methods : Array[ExperimentalV2AuthMethod],
) -> String? {
  search~: {
    let seen : Map[String, Bool] = Map([])
    for entry in methods {
      match entry {
        Known(agent) =>
          if seen.contains(agent.method_id) {
            break search~ Some(agent.method_id)
          } else {
            seen[agent.method_id] = true
          }
        Extension(..) | Future(..) => ()
      }
    }
    None
  }
}

///|
/// Compose one validated v2 Agent spec.  Fail-fast rules: identity fields are
/// non-empty; `authMethods` and the auth service are coupled both directions
/// (a non-empty advertisement without the service is a composition error, and
/// so is the reverse) with the same non-empty/duplicate-free method list the
/// endpoint state constructor enforces; the `session` marker must be
/// supported because its baseline methods are required services; the
/// `session.delete` marker exists exactly when the delete service does; and
/// the `session.fork` marker exists exactly when the fork service does
/// (upstream unstable, RFD session-fork, Draft).
pub fn experimental_v2_agent_spec(
  info~ : ExperimentalV2Implementation,
  capabilities~ : ExperimentalV2AgentCapabilities,
  sessions~ : ExperimentalV2AgentSessionService,
  auth_methods? : Array[ExperimentalV2AuthMethod]? = None,
  auth? : ExperimentalV2AgentAuthService? = None,
) -> ExperimentalV2AgentSpec raise ExperimentalV2AgentCompositionError {
  if info.name == "" {
    raise InvalidImplementation(reason="agent name must not be empty")
  }
  if info.version == "" {
    raise InvalidImplementation(reason="agent version must not be empty")
  }
  if capabilities.session is MarkerUnsupported {
    raise SessionMarkerMissing
  }
  match auth_methods {
    None =>
      if auth is Some(_) {
        raise AuthServiceMismatch(
          reason="the auth service requires advertised authMethods",
        )
      }
    Some(methods) => {
      if methods.is_empty() {
        raise EmptyAuthMethods
      }
      match experimental_v2_agent_duplicate_method_id(methods) {
        Some(method_id) => raise DuplicateAuthMethodId(method_id~)
        None => ()
      }
      if auth is None {
        raise AuthServiceMismatch(
          reason="advertised authMethods require the auth service",
        )
      }
    }
  }
  let delete_supported : Bool = match capabilities.session {
    MarkerSupported(session) => session.delete is MarkerSupported(_)
    MarkerUnsupported => false
  }
  if delete_supported && sessions.delete_handler is None {
    raise DeleteServiceMismatch(
      reason="the session.delete marker requires the delete service",
    )
  }
  if !delete_supported && sessions.delete_handler is Some(_) {
    raise DeleteServiceMismatch(
      reason="the delete service requires the session.delete marker",
    )
  }
  let fork_supported : Bool = match capabilities.session {
    MarkerSupported(session) => session.fork is MarkerSupported(_)
    MarkerUnsupported => false
  }
  if fork_supported && sessions.fork_handler is None {
    raise ForkServiceMismatch(
      reason="the session.fork marker requires the fork service",
    )
  }
  if !fork_supported && sessions.fork_handler is Some(_) {
    raise ForkServiceMismatch(
      reason="the fork service requires the session.fork marker",
    )
  }
  { info, capabilities, sessions, auth_methods, auth, }
}

///|
/// An opaque, fully validated v2 Agent endpoint: immutable service closures
/// plus the advertisement its `initialize` result echoes.  It never owns
/// connection-scoped state.
pub struct ExperimentalV2AgentEndpoint {
  info : ExperimentalV2Implementation
  capabilities : ExperimentalV2AgentCapabilities
  auth_methods : Array[ExperimentalV2AuthMethod]?
  sessions : ExperimentalV2AgentSessionService
  auth : ExperimentalV2AgentAuthService?
}

///|
/// Derive the endpoint's advertised capabilities from the validated spec.
/// The `session.delete` and `session.fork` markers are rebuilt from
/// delete/fork-service presence so the endpoint cannot drift from its
/// services; every other marker is the spec's validated value.
fn experimental_v2_agent_endpoint_capabilities(
  spec : ExperimentalV2AgentSpec,
) -> ExperimentalV2AgentCapabilities {
  match spec.capabilities.session {
    MarkerSupported(session) => {
      let delete : ExperimentalV2Marker[ExperimentalV2MarkerPayload] = if spec.sessions.delete_handler
        is Some(_) {
        session.delete
      } else {
        MarkerUnsupported
      }
      let fork : ExperimentalV2Marker[ExperimentalV2MarkerPayload] = if spec.sessions.fork_handler
        is Some(_) {
        session.fork
      } else {
        MarkerUnsupported
      }
      {
        ..spec.capabilities,
        session: MarkerSupported({ ..session, delete, fork, }),
      }
    }
    MarkerUnsupported => spec.capabilities
  }
}

///|
pub fn experimental_v2_agent_endpoint_from_spec(
  spec : ExperimentalV2AgentSpec,
) -> ExperimentalV2AgentEndpoint {
  {
    info: spec.info,
    capabilities: experimental_v2_agent_endpoint_capabilities(spec),
    auth_methods: match spec.auth_methods {
      Some(methods) => Some(methods.copy())
      None => None
    },
    sessions: spec.sessions,
    auth: spec.auth,
  }
}

///|
/// Return the immutable implementation information for initialization.
pub fn ExperimentalV2AgentEndpoint::info(
  self : ExperimentalV2AgentEndpoint,
) -> ExperimentalV2Implementation {
  self.info
}

///|
/// Return the capabilities derived from service presence and spec markers.
pub fn ExperimentalV2AgentEndpoint::capabilities(
  self : ExperimentalV2AgentEndpoint,
) -> ExperimentalV2AgentCapabilities {
  self.capabilities
}

///|
/// Return a defensive copy of the advertised authentication methods.
pub fn ExperimentalV2AgentEndpoint::auth_methods(
  self : ExperimentalV2AgentEndpoint,
) -> Array[ExperimentalV2AuthMethod]? {
  match self.auth_methods {
    Some(methods) => Some(methods.copy())
    None => None
  }
}

///|
/// Return the immutable endpoint advertisement as one fresh endpoint config,
/// the exact value `experimental_v2_agent_state_new` expects.
pub fn ExperimentalV2AgentEndpoint::config(
  self : ExperimentalV2AgentEndpoint,
) -> ExperimentalV2AgentEndpointConfig {
  {
    info: self.info,
    capabilities: self.capabilities,
    auth_methods: match self.auth_methods {
      Some(methods) => Some(methods.copy())
      None => None
    },
  }
}

///|
/// Invoke the required typed `session/new` handler.
pub async fn ExperimentalV2AgentEndpoint::new_session(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2NewSessionParams,
) -> ExperimentalV2NewSessionResult raise ExperimentalV2AgentHandlerError {
  experimental_v2_agent_handler_call("session/new", async fn() {
    (self.sessions.new_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/list` handler.
pub async fn ExperimentalV2AgentEndpoint::list_sessions(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2ListSessionsParams,
) -> ExperimentalV2ListSessionsResult raise ExperimentalV2AgentHandlerError {
  experimental_v2_agent_handler_call("session/list", async fn() {
    (self.sessions.list_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/resume` handler.
pub async fn ExperimentalV2AgentEndpoint::resume_session(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2ResumeSessionParams,
) -> ExperimentalV2ResumeSessionResult raise ExperimentalV2AgentHandlerError {
  experimental_v2_agent_handler_call("session/resume", async fn() {
    (self.sessions.resume_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/close` handler.
pub async fn ExperimentalV2AgentEndpoint::close_session(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2CloseSessionParams,
) -> ExperimentalV2CloseSessionResult raise ExperimentalV2AgentHandlerError {
  experimental_v2_agent_handler_call("session/close", async fn() {
    (self.sessions.close_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/prompt` handler.
pub async fn ExperimentalV2AgentEndpoint::prompt(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2PromptParams,
) -> ExperimentalV2PromptResult raise ExperimentalV2AgentHandlerError {
  experimental_v2_agent_handler_call("session/prompt", async fn() {
    (self.sessions.prompt_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/set_config_option` handler.
pub async fn ExperimentalV2AgentEndpoint::set_config_option(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2SetConfigOptionParams,
) -> ExperimentalV2SetConfigOptionResult raise ExperimentalV2AgentHandlerError {
  experimental_v2_agent_handler_call("session/set_config_option", async fn() {
    (self.sessions.set_config_option_handler)(context, params)
  })
}

///|
/// Invoke the optional typed `session/delete` handler.
pub async fn ExperimentalV2AgentEndpoint::delete_session(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2DeleteSessionParams,
) -> ExperimentalV2DeleteSessionResult raise ExperimentalV2AgentHandlerError {
  match self.sessions.delete_handler {
    Some(handler) =>
      experimental_v2_agent_handler_call("session/delete", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/delete")
  }
}

///|
/// Invoke the optional typed `session/fork` handler.  Upstream unstable (RFD
/// session-fork, Draft).
pub async fn ExperimentalV2AgentEndpoint::fork_session(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2ForkSessionParams,
) -> ExperimentalV2ForkSessionResult raise ExperimentalV2AgentHandlerError {
  match self.sessions.fork_handler {
    Some(handler) =>
      experimental_v2_agent_handler_call("session/fork", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/fork")
  }
}

///|
/// Invoke the typed `auth/login` handler of the auth pair.
pub async fn ExperimentalV2AgentEndpoint::auth_login(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2LoginParams,
) -> ExperimentalV2LoginResult raise ExperimentalV2AgentHandlerError {
  match self.auth {
    Some(auth) =>
      experimental_v2_agent_handler_call("auth/login", async fn() {
        (auth.login_handler)(context, params)
      })
    None => raise UnavailableOperation(method_name="auth/login")
  }
}

///|
/// Invoke the typed `auth/logout` handler of the auth pair.
pub async fn ExperimentalV2AgentEndpoint::auth_logout(
  self : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
  params : ExperimentalV2LogoutParams,
) -> ExperimentalV2LogoutResult raise ExperimentalV2AgentHandlerError {
  match self.auth {
    Some(auth) =>
      experimental_v2_agent_handler_call("auth/logout", async fn() {
        (auth.logout_handler)(context, params)
      })
    None => raise UnavailableOperation(method_name="auth/logout")
  }
}
