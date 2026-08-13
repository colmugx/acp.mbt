///|
/// An opaque, fully validated Agent endpoint.  It contains immutable service
/// closures and derived initialization data, never connection-scoped state.
pub struct AgentEndpoint {
  info : Implementation
  sessions : AgentSessionService
  auth : AgentAuthService?
  capabilities : AgentCapabilities
  auth_methods : ProtocolNullable[Array[AuthMethod]]
}

///|
fn agent_endpoint_marker(enabled : Bool) -> ProtocolNullable[CapabilityMarker] {
  if enabled {
    Value({ meta: Omitted })
  } else {
    Omitted
  }
}

///|
fn agent_endpoint_prompt_capabilities(
  support : AgentSupport,
) -> ProtocolNullable[AgentPromptCapabilities] {
  if support.prompt_image ||
    support.prompt_audio ||
    support.prompt_embedded_context {
    Value({
      image: if support.prompt_image {
        Value(true)
      } else {
        Omitted
      },
      audio: if support.prompt_audio {
        Value(true)
      } else {
        Omitted
      },
      embedded_context: if support.prompt_embedded_context {
        Value(true)
      } else {
        Omitted
      },
      meta: Omitted,
    })
  } else {
    Omitted
  }
}

///|
fn agent_endpoint_mcp_capabilities(
  support : AgentSupport,
) -> ProtocolNullable[AgentMcpCapabilities] {
  if support.mcp_http || support.mcp_sse {
    Value({
      http: if support.mcp_http {
        Value(true)
      } else {
        Omitted
      },
      sse: if support.mcp_sse {
        Value(true)
      } else {
        Omitted
      },
      meta: Omitted,
    })
  } else {
    Omitted
  }
}

///|
fn agent_endpoint_session_capabilities(
  spec : AgentSpec,
) -> ProtocolNullable[AgentSessionCapabilities] {
  let sessions = spec.sessions
  let list = sessions.list_handler is Some(_)
  let delete = sessions.delete_handler is Some(_)
  let resume_capable = sessions.resume_handler is Some(_)
  let close = sessions.close_handler is Some(_)
  let additional_directories = spec.support.additional_directories
  if list || delete || resume_capable || close || additional_directories {
    Value({
      list: agent_endpoint_marker(list),
      delete: agent_endpoint_marker(delete),
      resume_capability: agent_endpoint_marker(resume_capable),
      close: agent_endpoint_marker(close),
      additional_directories: agent_endpoint_marker(additional_directories),
      meta: Omitted,
    })
  } else {
    Omitted
  }
}

///|
fn agent_endpoint_auth_capabilities(
  auth : AgentAuthService?,
) -> ProtocolNullable[AgentAuthCapabilities] {
  match auth {
    Some(auth) =>
      Value({
        logout: agent_endpoint_marker(auth.logout_handler is Some(_)),
        meta: Omitted,
      })
    None => Omitted
  }
}

///|
fn agent_endpoint_capabilities(spec : AgentSpec) -> AgentCapabilities {
  {
    load_session: if spec.sessions.load_handler is Some(_) {
      Value(true)
    } else {
      Omitted
    },
    prompt_capabilities: agent_endpoint_prompt_capabilities(spec.support),
    mcp_capabilities: agent_endpoint_mcp_capabilities(spec.support),
    auth: agent_endpoint_auth_capabilities(spec.auth),
    session_capabilities: agent_endpoint_session_capabilities(spec),
    meta: Omitted,
  }
}

///|
pub fn agent_endpoint_from_spec(spec : AgentSpec) -> AgentEndpoint {
  let auth_methods = match spec.auth {
    Some(auth) => @protocol_data.ProtocolNullable::Value(auth.methods.copy())
    None => Omitted
  }
  {
    info: spec.info,
    sessions: spec.sessions,
    auth: spec.auth,
    capabilities: agent_endpoint_capabilities(spec),
    auth_methods,
  }
}

///|
/// Return the immutable implementation information for initialization.
pub fn AgentEndpoint::info(self : AgentEndpoint) -> Implementation {
  self.info
}

///|
/// Return capabilities derived from service presence and support values.
pub fn AgentEndpoint::capabilities(self : AgentEndpoint) -> AgentCapabilities {
  self.capabilities
}

///|
/// Return a defensive copy of the advertised authentication methods.
pub fn AgentEndpoint::auth_methods(
  self : AgentEndpoint,
) -> ProtocolNullable[Array[AuthMethod]] {
  match self.auth_methods {
    Omitted => Omitted
    Null => Null
    Value(methods) => Value(methods.copy())
  }
}

///|
/// Invoke the required typed `session/new` handler.
pub async fn AgentEndpoint::new_session(
  self : AgentEndpoint,
  context : AgentContext,
  params : NewSessionParams,
) -> NewSessionResult raise HandlerError {
  agent_handler_call("session/new", async fn() {
    (self.sessions.new_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/prompt` handler.
pub async fn AgentEndpoint::prompt(
  self : AgentEndpoint,
  context : AgentContext,
  params : PromptParams,
) -> PromptResult raise HandlerError {
  agent_handler_call("session/prompt", async fn() {
    (self.sessions.prompt_handler)(context, params)
  })
}

///|
/// Invoke the required typed `session/cancel` handler.
pub async fn AgentEndpoint::cancel(
  self : AgentEndpoint,
  context : AgentContext,
  params : CancelParams,
) -> Unit raise HandlerError {
  agent_handler_call("session/cancel", async fn() {
    (self.sessions.cancel_handler)(context, params)
  })
}

///|
pub async fn AgentEndpoint::load_session(
  self : AgentEndpoint,
  context : AgentContext,
  params : LoadSessionParams,
) -> LoadSessionResult raise HandlerError {
  match self.sessions.load_handler {
    Some(handler) =>
      agent_handler_call("session/load", async fn() { handler(context, params) })
    None => raise UnavailableOperation(method_name="session/load")
  }
}

///|
pub async fn AgentEndpoint::resume_session(
  self : AgentEndpoint,
  context : AgentContext,
  params : ResumeSessionParams,
) -> ResumeSessionResult raise HandlerError {
  match self.sessions.resume_handler {
    Some(handler) =>
      agent_handler_call("session/resume", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/resume")
  }
}

///|
pub async fn AgentEndpoint::list_sessions(
  self : AgentEndpoint,
  context : AgentContext,
  params : ListSessionsParams,
) -> ListSessionsResult raise HandlerError {
  match self.sessions.list_handler {
    Some(handler) =>
      agent_handler_call("session/list", async fn() { handler(context, params) })
    None => raise UnavailableOperation(method_name="session/list")
  }
}

///|
pub async fn AgentEndpoint::delete_session(
  self : AgentEndpoint,
  context : AgentContext,
  params : DeleteSessionParams,
) -> DeleteSessionResult raise HandlerError {
  match self.sessions.delete_handler {
    Some(handler) =>
      agent_handler_call("session/delete", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/delete")
  }
}

///|
pub async fn AgentEndpoint::close_session(
  self : AgentEndpoint,
  context : AgentContext,
  params : CloseSessionParams,
) -> CloseSessionResult raise HandlerError {
  match self.sessions.close_handler {
    Some(handler) =>
      agent_handler_call("session/close", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/close")
  }
}

///|
pub async fn AgentEndpoint::set_mode(
  self : AgentEndpoint,
  context : AgentContext,
  params : SetSessionModeParams,
) -> SetSessionModeResult raise HandlerError {
  match self.sessions.set_mode_handler {
    Some(handler) =>
      agent_handler_call("session/set_mode", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/set_mode")
  }
}

///|
pub async fn AgentEndpoint::set_config_option(
  self : AgentEndpoint,
  context : AgentContext,
  params : SetSessionConfigOptionParams,
) -> SetSessionConfigOptionResult raise HandlerError {
  match self.sessions.set_config_option_handler {
    Some(handler) =>
      agent_handler_call("session/set_config_option", async fn() {
        handler(context, params)
      })
    None => raise UnavailableOperation(method_name="session/set_config_option")
  }
}

///|
pub async fn AgentEndpoint::authenticate(
  self : AgentEndpoint,
  context : AgentContext,
  params : AuthenticateParams,
) -> AuthenticateResult raise HandlerError {
  match self.auth {
    Some(auth) =>
      agent_handler_call("authenticate", async fn() {
        (auth.authenticate_handler)(context, params)
      })
    None => raise UnavailableOperation(method_name="authenticate")
  }
}

///|
pub async fn AgentEndpoint::logout(
  self : AgentEndpoint,
  context : AgentContext,
  params : LogoutParams,
) -> LogoutResult raise HandlerError {
  match self.auth {
    Some(auth) =>
      match auth.logout_handler {
        Some(handler) =>
          agent_handler_call("logout", async fn() { handler(context, params) })
        None => raise UnavailableOperation(method_name="logout")
      }
    None => raise UnavailableOperation(method_name="logout")
  }
}
