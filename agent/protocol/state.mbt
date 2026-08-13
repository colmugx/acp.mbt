///|
using @agent_message {type AgentRequest, type AgentNotification}

///|
using @jsonrpc {type RequestId}

///|
using @protocol_data {
  type ProtocolNullable,
  type AgentCapabilities,
  type AuthMethod,
  type Implementation,
  type ClientCapabilities,
  type InitializeParams,
  type InitializeResult,
  type AuthenticateParams,
  type SessionId,
  type McpServer,
  type ContentBlock,
}

///|
/// The phase of the Agent-side v1 protocol handshake.
pub(all) enum AgentProtocolPhase {
  AwaitingInitialize
  Initialized
} derive(Eq, Debug)

///|
/// Authentication is explicit state, not an implicit capability fallback.
pub(all) enum AgentAuthenticationState {
  NotRequired
  AwaitingAuthentication
  Authenticated
} derive(Eq, Debug)

///|
/// Immutable information an Agent endpoint advertises during initialization.
///
/// `Omitted` and `Null` are preserved so that an endpoint can intentionally
/// advertise that a capability or authentication list is unavailable.  Gate
/// checks treat both forms as unsupported.
pub(all) struct AgentProtocolConfig {
  agent_capabilities : ProtocolNullable[AgentCapabilities]
  auth_methods : ProtocolNullable[Array[AuthMethod]]
  agent_info : ProtocolNullable[Implementation]
} derive(Eq, Debug)

///|
/// Immutable Agent-side protocol state.
pub(all) struct AgentProtocolState {
  phase : AgentProtocolPhase
  protocol_version : ProtocolNullable[Int]
  client_capabilities : ProtocolNullable[ClientCapabilities]
  client_info : ProtocolNullable[Implementation]
  authentication : AgentAuthenticationState
  config : AgentProtocolConfig
} derive(Eq, Debug)

///|
/// Inputs accepted by the pure protocol reducer.  Runtime effects are
/// represented by commands and completion events; this type performs no I/O.
pub(all) enum AgentProtocolEvent {
  Request(AgentRequest)
  Notification(AgentNotification)
  AuthenticationSucceeded(method_id~ : String)
  LoggedOut
} derive(Eq, Debug)

///|
/// Commands emitted by the pure reducer for a runtime or endpoint adapter.
/// The reducer never executes these commands.
pub(all) enum AgentProtocolCommand {
  SendInitialize(result~ : InitializeResult, accepted~ : Bool)
  DispatchRequest(AgentRequest)
  DispatchNotification(AgentNotification)
  Authenticate(method_id~ : String)
  Logout
  CancelSession(session_id~ : SessionId)
  CancelRequest(request_id~ : RequestId)
} derive(Eq, Debug)

///|
/// State and commands produced by one reducer step.
pub(all) struct AgentProtocolStep {
  state : AgentProtocolState
  commands : Array[AgentProtocolCommand]
} derive(Eq, Debug)

///|
/// Explicit failures from protocol phase and capability gates.
pub(all) suberror AgentProtocolError {
  NotInitialized(method_name~ : String)
  AlreadyInitialized
  CapabilityDenied(method_name~ : String, capability~ : String)
  AuthenticationRequired(method_name~ : String)
  AuthenticationMethodNotAdvertised(method_id~ : String)
  AuthenticationNotRequired
  AlreadyAuthenticated
  NotAuthenticated
  InvalidEvent(reason~ : String)
} derive(Eq, Debug)

///|
/// Construct a fresh state for one Agent endpoint.
pub fn agent_protocol_state_new(
  config~ : AgentProtocolConfig,
) -> AgentProtocolState {
  {
    phase: AwaitingInitialize,
    protocol_version: Omitted,
    client_capabilities: Omitted,
    client_info: Omitted,
    authentication: NotRequired,
    config,
  }
}

///|
fn agent_authentication_after_initialize(
  auth_methods : ProtocolNullable[Array[AuthMethod]],
) -> AgentAuthenticationState {
  match auth_methods {
    Value(methods) =>
      if methods.length() == 0 {
        NotRequired
      } else {
        AwaitingAuthentication
      }
    Omitted | Null => NotRequired
  }
}

///|
fn agent_initialize_result(config : AgentProtocolConfig) -> InitializeResult {
  {
    protocol_version: 1,
    agent_capabilities: config.agent_capabilities,
    auth_methods: config.auth_methods,
    agent_info: config.agent_info,
    meta: Omitted,
  }
}

///|
fn agent_capabilities(
  state : AgentProtocolState,
) -> ProtocolNullable[AgentCapabilities] {
  state.config.agent_capabilities
}

///|
fn agent_load_session_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.load_session {
        Value(true) => true
        Omitted | Null | Value(false) => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_prompt_image_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.prompt_capabilities {
        Value(prompt) =>
          match prompt.image {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_prompt_audio_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.prompt_capabilities {
        Value(prompt) =>
          match prompt.audio {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_prompt_embedded_context_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.prompt_capabilities {
        Value(prompt) =>
          match prompt.embedded_context {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_mcp_http_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.mcp_capabilities {
        Value(mcp) =>
          match mcp.http {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_mcp_sse_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.mcp_capabilities {
        Value(mcp) =>
          match mcp.sse {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_logout_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.auth {
        Value(auth) =>
          match auth.logout {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_list_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.session_capabilities {
        Value(session) =>
          match session.list {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_delete_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.session_capabilities {
        Value(session) =>
          match session.delete {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_resume_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.session_capabilities {
        Value(session) =>
          match session.resume_capability {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_close_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.session_capabilities {
        Value(session) =>
          match session.close {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_additional_directories_supported(state : AgentProtocolState) -> Bool {
  match agent_capabilities(state) {
    Value(capabilities) =>
      match capabilities.session_capabilities {
        Value(session) =>
          match session.additional_directories {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_client_boolean_config_supported(state : AgentProtocolState) -> Bool {
  match state.client_capabilities {
    Value(capabilities) =>
      match capabilities.session {
        Value(session) =>
          match session.config_options {
            Value(config_options) =>
              match config_options.boolean {
                Value(_) => true
                Omitted | Null => false
              }
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn agent_require_initialized(
  state : AgentProtocolState,
  method_name : String,
) -> Unit raise AgentProtocolError {
  match state.phase {
    AwaitingInitialize => raise NotInitialized(method_name~)
    Initialized => ()
  }
}

///|
fn agent_require_authenticated(
  state : AgentProtocolState,
  method_name : String,
) -> Unit raise AgentProtocolError {
  match state.authentication {
    NotRequired | Authenticated => ()
    AwaitingAuthentication => raise AuthenticationRequired(method_name~)
  }
}

///|
fn agent_require_capability(
  supported : Bool,
  method_name : String,
  capability : String,
) -> Unit raise AgentProtocolError {
  if !supported {
    raise CapabilityDenied(method_name~, capability~)
  }
}

///|
fn agent_check_additional_directories(
  state : AgentProtocolState,
  method_name : String,
  directories : ProtocolNullable[Array[String]],
) -> Unit raise AgentProtocolError {
  match directories {
    Value(_) =>
      agent_require_capability(
        agent_additional_directories_supported(state),
        method_name,
        "session.additionalDirectories",
      )
    Omitted | Null => ()
  }
}

///|
fn agent_check_mcp_servers(
  state : AgentProtocolState,
  method_name : String,
  servers : Array[McpServer],
) -> Unit raise AgentProtocolError {
  for server in servers {
    match server {
      Stdio(_) => ()
      Http(_) =>
        agent_require_capability(
          agent_mcp_http_supported(state),
          method_name,
          "mcp.http",
        )
      Sse(_) =>
        agent_require_capability(
          agent_mcp_sse_supported(state),
          method_name,
          "mcp.sse",
        )
    }
  }
}

///|
fn agent_check_prompt_blocks(
  state : AgentProtocolState,
  method_name : String,
  blocks : Array[ContentBlock],
) -> Unit raise AgentProtocolError {
  for block in blocks {
    match block {
      Text(_) | ResourceLink(_) => ()
      Image(_) =>
        agent_require_capability(
          agent_prompt_image_supported(state),
          method_name,
          "prompt.image",
        )
      Audio(_) =>
        agent_require_capability(
          agent_prompt_audio_supported(state),
          method_name,
          "prompt.audio",
        )
      Resource(_) =>
        agent_require_capability(
          agent_prompt_embedded_context_supported(state),
          method_name,
          "prompt.embeddedContext",
        )
    }
  }
}

///|
fn agent_auth_method_advertised(
  state : AgentProtocolState,
  method_id : String,
) -> Bool {
  match state.config.auth_methods {
    Value(methods) => {
      for auth_method in methods {
        if auth_method.id == method_id {
          return true
        }
      }
      false
    }
    Omitted | Null => false
  }
}

///|
fn agent_reduce_initialize(
  state : AgentProtocolState,
  params : InitializeParams,
) -> AgentProtocolStep raise AgentProtocolError {
  match state.phase {
    Initialized => raise AlreadyInitialized
    AwaitingInitialize => {
      let result = agent_initialize_result(state.config)
      if params.protocol_version == 1 {
        let next_state = {
          ..state,
          phase: Initialized,
          protocol_version: Value(1),
          client_capabilities: params.client_capabilities,
          client_info: params.client_info,
          authentication: agent_authentication_after_initialize(
            state.config.auth_methods,
          ),
        }
        {
          state: next_state,
          commands: [SendInitialize(result~, accepted=true)],
        }
      } else {
        // The peer receives the latest supported version and decides whether
        // to disconnect.  The Agent remains pre-initialized until a v1
        // initialize request is received.
        { state, commands: [SendInitialize(result~, accepted=false)] }
      }
    }
  }
}

///|
fn agent_reduce_authenticate(
  state : AgentProtocolState,
  params : AuthenticateParams,
) -> AgentProtocolStep raise AgentProtocolError {
  match state.authentication {
    NotRequired => raise AuthenticationNotRequired
    Authenticated => raise AlreadyAuthenticated
    AwaitingAuthentication => {
      if !agent_auth_method_advertised(state, params.method_id) {
        raise AuthenticationMethodNotAdvertised(method_id=params.method_id)
      }
      { state, commands: [Authenticate(method_id=params.method_id)] }
    }
  }
}

///|
fn agent_reduce_logout(
  state : AgentProtocolState,
) -> AgentProtocolStep raise AgentProtocolError {
  agent_require_capability(
    agent_logout_supported(state),
    "logout",
    "auth.logout",
  )
  agent_require_authenticated(state, "logout")
  { state, commands: [Logout] }
}

///|
fn agent_reduce_request_initialized(
  state : AgentProtocolState,
  request : AgentRequest,
) -> AgentProtocolStep raise AgentProtocolError {
  match request {
    Initialize(_) => raise AlreadyInitialized
    Authenticate(params) => agent_reduce_authenticate(state, params)
    Logout(_) => agent_reduce_logout(state)
    SessionNew(params) => {
      agent_require_authenticated(state, "session/new")
      agent_check_additional_directories(
        state,
        "session/new",
        params.additional_directories,
      )
      agent_check_mcp_servers(state, "session/new", params.mcp_servers)
      { state, commands: [DispatchRequest(request)] }
    }
    SessionLoad(params) => {
      agent_require_authenticated(state, "session/load")
      agent_require_capability(
        agent_load_session_supported(state),
        "session/load",
        "loadSession",
      )
      agent_check_additional_directories(
        state,
        "session/load",
        params.additional_directories,
      )
      agent_check_mcp_servers(state, "session/load", params.mcp_servers)
      { state, commands: [DispatchRequest(request)] }
    }
    SessionResume(params) => {
      agent_require_authenticated(state, "session/resume")
      agent_require_capability(
        agent_resume_supported(state),
        "session/resume",
        "session.resume",
      )
      agent_check_additional_directories(
        state,
        "session/resume",
        params.additional_directories,
      )
      match params.mcp_servers {
        Value(servers) =>
          agent_check_mcp_servers(state, "session/resume", servers)
        Omitted | Null => ()
      }
      { state, commands: [DispatchRequest(request)] }
    }
    SessionList(_) => {
      agent_require_authenticated(state, "session/list")
      agent_require_capability(
        agent_list_supported(state),
        "session/list",
        "session.list",
      )
      { state, commands: [DispatchRequest(request)] }
    }
    SessionDelete(_) => {
      agent_require_authenticated(state, "session/delete")
      agent_require_capability(
        agent_delete_supported(state),
        "session/delete",
        "session.delete",
      )
      { state, commands: [DispatchRequest(request)] }
    }
    SessionClose(_) => {
      agent_require_authenticated(state, "session/close")
      agent_require_capability(
        agent_close_supported(state),
        "session/close",
        "session.close",
      )
      { state, commands: [DispatchRequest(request)] }
    }
    SessionSetMode(_) => {
      agent_require_authenticated(state, "session/set_mode")
      { state, commands: [DispatchRequest(request)] }
    }
    SessionSetConfigOption(params) => {
      agent_require_authenticated(state, "session/set_config_option")
      match params.value {
        Boolean(_) =>
          agent_require_capability(
            agent_client_boolean_config_supported(state),
            "session/set_config_option",
            "session.configOptions.boolean",
          )
        ValueId(_) => ()
      }
      { state, commands: [DispatchRequest(request)] }
    }
    SessionPrompt(params) => {
      agent_require_authenticated(state, "session/prompt")
      agent_check_prompt_blocks(state, "session/prompt", params.prompt)
      { state, commands: [DispatchRequest(request)] }
    }
  }
}

///|
fn agent_reduce_request(
  state : AgentProtocolState,
  request : AgentRequest,
) -> AgentProtocolStep raise AgentProtocolError {
  match request {
    Initialize(params) => agent_reduce_initialize(state, params)
    _ => {
      let method_name = request.method_name()
      agent_require_initialized(state, method_name)
      agent_reduce_request_initialized(state, request)
    }
  }
}

///|
fn agent_reduce_notification(
  state : AgentProtocolState,
  notification : AgentNotification,
) -> AgentProtocolStep raise AgentProtocolError {
  let method_name = notification.method_name()
  agent_require_initialized(state, method_name)
  match notification {
    SessionCancel(params) => {
      agent_require_authenticated(state, method_name)
      { state, commands: [CancelSession(session_id=params.session_id)] }
    }
    CancelRequest(request_id) =>
      { state, commands: [CancelRequest(request_id~)] }
  }
}

///|
fn agent_reduce_authentication_succeeded(
  state : AgentProtocolState,
  method_id : String,
) -> AgentProtocolStep raise AgentProtocolError {
  agent_require_initialized(state, "authenticate")
  if !agent_auth_method_advertised(state, method_id) {
    raise AuthenticationMethodNotAdvertised(method_id~)
  }
  match state.authentication {
    NotRequired => raise AuthenticationNotRequired
    Authenticated => raise AlreadyAuthenticated
    AwaitingAuthentication =>
      { state: { ..state, authentication: Authenticated }, commands: [] }
  }
}

///|
fn agent_reduce_logged_out(
  state : AgentProtocolState,
) -> AgentProtocolStep raise AgentProtocolError {
  agent_require_initialized(state, "logout")
  match state.authentication {
    NotRequired => raise NotAuthenticated
    AwaitingAuthentication => raise NotAuthenticated
    Authenticated =>
      {
        state: {
          ..state,
          authentication: agent_authentication_after_initialize(
            state.config.auth_methods,
          ),
        },
        commands: [],
      }
  }
}

///|
/// Reduce one typed Agent protocol event without performing any I/O.
pub fn agent_protocol_reduce(
  state : AgentProtocolState,
  event : AgentProtocolEvent,
) -> AgentProtocolStep raise AgentProtocolError {
  match event {
    Request(request) => agent_reduce_request(state, request)
    Notification(notification) => agent_reduce_notification(state, notification)
    AuthenticationSucceeded(method_id~) =>
      agent_reduce_authentication_succeeded(state, method_id)
    LoggedOut => agent_reduce_logged_out(state)
  }
}
