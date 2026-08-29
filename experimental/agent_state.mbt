///|
/// The protocol version a v2 stable-baseline endpoint speaks and echoes.  A
/// v2 endpoint is v2-only: it never negotiates down, converts frames, or
/// serves a v1 peer on the same connection (plan 08 version isolation).
pub let experimental_v2_protocol_version : Int = 2

///|
/// Client→Agent requests accepted by a v2 Agent endpoint, carrying the
/// decoded params of each stable-baseline method.
pub(all) enum ExperimentalV2AgentRequest {
  Initialize(ExperimentalV2InitializeParams)
  AuthLogin(ExperimentalV2LoginParams)
  AuthLogout(ExperimentalV2LogoutParams)
  SessionNew(ExperimentalV2NewSessionParams)
  SessionPrompt(ExperimentalV2PromptParams)
  SessionList(ExperimentalV2ListSessionsParams)
  SessionDelete(ExperimentalV2DeleteSessionParams)
  SessionResume(ExperimentalV2ResumeSessionParams)
  SessionFork(ExperimentalV2ForkSessionParams)
  SessionClose(ExperimentalV2CloseSessionParams)
  SessionSetConfigOption(ExperimentalV2SetConfigOptionParams)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2AgentRequest::method_name(
  self : ExperimentalV2AgentRequest,
) -> String {
  match self {
    Initialize(_) => "initialize"
    AuthLogin(_) => "auth/login"
    AuthLogout(_) => "auth/logout"
    SessionNew(_) => "session/new"
    SessionPrompt(_) => "session/prompt"
    SessionList(_) => "session/list"
    SessionDelete(_) => "session/delete"
    SessionResume(_) => "session/resume"
    SessionFork(_) => "session/fork"
    SessionClose(_) => "session/close"
    SessionSetConfigOption(_) => "session/set_config_option"
  }
}

///|
/// Client→Agent notifications accepted by a v2 Agent endpoint.
pub(all) enum ExperimentalV2AgentNotification {
  SessionCancel(ExperimentalV2CancelSessionParams)
  CancelRequest(ExperimentalV2RequestId)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2AgentNotification::method_name(
  self : ExperimentalV2AgentNotification,
) -> String {
  match self {
    SessionCancel(_) => "session/cancel"
    CancelRequest(_) => "$/cancel_request"
  }
}

///|
/// The phase of the Agent-side v2 endpoint lifecycle.
pub(all) enum ExperimentalV2AgentPhase {
  AgentAwaitingInitialize
  AgentInitialized
} derive(Eq, Debug)

///|
/// Agent-side authentication state.  A non-empty advertised `authMethods`
/// activates the surface as `AuthPending` after `initialize`; v2 does not
/// gate session methods on authentication.
pub(all) enum ExperimentalV2AgentAuthentication {
  AuthNotAdvertised
  AuthPending
  AuthLoggedIn
} derive(Eq, Debug)

///|
/// Immutable advertisement of one v2 Agent endpoint: what its `initialize`
/// result echoes.  A non-empty `auth_methods` advertises BOTH `auth/login`
/// and `auth/logout`; `None` advertises neither and clients MUST NOT call
/// them.
pub(all) struct ExperimentalV2AgentEndpointConfig {
  info : ExperimentalV2Implementation
  capabilities : ExperimentalV2AgentCapabilities
  auth_methods : Array[ExperimentalV2AuthMethod]?
} derive(Eq, Debug)

///|
/// Immutable Agent-side v2 endpoint state.
pub(all) struct ExperimentalV2AgentState {
  phase : ExperimentalV2AgentPhase
  authentication : ExperimentalV2AgentAuthentication
  client_capabilities : ExperimentalV2ClientCapabilities
  client_info : ExperimentalV2Implementation?
  config : ExperimentalV2AgentEndpointConfig
} derive(Eq, Debug)

///|
/// Inputs accepted by the pure Agent-side v2 reducer.  Runtime effects are
/// represented by commands and completion events; this type performs no I/O.
pub(all) enum ExperimentalV2AgentEvent {
  ClientRequest(ExperimentalV2AgentRequest)
  ClientNotification(ExperimentalV2AgentNotification)
  UnknownClientMethod(method_name~ : String)
  LoginSucceeded(method_id~ : String)
  LoggedOut
} derive(Eq, Debug)

///|
/// Commands emitted by the pure v2 Agent reducer for a runtime or endpoint
/// adapter.  The reducer never executes these commands.
pub(all) enum ExperimentalV2AgentCommand {
  SendInitialize(result~ : ExperimentalV2InitializeResult, accepted~ : Bool)
  DispatchRequest(ExperimentalV2AgentRequest)
  Login(method_id~ : String)
  Logout
  CancelSession(session_id~ : String)
  CancelRequest(request_id~ : ExperimentalV2RequestId)
} derive(Eq, Debug)

///|
/// State and commands produced by one v2 Agent reducer step.
pub(all) struct ExperimentalV2AgentStep {
  state : ExperimentalV2AgentState
  commands : Array[ExperimentalV2AgentCommand]
} derive(Eq, Debug)

///|
/// Explicit failures from v2 Agent phase, negotiation, and capability gates.
pub(all) suberror ExperimentalV2AgentProtocolError {
  NotInitialized(method_name~ : String)
  AlreadyInitialized
  AuthNotAdvertised(method_name~ : String)
  AuthMethodNotAdvertised(method_id~ : String)
  AlreadyLoggedIn
  NotLoggedIn
  CapabilityDenied(method_name~ : String, capability~ : String)
  UnknownMethod(method_name~ : String)
} derive(Eq, Debug)

///|
/// Fail-fast construction failures of the advertised v2 Agent method set.
pub(all) suberror ExperimentalV2AgentStateError {
  EmptyAuthMethods
  DuplicateAuthMethodId(method_id~ : String)
} derive(Eq, Debug)

///|
/// Construct a fresh v2 Agent endpoint state, validating the advertised
/// method set fail-fast.  `auth_methods` must be `None` (surface absent) or a
/// duplicate-free non-empty list; a present-but-empty list is an ambiguous
/// advertisement, not a silent "no auth".
pub fn experimental_v2_agent_state_new(
  config~ : ExperimentalV2AgentEndpointConfig,
) -> ExperimentalV2AgentState raise ExperimentalV2AgentStateError {
  match config.auth_methods {
    None => ()
    Some(methods) => {
      if methods.is_empty() {
        raise EmptyAuthMethods
      }
      let seen : Map[String, Bool] = Map([])
      for entry in methods {
        match entry {
          Known(agent) =>
            if seen.contains(agent.method_id) {
              raise DuplicateAuthMethodId(method_id=agent.method_id)
            } else {
              seen[agent.method_id] = true
            }
          Extension(..) | Future(..) => ()
        }
      }
    }
  }
  {
    phase: AgentAwaitingInitialize,
    authentication: AuthNotAdvertised,
    client_capabilities: { elicitation: MarkerUnsupported, meta: None, },
    client_info: None,
    config,
  }
}

///|
fn experimental_v2_agent_require_initialized(
  state : ExperimentalV2AgentState,
  method_name : String,
) -> Unit raise ExperimentalV2AgentProtocolError {
  match state.phase {
    AgentAwaitingInitialize => raise NotInitialized(method_name~)
    AgentInitialized => ()
  }
}

///|
fn experimental_v2_agent_require_capability(
  supported : Bool,
  method_name : String,
  capability : String,
) -> Unit raise ExperimentalV2AgentProtocolError {
  if !supported {
    raise CapabilityDenied(method_name~, capability~)
  }
}

///|
/// Walk `session` → `group` → `leaf`; every marker level must be supported
/// for the gate to open.  Omitted and null markers collapse to unsupported.
fn[A, B] experimental_v2_agent_session_nested(
  state : ExperimentalV2AgentState,
  group : (ExperimentalV2SessionCapabilities) -> ExperimentalV2Marker[A],
  leaf : (A) -> ExperimentalV2Marker[B],
) -> Bool {
  match state.config.capabilities.session {
    MarkerSupported(session) =>
      match group(session) {
        MarkerSupported(group) =>
          match leaf(group) {
            MarkerSupported(_) => true
            MarkerUnsupported => false
          }
        MarkerUnsupported => false
      }
    MarkerUnsupported => false
  }
}

///|
fn experimental_v2_agent_delete_supported(
  state : ExperimentalV2AgentState,
) -> Bool {
  experimental_v2_agent_session_nested(
    state,
    session => MarkerSupported(session),
    session => session.delete,
  )
}

///|
fn experimental_v2_agent_additional_directories_supported(
  state : ExperimentalV2AgentState,
) -> Bool {
  experimental_v2_agent_session_nested(
    state,
    session => MarkerSupported(session),
    session => session.additional_directories,
  )
}

///|
/// Upstream unstable (RFD session-fork, Draft): the `session.fork` marker of
/// the pinned v2 unstable overlay, gated exactly like `session.delete`.
fn experimental_v2_agent_fork_supported(
  state : ExperimentalV2AgentState,
) -> Bool {
  experimental_v2_agent_session_nested(
    state,
    session => MarkerSupported(session),
    session => session.fork,
  )
}

///|
fn experimental_v2_agent_prompt_block_supported(
  state : ExperimentalV2AgentState,
  select : (ExperimentalV2PromptCapabilities) -> ExperimentalV2Marker[
    ExperimentalV2MarkerPayload,
  ],
) -> Bool {
  experimental_v2_agent_session_nested(state, session => session.prompt, select)
}

///|
fn experimental_v2_agent_mcp_transport_supported(
  state : ExperimentalV2AgentState,
  select : (ExperimentalV2McpCapabilities) -> ExperimentalV2Marker[
    ExperimentalV2MarkerPayload,
  ],
) -> Bool {
  experimental_v2_agent_session_nested(state, session => session.mcp, select)
}

///|
fn experimental_v2_agent_check_additional_directories(
  state : ExperimentalV2AgentState,
  method_name : String,
  directories : Array[String]?,
) -> Unit raise ExperimentalV2AgentProtocolError {
  match directories {
    Some(_) =>
      experimental_v2_agent_require_capability(
        experimental_v2_agent_additional_directories_supported(state),
        method_name,
        "session.additionalDirectories",
      )
    None => ()
  }
}

///|
/// Known transports gate on `session.mcp.stdio`/`session.mcp.http`; an
/// extension or future transport has no marker in this baseline and is
/// always denied, never guessed.
fn experimental_v2_agent_check_mcp_servers(
  state : ExperimentalV2AgentState,
  method_name : String,
  servers : Array[ExperimentalV2McpServer],
) -> Unit raise ExperimentalV2AgentProtocolError {
  for server in servers {
    match server {
      Known(TransportStdio(_)) =>
        experimental_v2_agent_require_capability(
          experimental_v2_agent_mcp_transport_supported(state, mcp => mcp.stdio),
          method_name,
          "session.mcp.stdio",
        )
      Known(TransportHttp(_)) =>
        experimental_v2_agent_require_capability(
          experimental_v2_agent_mcp_transport_supported(state, mcp => mcp.http),
          method_name,
          "session.mcp.http",
        )
      Extension(tag~, ..) | Future(tag~, ..) =>
        experimental_v2_agent_require_capability(
          false,
          method_name,
          "session.mcp." + tag,
        )
    }
  }
}

///|
/// Baseline blocks (`text`, `resource_link`) always pass; the other known
/// kinds gate on their prompt marker and extension/future kinds have no
/// marker to open them.
fn experimental_v2_agent_check_prompt_blocks(
  state : ExperimentalV2AgentState,
  method_name : String,
  blocks : Array[ExperimentalV2ContentBlock],
) -> Unit raise ExperimentalV2AgentProtocolError {
  for block in blocks {
    match block {
      Known(BlockText(_)) | Known(BlockResourceLink(_)) => ()
      Known(BlockImage(_)) =>
        experimental_v2_agent_require_capability(
          experimental_v2_agent_prompt_block_supported(state, prompt => {
            prompt.image
          }),
          method_name,
          "prompt.image",
        )
      Known(BlockAudio(_)) =>
        experimental_v2_agent_require_capability(
          experimental_v2_agent_prompt_block_supported(state, prompt => {
            prompt.audio
          }),
          method_name,
          "prompt.audio",
        )
      Known(BlockResource(_)) =>
        experimental_v2_agent_require_capability(
          experimental_v2_agent_prompt_block_supported(state, prompt => {
            prompt.embedded_context
          }),
          method_name,
          "prompt.embeddedContext",
        )
      Extension(tag~, ..) | Future(tag~, ..) =>
        experimental_v2_agent_require_capability(
          false,
          method_name,
          "prompt." + tag,
        )
    }
  }
}

///|
/// The auth surface is active only for a non-empty advertised `authMethods`
/// list; `None` and `Some([])` both mean clients MUST NOT call login/logout.
fn experimental_v2_agent_auth_advertised(
  config : ExperimentalV2AgentEndpointConfig,
) -> Bool {
  match config.auth_methods {
    Some(methods) => !methods.is_empty()
    None => false
  }
}

///|
/// Only known `agent`-typed methods carry an addressable `methodId`;
/// extension/future methods cannot be validated and are never matched.
fn experimental_v2_agent_auth_method_advertised(
  state : ExperimentalV2AgentState,
  method_id : String,
) -> Bool {
  match state.config.auth_methods {
    Some(methods) => {
      for entry in methods {
        match entry {
          Known(agent) => if agent.method_id == method_id { return true }
          Extension(..) | Future(..) => ()
        }
      }
      false
    }
    None => false
  }
}

///|
fn experimental_v2_agent_authentication_after_initialize(
  config : ExperimentalV2AgentEndpointConfig,
) -> ExperimentalV2AgentAuthentication {
  if experimental_v2_agent_auth_advertised(config) {
    AuthPending
  } else {
    AuthNotAdvertised
  }
}

///|
fn experimental_v2_agent_initialize_result(
  config : ExperimentalV2AgentEndpointConfig,
) -> ExperimentalV2InitializeResult {
  {
    protocol_version: experimental_v2_protocol_version,
    info: config.info,
    capabilities: config.capabilities,
    auth_methods: config.auth_methods,
    meta: None,
  }
}

///|
/// v2 negotiation: only `protocolVersion == 2` enters `AgentInitialized`.
/// Any other offered version is answered with this endpoint's own version 2
/// (`accepted=false`) and the endpoint stays pre-initialized; a peer that
/// cannot use 2 must close and reconnect through a v1 endpoint.  There is no
/// downgrade and no frame conversion.
fn experimental_v2_agent_reduce_initialize(
  state : ExperimentalV2AgentState,
  params : ExperimentalV2InitializeParams,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  match state.phase {
    AgentInitialized => raise AlreadyInitialized
    AgentAwaitingInitialize => {
      let result = experimental_v2_agent_initialize_result(state.config)
      if params.protocol_version == experimental_v2_protocol_version {
        let next_state = {
          ..state,
          phase: AgentInitialized,
          authentication: experimental_v2_agent_authentication_after_initialize(
            state.config,
          ),
          client_capabilities: params.capabilities,
          client_info: Some(params.info),
        }
        {
          state: next_state,
          commands: [SendInitialize(result~, accepted=true)],
        }
      } else {
        { state, commands: [SendInitialize(result~, accepted=false)], }
      }
    }
  }
}

///|
fn experimental_v2_agent_reduce_login(
  state : ExperimentalV2AgentState,
  params : ExperimentalV2LoginParams,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  match state.authentication {
    AuthNotAdvertised => raise AuthNotAdvertised(method_name="auth/login")
    AuthLoggedIn => raise AlreadyLoggedIn
    AuthPending => {
      if !experimental_v2_agent_auth_method_advertised(state, params.method_id) {
        raise AuthMethodNotAdvertised(method_id=params.method_id)
      }
      { state, commands: [Login(method_id=params.method_id)], }
    }
  }
}

///|
fn experimental_v2_agent_reduce_logout(
  state : ExperimentalV2AgentState,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  match state.authentication {
    AuthNotAdvertised => raise AuthNotAdvertised(method_name="auth/logout")
    AuthPending => raise NotLoggedIn
    AuthLoggedIn => { state, commands: [Logout], }
  }
}

///|
fn experimental_v2_agent_reduce_request_initialized(
  state : ExperimentalV2AgentState,
  request : ExperimentalV2AgentRequest,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  match request {
    Initialize(_) => raise AlreadyInitialized
    AuthLogin(params) => experimental_v2_agent_reduce_login(state, params)
    AuthLogout(_) => experimental_v2_agent_reduce_logout(state)
    SessionNew(params) => {
      experimental_v2_agent_check_additional_directories(
        state,
        "session/new",
        params.additional_directories,
      )
      match params.mcp_servers {
        Some(servers) =>
          experimental_v2_agent_check_mcp_servers(state, "session/new", servers)
        None => ()
      }
      { state, commands: [DispatchRequest(request)], }
    }
    SessionPrompt(params) => {
      experimental_v2_agent_check_prompt_blocks(
        state,
        "session/prompt",
        params.prompt,
      )
      { state, commands: [DispatchRequest(request)], }
    }
    SessionList(_) | SessionClose(_) | SessionSetConfigOption(_) =>
      { state, commands: [DispatchRequest(request)], }
    SessionDelete(_) => {
      experimental_v2_agent_require_capability(
        experimental_v2_agent_delete_supported(state),
        "session/delete",
        "session.delete",
      )
      { state, commands: [DispatchRequest(request)], }
    }
    SessionResume(params) => {
      experimental_v2_agent_check_additional_directories(
        state,
        "session/resume",
        params.additional_directories,
      )
      match params.mcp_servers {
        Some(servers) =>
          experimental_v2_agent_check_mcp_servers(
            state, "session/resume", servers,
          )
        None => ()
      }
      { state, commands: [DispatchRequest(request)], }
    }
    SessionFork(params) => {
      experimental_v2_agent_require_capability(
        experimental_v2_agent_fork_supported(state),
        "session/fork",
        "session.fork",
      )
      experimental_v2_agent_check_additional_directories(
        state,
        "session/fork",
        params.additional_directories,
      )
      match params.mcp_servers {
        Some(servers) =>
          experimental_v2_agent_check_mcp_servers(
            state, "session/fork", servers,
          )
        None => ()
      }
      { state, commands: [DispatchRequest(request)], }
    }
  }
}

///|
fn experimental_v2_agent_reduce_notification(
  state : ExperimentalV2AgentState,
  notification : ExperimentalV2AgentNotification,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  let method_name = ExperimentalV2AgentNotification::method_name(notification)
  experimental_v2_agent_require_initialized(state, method_name)
  match notification {
    SessionCancel(params) =>
      { state, commands: [CancelSession(session_id=params.session_id)], }
    CancelRequest(request_id) =>
      { state, commands: [CancelRequest(request_id~)], }
  }
}

///|
fn experimental_v2_agent_reduce_login_succeeded(
  state : ExperimentalV2AgentState,
  method_id : String,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  experimental_v2_agent_require_initialized(state, "auth/login")
  if !experimental_v2_agent_auth_method_advertised(state, method_id) {
    raise AuthMethodNotAdvertised(method_id~)
  }
  match state.authentication {
    AuthNotAdvertised => raise AuthNotAdvertised(method_name="auth/login")
    AuthLoggedIn => raise AlreadyLoggedIn
    AuthPending =>
      { state: { ..state, authentication: AuthLoggedIn, }, commands: [], }
  }
}

///|
fn experimental_v2_agent_reduce_logged_out(
  state : ExperimentalV2AgentState,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  experimental_v2_agent_require_initialized(state, "auth/logout")
  match state.authentication {
    AuthNotAdvertised => raise AuthNotAdvertised(method_name="auth/logout")
    AuthPending => raise NotLoggedIn
    AuthLoggedIn =>
      { state: { ..state, authentication: AuthPending, }, commands: [], }
  }
}

///|
/// Reduce one typed Agent-side v2 event without performing any I/O.
pub fn experimental_v2_agent_reduce(
  state : ExperimentalV2AgentState,
  event : ExperimentalV2AgentEvent,
) -> ExperimentalV2AgentStep raise ExperimentalV2AgentProtocolError {
  match event {
    ClientRequest(request) =>
      match request {
        Initialize(params) =>
          experimental_v2_agent_reduce_initialize(state, params)
        _ => {
          let method_name = request.method_name()
          experimental_v2_agent_require_initialized(state, method_name)
          experimental_v2_agent_reduce_request_initialized(state, request)
        }
      }
    ClientNotification(notification) =>
      experimental_v2_agent_reduce_notification(state, notification)
    UnknownClientMethod(method_name~) => raise UnknownMethod(method_name~)
    LoginSucceeded(method_id~) =>
      experimental_v2_agent_reduce_login_succeeded(state, method_id)
    LoggedOut => experimental_v2_agent_reduce_logged_out(state)
  }
}
