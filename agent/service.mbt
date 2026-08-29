///|
/// Normalize generic async failures once at the Agent endpoint boundary.
/// Handler-authored messages pass through with the method name as context;
/// an unexpected exception names itself so the client receives something a
/// user can paste to a developer.
fn agent_handler_error(method_name : String, error : Error) -> HandlerError {
  if @async.is_cancellation_error(error) {
    Cancelled
  } else {
    match error {
      HandlerError::Application(message~) =>
        Application(message=method_name + ": " + message)
      HandlerError::InvalidParams(message~) =>
        InvalidParams(message=method_name + ": " + message)
      HandlerError::Cancelled => Cancelled
      HandlerError::UnavailableOperation(method_name~) =>
        UnavailableOperation(method_name~)
      _ =>
        Application(
          message=method_name + ": agent handler failed: " + error.to_string(),
        )
    }
  }
}

///|
async fn[T] agent_handler_call(
  method_name : String,
  handler : async () -> T,
) -> T raise HandlerError {
  handler() catch {
    error => raise agent_handler_error(method_name, error)
  }
}

///|
/// Typed async handler signatures for the required session operations.
pub type AgentNewSessionHandler = async (AgentContext, NewSessionParams) -> NewSessionResult

///|
pub type AgentPromptHandler = async (AgentContext, PromptParams) -> PromptResult

///|
pub type AgentCancelHandler = async (AgentContext, CancelParams) -> Unit

///|
/// Typed async handler signatures for optional session operations.
pub type AgentLoadSessionHandler = async (AgentContext, LoadSessionParams) -> LoadSessionResult

///|
pub type AgentResumeSessionHandler = async (AgentContext, ResumeSessionParams) -> ResumeSessionResult

///|
pub type AgentForkSessionHandler = async (AgentContext, ForkSessionParams) -> ForkSessionResult

///|
pub type AgentListSessionsHandler = async (AgentContext, ListSessionsParams) -> ListSessionsResult

///|
pub type AgentDeleteSessionHandler = async (AgentContext, DeleteSessionParams) -> DeleteSessionResult

///|
pub type AgentCloseSessionHandler = async (AgentContext, CloseSessionParams) -> CloseSessionResult

///|
pub type AgentSetModeHandler = async (AgentContext, SetSessionModeParams) -> SetSessionModeResult

///|
pub type AgentSetConfigOptionHandler = async (
  AgentContext,
  SetSessionConfigOptionParams,
) -> SetSessionConfigOptionResult

///|
/// Typed async authentication handlers.
pub type AgentAuthenticateHandler = async (AgentContext, AuthenticateParams) -> AuthenticateResult

///|
pub type AgentLogoutHandler = async (AgentContext, LogoutParams) -> LogoutResult

///|
/// Immutable required/optional session service.  The fields remain private so
/// callers cannot construct a half-populated service record.
pub struct AgentSessionService {
  new_handler : AgentNewSessionHandler
  prompt_handler : AgentPromptHandler
  cancel_handler : AgentCancelHandler
  load_handler : AgentLoadSessionHandler?
  resume_handler : AgentResumeSessionHandler?
  fork_handler : AgentForkSessionHandler?
  list_handler : AgentListSessionsHandler?
  delete_handler : AgentDeleteSessionHandler?
  close_handler : AgentCloseSessionHandler?
  set_mode_handler : AgentSetModeHandler?
  set_config_option_handler : AgentSetConfigOptionHandler?
}

///|
/// Compose all required session callbacks once.  Optional callbacks are
/// represented by `None`; there is no mutable registration phase.
pub fn agent_session_service(
  new_session~ : AgentNewSessionHandler,
  prompt~ : AgentPromptHandler,
  cancel~ : AgentCancelHandler,
  load? : AgentLoadSessionHandler,
  resume_session? : AgentResumeSessionHandler,
  fork_session? : AgentForkSessionHandler,
  list? : AgentListSessionsHandler,
  delete? : AgentDeleteSessionHandler,
  close? : AgentCloseSessionHandler,
  set_mode? : AgentSetModeHandler,
  set_config_option? : AgentSetConfigOptionHandler,
) -> AgentSessionService {
  {
    new_handler: new_session,
    prompt_handler: prompt,
    cancel_handler: cancel,
    load_handler: load,
    resume_handler: resume_session,
    fork_handler: fork_session,
    list_handler: list,
    delete_handler: delete,
    close_handler: close,
    set_mode_handler: set_mode,
    set_config_option_handler: set_config_option,
  }
}

///|
/// Immutable authentication service.  `methods` is copied and checked before
/// the service can be used by an endpoint.
pub struct AgentAuthService {
  methods : Array[AuthMethod]
  authenticate_handler : AgentAuthenticateHandler
  logout_handler : AgentLogoutHandler?
}

///|
pub fn agent_auth_service(
  methods~ : Array[AuthMethod],
  authenticate~ : AgentAuthenticateHandler,
  logout? : AgentLogoutHandler,
) -> AgentAuthService raise AgentCompositionError {
  if methods.length() == 0 {
    raise InvalidAuthMethods(reason="at least one method is required")
  }
  let seen : Map[String, Bool] = Map([])
  for auth_method in methods {
    if auth_method.id.length() == 0 {
      raise InvalidAuthMethods(reason="method id must not be empty")
    }
    if seen.contains(auth_method.id) {
      raise InvalidAuthMethods(reason="duplicate method id: " + auth_method.id)
    }
    seen[auth_method.id] = true
  }
  {
    methods: methods.copy(),
    authenticate_handler: authenticate,
    logout_handler: logout,
  }
}

///|
/// Non-service support declarations used to derive prompt/MCP capabilities.
/// These are immutable values, not a second manually supplied capability map.
pub struct AgentSupport {
  prompt_image : Bool
  prompt_audio : Bool
  prompt_embedded_context : Bool
  mcp_http : Bool
  mcp_sse : Bool
  additional_directories : Bool
}

///|
pub fn agent_support(
  prompt_image? : Bool = false,
  prompt_audio? : Bool = false,
  prompt_embedded_context? : Bool = false,
  mcp_http? : Bool = false,
  mcp_sse? : Bool = false,
  additional_directories? : Bool = false,
) -> AgentSupport {
  {
    prompt_image,
    prompt_audio,
    prompt_embedded_context,
    mcp_http,
    mcp_sse,
    additional_directories,
  }
}

///|
/// Immutable specification consumed by the Reader composition program.
pub struct AgentSpec {
  info : Implementation
  sessions : AgentSessionService
  support : AgentSupport
  auth : AgentAuthService?
}

///|
pub fn agent_spec(
  info~ : Implementation,
  sessions~ : AgentSessionService,
  support~ : AgentSupport,
  auth? : AgentAuthService,
) -> Result[AgentSpec, AgentCompositionError] {
  if info.name.length() == 0 {
    Err(InvalidImplementation(reason="agent name must not be empty"))
  } else if info.version.length() == 0 {
    Err(InvalidImplementation(reason="agent version must not be empty"))
  } else {
    Ok({ info, sessions, support, auth, })
  }
}
