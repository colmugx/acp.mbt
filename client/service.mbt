///|
using @acp_error {type ClientCompositionError, type HandlerError}

///|
/// A typed observer for Agent `session/update` notifications received by the
/// Client.
pub type ClientSessionUpdateHandler = async (SessionUpdateParams) -> Unit

///|
/// A typed handler for Agent permission requests received by the Client.
pub type ClientRequestPermissionHandler = async (RequestPermissionRequest) -> RequestPermissionResponse

///|
/// The required baseline Client service.  Both callbacks are supplied in one
/// immutable value; there is no later registration phase.
pub struct ClientSessionService {
  session_update_handler : ClientSessionUpdateHandler
  request_permission_handler : ClientRequestPermissionHandler
}

///|
/// Compose the baseline Client service.  Both callbacks are required by the
/// signature; an incomplete baseline cannot be represented as a service value.
pub fn client_session_service(
  session_update~ : ClientSessionUpdateHandler,
  request_permission~ : ClientRequestPermissionHandler,
) -> ClientSessionService {
  {
    session_update_handler: session_update,
    request_permission_handler: request_permission,
  }
}

///|
/// Typed filesystem callbacks.  Read and write remain independent services
/// so each capability can be derived without a manually supplied flag.
pub type ClientReadTextFileHandler = async (ReadTextFileParams) -> ReadTextFileResult

///|
pub type ClientWriteTextFileHandler = async (WriteTextFileParams) -> WriteTextFileResult

///|
/// Immutable filesystem service.  At least one operation must be supplied;
/// omit the whole service when the Client has no filesystem support.
pub struct ClientFileSystemService {
  read_handler : ClientReadTextFileHandler?
  write_handler : ClientWriteTextFileHandler?
}

///|
pub fn client_file_system_service(
  read? : ClientReadTextFileHandler,
  write? : ClientWriteTextFileHandler,
) -> ClientFileSystemService raise ClientCompositionError {
  if read is None && write is None {
    raise MissingRequiredService(
      service_name="fs/read_text_file or fs/write_text_file",
    )
  }
  { read_handler: read, write_handler: write }
}

///|
/// Typed terminal callbacks.  Terminal support is all-or-nothing at the
/// service boundary, matching the five-operation ACP surface.
pub type ClientTerminalCreateHandler = async (TerminalCreateParams) -> TerminalCreateResult

///|
pub type ClientTerminalOutputHandler = async (TerminalOutputParams) -> TerminalOutputResult

///|
pub type ClientTerminalWaitForExitHandler = async (TerminalWaitForExitParams) -> TerminalWaitForExitResult

///|
pub type ClientTerminalKillHandler = async (TerminalKillParams) -> TerminalKillResult

///|
pub type ClientTerminalReleaseHandler = async (TerminalReleaseParams) -> TerminalReleaseResult

///|
/// Immutable complete terminal service.  All five callbacks are required by
/// the signature; an incomplete terminal cannot be represented as a service
/// value.
pub struct ClientTerminalService {
  create_handler : ClientTerminalCreateHandler
  output_handler : ClientTerminalOutputHandler
  wait_for_exit_handler : ClientTerminalWaitForExitHandler
  kill_handler : ClientTerminalKillHandler
  release_handler : ClientTerminalReleaseHandler
}

///|
pub fn client_terminal_service(
  create~ : ClientTerminalCreateHandler,
  output~ : ClientTerminalOutputHandler,
  wait_for_exit~ : ClientTerminalWaitForExitHandler,
  kill~ : ClientTerminalKillHandler,
  release~ : ClientTerminalReleaseHandler,
) -> ClientTerminalService {
  {
    create_handler: create,
    output_handler: output,
    wait_for_exit_handler: wait_for_exit,
    kill_handler: kill,
    release_handler: release,
  }
}

///|
/// Typed elicitation callbacks.  Form and URL requests carry their
/// mode-specific payloads; completion is a separate notification observer.
pub type ClientElicitationFormHandler = async (ElicitationFormParams) -> ElicitationCreateResult

///|
pub type ClientElicitationUrlHandler = async (ElicitationUrlParams) -> ElicitationCreateResult

///|
pub type ClientElicitationCompleteHandler = async (ElicitationCompleteParams) -> Unit

///|
/// Immutable elicitation service.  URL support requires completion handling;
/// this prevents advertising a flow that cannot consume its completion event.
pub struct ClientElicitationService {
  form_handler : ClientElicitationFormHandler?
  url_handler : ClientElicitationUrlHandler?
  complete_handler : ClientElicitationCompleteHandler?
}

///|
pub fn client_elicitation_service(
  form? : ClientElicitationFormHandler,
  url? : ClientElicitationUrlHandler,
  complete? : ClientElicitationCompleteHandler,
) -> ClientElicitationService raise ClientCompositionError {
  if url is Some(_) && complete is None {
    raise ConflictingSupport(
      reason="elicitation/url requires elicitation/complete",
    )
  }
  if form is None && url is None && complete is None {
    raise MissingRequiredService(service_name="elicitation handler")
  }
  { form_handler: form, url_handler: url, complete_handler: complete }
}

///|
/// The application-owned immutable Client specification consumed by the
/// Reader composition program.
pub struct ClientSpec {
  info : Implementation
  session : ClientSessionService
  file_system : ClientFileSystemService?
  terminal : ClientTerminalService?
  elicitation : ClientElicitationService?
}

///|
/// Validate and freeze one Client specification.  The baseline session
/// service is required; optional services are capability sources, never
/// independent capability flags.
pub fn client_spec(
  info~ : Implementation,
  session~ : ClientSessionService,
  file_system? : ClientFileSystemService,
  terminal? : ClientTerminalService,
  elicitation? : ClientElicitationService,
) -> Result[ClientSpec, ClientCompositionError] {
  if info.name.length() == 0 {
    Err(InvalidImplementation(reason="client name must not be empty"))
  } else if info.version.length() == 0 {
    Err(InvalidImplementation(reason="client version must not be empty"))
  } else {
    Ok({ info, session, file_system, terminal, elicitation })
  }
}

///|
