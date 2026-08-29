///|
/// Typed handler failures crossing the v2 Client service boundary.  Payloads
/// are host-authored display strings, mirroring the v2 Agent handler error
/// contract: no secrets, raw payloads, or stack detail.
pub(all) suberror ExperimentalV2ClientHandlerError {
  Application(message~ : String)
  /// Invalid request parameters (unknown id, wrong value shape); maps to
  /// JSON-RPC `-32602`.
  InvalidParams(message~ : String)
  Cancelled
  UnavailableOperation(method_name~ : String)
} derive(Eq, Debug)

///|
/// Normalize one raw handler failure once at the v2 Client endpoint boundary:
/// cancellation and typed failures keep their shape (the method name is added
/// as context), anything else names itself as an application failure.
// The catch-all is load-bearing: it is the single seam that keeps unexpected
// handler defects typed instead of escaping the owner loop.
#warnings("-fragile_catch_all")
fn experimental_v2_client_handler_error(
  method_name : String,
  error : Error,
) -> ExperimentalV2ClientHandlerError {
  if @async.is_cancellation_error(error) {
    Cancelled
  } else {
    match error {
      ExperimentalV2ClientHandlerError::Application(message~) =>
        Application(message=method_name + ": " + message)
      ExperimentalV2ClientHandlerError::InvalidParams(message~) =>
        InvalidParams(message=method_name + ": " + message)
      ExperimentalV2ClientHandlerError::Cancelled => Cancelled
      ExperimentalV2ClientHandlerError::UnavailableOperation(method_name~) =>
        UnavailableOperation(method_name~)
      _ =>
        Application(
          message=method_name + ": client handler failed: " + error.to_string(),
        )
    }
  }
}

///|
async fn[T] experimental_v2_client_handler_call(
  method_name : String,
  handler : async () -> T,
) -> T raise ExperimentalV2ClientHandlerError {
  handler() catch {
    error => raise experimental_v2_client_handler_error(method_name, error)
  }
}

///|
/// Typed observer for Agent `session/update` notifications received by the v2
/// Client.
pub type ExperimentalV2ClientSessionUpdateHandler = async (
  ExperimentalV2UpdateSessionNotification,
) -> Unit

///|
/// Typed handler for Agent permission requests received by the v2 Client.
pub type ExperimentalV2ClientRequestPermissionHandler = async (
  ExperimentalV2RequestPermissionRequest,
) -> ExperimentalV2RequestPermissionResponse

///|
/// The required v2 Client baseline service: the `session/update` sink plus
/// the `session/request_permission` handler.  v2 removed the client
/// filesystem and terminal surfaces, so no such services exist here.
pub struct ExperimentalV2ClientSessionService {
  session_update_handler : ExperimentalV2ClientSessionUpdateHandler
  request_permission_handler : ExperimentalV2ClientRequestPermissionHandler
}

///|
/// Compose the required v2 Client baseline.  Both callbacks are required by
/// the signature; an incomplete baseline cannot be represented as a service
/// value.
pub fn experimental_v2_client_session_service(
  session_update~ : ExperimentalV2ClientSessionUpdateHandler,
  request_permission~ : ExperimentalV2ClientRequestPermissionHandler,
) -> ExperimentalV2ClientSessionService {
  {
    session_update_handler: session_update,
    request_permission_handler: request_permission,
  }
}

///|
/// Typed form-mode `elicitation/create` handler: the request `message` plus
/// the form-mode payload.  The endpoint dispatches by mode, so this handler
/// only ever sees `ElicitationForm` requests.
pub type ExperimentalV2ClientElicitationFormHandler = async (
  String,
  ExperimentalV2ElicitationFormMode,
) -> ExperimentalV2ElicitationCreateResponse

///|
/// Typed URL-mode `elicitation/create` handler: the request `message` plus
/// the URL-mode payload.  The endpoint dispatches by mode, so this handler
/// only ever sees `ElicitationUrl` requests.
pub type ExperimentalV2ClientElicitationUrlHandler = async (
  String,
  ExperimentalV2ElicitationUrlMode,
) -> ExperimentalV2ElicitationCreateResponse

///|
/// Typed `elicitation/complete` notification observer.
pub type ExperimentalV2ClientElicitationCompleteHandler = async (
  ExperimentalV2CompleteElicitationNotification,
) -> Unit

///|
/// Immutable optional v2 Client elicitation service.  The `form` and `url`
/// create handlers are the capability sources for the `elicitation.form` and
/// `elicitation.url` markers; the completion sink backs the
/// `elicitation/complete` notification.
pub struct ExperimentalV2ClientElicitationService {
  form_handler : ExperimentalV2ClientElicitationFormHandler?
  url_handler : ExperimentalV2ClientElicitationUrlHandler?
  complete_handler : ExperimentalV2ClientElicitationCompleteHandler?
}

///|
/// Failures found while composing one immutable v2 Client service or spec.
pub(all) suberror ExperimentalV2ClientCompositionError {
  InvalidImplementation(reason~ : String)
  /// An elicitation service value with no handler at all.
  MissingElicitationHandler
  /// URL-mode creates complete out-of-band through `elicitation/complete`,
  /// so a client that can start URL flows must be able to observe their
  /// completion.
  ElicitationUrlRequiresComplete(reason~ : String)
} derive(Eq, Debug)

///|
/// Compose the optional v2 Client elicitation service.  At least one handler
/// must be supplied; URL-mode support requires the completion sink, because a
/// URL elicitation finishes later through the `elicitation/complete`
/// notification rather than the create response.
pub fn experimental_v2_client_elicitation_service(
  form? : ExperimentalV2ClientElicitationFormHandler,
  url? : ExperimentalV2ClientElicitationUrlHandler,
  complete? : ExperimentalV2ClientElicitationCompleteHandler,
) -> ExperimentalV2ClientElicitationService raise ExperimentalV2ClientCompositionError {
  if url is Some(_) && complete is None {
    raise ElicitationUrlRequiresComplete(
      reason="elicitation/url requires the elicitation/complete sink",
    )
  }
  if form is None && url is None && complete is None {
    raise MissingElicitationHandler
  }
  { form_handler: form, url_handler: url, complete_handler: complete, }
}

///|
/// The application-owned immutable v2 Client specification consumed by the
/// endpoint constructor.
pub struct ExperimentalV2ClientSpec {
  info : ExperimentalV2Implementation
  session : ExperimentalV2ClientSessionService
  elicitation : ExperimentalV2ClientElicitationService?
}

///|
/// Validate and freeze one v2 Client specification.  The baseline session
/// service is required; the optional elicitation service is the only
/// capability source, never an independent capability flag.
pub fn experimental_v2_client_spec(
  info~ : ExperimentalV2Implementation,
  session~ : ExperimentalV2ClientSessionService,
  elicitation? : ExperimentalV2ClientElicitationService,
) -> ExperimentalV2ClientSpec raise ExperimentalV2ClientCompositionError {
  if info.name == "" {
    raise InvalidImplementation(reason="client name must not be empty")
  }
  if info.version == "" {
    raise InvalidImplementation(reason="client version must not be empty")
  }
  { info, session, elicitation, }
}

///|
/// An opaque, fully validated v2 Client endpoint.  It owns immutable services
/// and the capabilities derived from their presence, never connection-scoped
/// state.
pub struct ExperimentalV2ClientEndpoint {
  info : ExperimentalV2Implementation
  session : ExperimentalV2ClientSessionService
  elicitation : ExperimentalV2ClientElicitationService?
  capabilities : ExperimentalV2ClientCapabilities
}

///|
fn experimental_v2_client_endpoint_marker(
  supported : Bool,
) -> ExperimentalV2Marker[ExperimentalV2MarkerPayload] {
  if supported {
    MarkerSupported({ meta: None, })
  } else {
    MarkerUnsupported
  }
}

///|
/// Derive the advertised v2 Client capabilities from service presence alone.
/// The `elicitation` marker exists exactly when at least one create handler
/// exists; `form`/`url` mirror their own handlers.  A completion-sink-only
/// service advertises nothing, because the notification itself is ungated in
/// v2.
fn experimental_v2_client_endpoint_capabilities(
  spec : ExperimentalV2ClientSpec,
) -> ExperimentalV2ClientCapabilities {
  match spec.elicitation {
    None => { elicitation: MarkerUnsupported, meta: None, }
    Some(service) => {
      let form = experimental_v2_client_endpoint_marker(
        service.form_handler is Some(_),
      )
      let url = experimental_v2_client_endpoint_marker(
        service.url_handler is Some(_),
      )
      match (form, url) {
        (MarkerUnsupported, MarkerUnsupported) =>
          { elicitation: MarkerUnsupported, meta: None, }
        _ =>
          {
            elicitation: MarkerSupported({ form, url, meta: None, }),
            meta: None,
          }
      }
    }
  }
}

///|
pub fn experimental_v2_client_endpoint_from_spec(
  spec : ExperimentalV2ClientSpec,
) -> ExperimentalV2ClientEndpoint {
  {
    info: spec.info,
    session: spec.session,
    elicitation: spec.elicitation,
    capabilities: experimental_v2_client_endpoint_capabilities(spec),
  }
}

///|
/// Return the immutable implementation information used for initialization.
pub fn ExperimentalV2ClientEndpoint::info(
  self : ExperimentalV2ClientEndpoint,
) -> ExperimentalV2Implementation {
  self.info
}

///|
/// Return the capabilities derived exclusively from service presence.
pub fn ExperimentalV2ClientEndpoint::capabilities(
  self : ExperimentalV2ClientEndpoint,
) -> ExperimentalV2ClientCapabilities {
  self.capabilities
}

///|
/// Deliver one typed `session/update` notification to the observer sink.
pub async fn ExperimentalV2ClientEndpoint::session_update(
  self : ExperimentalV2ClientEndpoint,
  notification : ExperimentalV2UpdateSessionNotification,
) -> Unit raise ExperimentalV2ClientHandlerError {
  experimental_v2_client_handler_call("session/update", async fn() {
    (self.session.session_update_handler)(notification)
  })
}

///|
/// Deliver one typed permission request to the Client handler.
pub async fn ExperimentalV2ClientEndpoint::request_permission(
  self : ExperimentalV2ClientEndpoint,
  request : ExperimentalV2RequestPermissionRequest,
) -> ExperimentalV2RequestPermissionResponse raise ExperimentalV2ClientHandlerError {
  experimental_v2_client_handler_call("session/request_permission", async fn() {
    (self.session.request_permission_handler)(request)
  })
}

///|
/// Dispatch one `elicitation/create` request by its mode.  Known form and
/// URL modes reach their own handlers; extension or future modes are
/// unavailable at this endpoint (the protocol layer has already denied them
/// by capability before dispatch).
pub async fn ExperimentalV2ClientEndpoint::elicitation_create(
  self : ExperimentalV2ClientEndpoint,
  request : ExperimentalV2ElicitationCreateRequest,
) -> ExperimentalV2ElicitationCreateResponse raise ExperimentalV2ClientHandlerError {
  match self.elicitation {
    Some(service) =>
      match request {
        Known(known) =>
          match known.mode {
            ElicitationForm(mode) =>
              match service.form_handler {
                Some(handler) =>
                  experimental_v2_client_handler_call("elicitation/create", async fn() {
                    handler(known.message, mode)
                  })
                None =>
                  raise UnavailableOperation(method_name="elicitation/create")
              }
            ElicitationUrl(mode) =>
              match service.url_handler {
                Some(handler) =>
                  experimental_v2_client_handler_call("elicitation/create", async fn() {
                    handler(known.message, mode)
                  })
                None =>
                  raise UnavailableOperation(method_name="elicitation/create")
              }
          }
        Extension(..) | Future(..) =>
          raise UnavailableOperation(method_name="elicitation/create")
      }
    None => raise UnavailableOperation(method_name="elicitation/create")
  }
}

///|
/// Observe one typed `elicitation/complete` notification.
pub async fn ExperimentalV2ClientEndpoint::elicitation_complete(
  self : ExperimentalV2ClientEndpoint,
  notification : ExperimentalV2CompleteElicitationNotification,
) -> Unit raise ExperimentalV2ClientHandlerError {
  match self.elicitation {
    Some(service) =>
      match service.complete_handler {
        Some(handler) =>
          experimental_v2_client_handler_call("elicitation/complete", async fn() {
            handler(notification)
          })
        None => raise UnavailableOperation(method_name="elicitation/complete")
      }
    None => raise UnavailableOperation(method_name="elicitation/complete")
  }
}
