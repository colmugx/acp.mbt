///|
/// An opaque, fully validated Client endpoint.  It owns immutable services
/// and derived initialization capabilities, never connection-scoped state.
pub struct ClientEndpoint {
  info : Implementation
  session : ClientSessionService
  file_system : ClientFileSystemService?
  terminal : ClientTerminalService?
  elicitation : ClientElicitationService?
  capabilities : ClientCapabilities
}

///|
fn client_endpoint_marker(enabled : Bool) -> ProtocolNullable[CapabilityMarker] {
  if enabled {
    Value({ meta: Omitted })
  } else {
    Omitted
  }
}

///|
fn client_endpoint_bool(enabled : Bool) -> ProtocolNullable[Bool] {
  if enabled {
    Value(true)
  } else {
    Omitted
  }
}

///|
fn client_endpoint_file_system_capabilities(
  service : ClientFileSystemService?,
) -> ProtocolNullable[ClientFileSystemCapabilities] {
  match service {
    None => Omitted
    Some(service) => {
      let read = client_endpoint_bool(service.read_handler is Some(_))
      let write = client_endpoint_bool(service.write_handler is Some(_))
      Value({ read_text_file: read, write_text_file: write, meta: Omitted })
    }
  }
}

///|
fn client_endpoint_elicitation_capabilities(
  service : ClientElicitationService?,
) -> ProtocolNullable[ClientElicitationCapabilities] {
  match service {
    None => Omitted
    Some(service) => {
      let form = client_endpoint_marker(service.form_handler is Some(_))
      let url = client_endpoint_marker(service.url_handler is Some(_))
      if service.form_handler is Some(_) || service.url_handler is Some(_) {
        Value({ form, url, meta: Omitted })
      } else {
        Omitted
      }
    }
  }
}

///|
fn client_endpoint_capabilities(spec : ClientSpec) -> ClientCapabilities {
  {
    fs: client_endpoint_file_system_capabilities(spec.file_system),
    terminal: if spec.terminal is Some(_) {
      Value(true)
    } else {
      Omitted
    },
    elicitation: client_endpoint_elicitation_capabilities(spec.elicitation),
    session: Omitted,
    meta: Omitted,
  }
}

///|
fn client_endpoint_from_spec(spec : ClientSpec) -> ClientEndpoint {
  {
    info: spec.info,
    session: spec.session,
    file_system: spec.file_system,
    terminal: spec.terminal,
    elicitation: spec.elicitation,
    capabilities: client_endpoint_capabilities(spec),
  }
}

///|
/// Return the immutable implementation information used for initialization.
pub fn ClientEndpoint::info(self : ClientEndpoint) -> Implementation {
  self.info
}

///|
/// Return capabilities derived exclusively from the supplied services.
pub fn ClientEndpoint::capabilities(
  self : ClientEndpoint,
) -> ClientCapabilities {
  self.capabilities
}

///|
fn client_handler_error(method_name : String, error : Error) -> HandlerError {
  if @async.is_cancellation_error(error) {
    Cancelled
  } else {
    match error {
      HandlerError::Application(_) =>
        Application(message=method_name + ": handler failure")
      HandlerError::Cancelled => Cancelled
      HandlerError::UnavailableOperation(method_name~) =>
        UnavailableOperation(method_name~)
      _ => Application(message=method_name + ": handler failure")
    }
  }
}

///|
/// Normalize any ordinary application Error at the endpoint boundary.
/// Callback authors do not need to manufacture a protocol-specific error.
async fn[T] client_handler_call(
  method_name : String,
  handler : async () -> T,
) -> T raise HandlerError {
  handler() catch {
    error => raise client_handler_error(method_name, error)
  }
}

///|
/// Deliver a `session/update` notification to the Client observer.
pub async fn ClientEndpoint::session_update(
  self : ClientEndpoint,
  params : SessionUpdateParams,
) -> Unit raise HandlerError {
  client_handler_call("session/update", async fn() {
    (self.session.session_update_handler)(params)
  })
}

///|
/// Deliver a permission request to the Client handler.
pub async fn ClientEndpoint::request_permission(
  self : ClientEndpoint,
  request : RequestPermissionRequest,
) -> RequestPermissionResponse raise HandlerError {
  client_handler_call("session/request_permission", async fn() {
    (self.session.request_permission_handler)(request)
  })
}

///|
/// Invoke the optional `fs/read_text_file` handler.
pub async fn ClientEndpoint::read_text_file(
  self : ClientEndpoint,
  params : ReadTextFileParams,
) -> ReadTextFileResult raise HandlerError {
  match self.file_system {
    Some(service) =>
      match service.read_handler {
        Some(handler) =>
          client_handler_call("fs/read_text_file", async fn() {
            handler(params)
          })
        None => raise UnavailableOperation(method_name="fs/read_text_file")
      }
    None => raise UnavailableOperation(method_name="fs/read_text_file")
  }
}

///|
/// Invoke the optional `fs/write_text_file` handler.
pub async fn ClientEndpoint::write_text_file(
  self : ClientEndpoint,
  params : WriteTextFileParams,
) -> WriteTextFileResult raise HandlerError {
  match self.file_system {
    Some(service) =>
      match service.write_handler {
        Some(handler) =>
          client_handler_call("fs/write_text_file", async fn() {
            handler(params)
          })
        None => raise UnavailableOperation(method_name="fs/write_text_file")
      }
    None => raise UnavailableOperation(method_name="fs/write_text_file")
  }
}

///|
/// Invoke `terminal/create` on the complete terminal service.
pub async fn ClientEndpoint::terminal_create(
  self : ClientEndpoint,
  params : TerminalCreateParams,
) -> TerminalCreateResult raise HandlerError {
  match self.terminal {
    Some(service) =>
      client_handler_call("terminal/create", async fn() {
        (service.create_handler)(params)
      })
    None => raise UnavailableOperation(method_name="terminal/create")
  }
}

///|
/// Invoke `terminal/output` on the complete terminal service.
pub async fn ClientEndpoint::terminal_output(
  self : ClientEndpoint,
  params : TerminalOutputParams,
) -> TerminalOutputResult raise HandlerError {
  match self.terminal {
    Some(service) =>
      client_handler_call("terminal/output", async fn() {
        (service.output_handler)(params)
      })
    None => raise UnavailableOperation(method_name="terminal/output")
  }
}

///|
/// Invoke `terminal/wait_for_exit` on the complete terminal service.
pub async fn ClientEndpoint::terminal_wait_for_exit(
  self : ClientEndpoint,
  params : TerminalWaitForExitParams,
) -> TerminalWaitForExitResult raise HandlerError {
  match self.terminal {
    Some(service) =>
      client_handler_call("terminal/wait_for_exit", async fn() {
        (service.wait_for_exit_handler)(params)
      })
    None => raise UnavailableOperation(method_name="terminal/wait_for_exit")
  }
}

///|
/// Invoke `terminal/kill` on the complete terminal service.
pub async fn ClientEndpoint::terminal_kill(
  self : ClientEndpoint,
  params : TerminalKillParams,
) -> TerminalKillResult raise HandlerError {
  match self.terminal {
    Some(service) =>
      client_handler_call("terminal/kill", async fn() {
        (service.kill_handler)(params)
      })
    None => raise UnavailableOperation(method_name="terminal/kill")
  }
}

///|
/// Invoke `terminal/release` on the complete terminal service.
pub async fn ClientEndpoint::terminal_release(
  self : ClientEndpoint,
  params : TerminalReleaseParams,
) -> TerminalReleaseResult raise HandlerError {
  match self.terminal {
    Some(service) =>
      client_handler_call("terminal/release", async fn() {
        (service.release_handler)(params)
      })
    None => raise UnavailableOperation(method_name="terminal/release")
  }
}

///|
/// Invoke form-mode `elicitation/create`.
pub async fn ClientEndpoint::elicitation_form(
  self : ClientEndpoint,
  params : ElicitationFormParams,
) -> ElicitationCreateResult raise HandlerError {
  match self.elicitation {
    Some(service) =>
      match service.form_handler {
        Some(handler) =>
          client_handler_call("elicitation/create", async fn() {
            handler(params)
          })
        None => raise UnavailableOperation(method_name="elicitation/create")
      }
    None => raise UnavailableOperation(method_name="elicitation/create")
  }
}

///|
/// Invoke URL-mode `elicitation/create`.
pub async fn ClientEndpoint::elicitation_url(
  self : ClientEndpoint,
  params : ElicitationUrlParams,
) -> ElicitationCreateResult raise HandlerError {
  match self.elicitation {
    Some(service) =>
      match service.url_handler {
        Some(handler) =>
          client_handler_call("elicitation/create", async fn() {
            handler(params)
          })
        None => raise UnavailableOperation(method_name="elicitation/create")
      }
    None => raise UnavailableOperation(method_name="elicitation/create")
  }
}

///|
/// Observe `elicitation/complete` notifications.
pub async fn ClientEndpoint::elicitation_complete(
  self : ClientEndpoint,
  params : ElicitationCompleteParams,
) -> Unit raise HandlerError {
  match self.elicitation {
    Some(service) =>
      match service.complete_handler {
        Some(handler) =>
          client_handler_call("elicitation/complete", async fn() {
            handler(params)
          })
        None => raise UnavailableOperation(method_name="elicitation/complete")
      }
    None => raise UnavailableOperation(method_name="elicitation/complete")
  }
}

///|
/// A pure Reader composition program for one caller-owned environment.
pub type ClientProgram[Env] = @reader.Reader[
  Env,
  Result[ClientEndpoint, ClientCompositionError],
]

///|
/// Turn a Reader of a validated Client specification into a one-shot endpoint
/// program.  Each `Reader::run` derives an isolated endpoint from its Env.
pub fn[Env] client_program(
  spec_program : @reader.Reader[Env, Result[ClientSpec, ClientCompositionError]],
) -> ClientProgram[Env] {
  @reader.Reader::map(spec_program, fn(result) {
    Result::map(result, fn(spec) { client_endpoint_from_spec(spec) })
  })
}

///|
/// Compose a Client endpoint directly from a caller-owned environment
/// projection without storing that environment globally.
pub fn[Env] client_program_from(
  project : (Env) -> Result[ClientSpec, ClientCompositionError],
) -> ClientProgram[Env] {
  client_program(@reader.asks(project))
}
