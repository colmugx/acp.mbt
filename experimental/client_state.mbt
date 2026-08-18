///|
/// Agent→Client requests accepted by a v2 Client endpoint.
pub(all) enum ExperimentalV2ClientRequest {
  SessionRequestPermission(ExperimentalV2RequestPermissionRequest)
  ElicitationCreate(ExperimentalV2ElicitationCreateRequest)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2ClientRequest::method_name(
  self : ExperimentalV2ClientRequest,
) -> String {
  match self {
    SessionRequestPermission(_) => "session/request_permission"
    ElicitationCreate(_) => "elicitation/create"
  }
}

///|
/// Agent→Client notifications accepted by a v2 Client endpoint.
pub(all) enum ExperimentalV2ClientNotification {
  SessionUpdate(ExperimentalV2UpdateSessionNotification)
  ElicitationComplete(ExperimentalV2CompleteElicitationNotification)
  CancelRequest(ExperimentalV2RequestId)
} derive(Eq, Debug)

///|
pub fn ExperimentalV2ClientNotification::method_name(
  self : ExperimentalV2ClientNotification,
) -> String {
  match self {
    SessionUpdate(_) => "session/update"
    ElicitationComplete(_) => "elicitation/complete"
    CancelRequest(_) => "$/cancel_request"
  }
}

///|
/// The phase of the Client-side v2 lifecycle.  `ClientFailed` is terminal: a
/// mismatched negotiate result fails the whole connection (SHOULD-close, no
/// partial ready, no downgrade path); every later event re-raises the stored
/// typed failure.
pub(all) enum ExperimentalV2ClientPhase {
  ClientAwaitingInitialize
  ClientReady
  ClientFailed(ExperimentalV2ClientProtocolError)
} derive(Eq, Debug)

///|
/// Immutable Client-side v2 state.  `capabilities` is this client's own
/// advertised surface, fixed at construction; `agent` is the negotiated
/// agent advertisement once ready.
pub(all) struct ExperimentalV2ClientState {
  phase : ExperimentalV2ClientPhase
  capabilities : ExperimentalV2ClientCapabilities
  agent : ExperimentalV2InitializeResult?
} derive(Eq, Debug)

///|
/// Inputs accepted by the pure Client-side v2 reducer.  The initialize
/// exchange is modeled by sending the pinned-version params (see
/// `experimental_v2_client_initialize_params`) and feeding the received
/// result back as an `InitializeResult` event.
pub(all) enum ExperimentalV2ClientEvent {
  InitializeResult(ExperimentalV2InitializeResult)
  AgentRequest(ExperimentalV2ClientRequest)
  AgentNotification(ExperimentalV2ClientNotification)
  UnknownAgentMethod(method_name~ : String)
} derive(Eq, Debug)

///|
/// Commands emitted for the runtime or endpoint adapter.  They are data
/// only; no async operation, task, or side effect is started by this
/// reducer.
pub(all) enum ExperimentalV2ClientCommand {
  DispatchRequest(ExperimentalV2ClientRequest)
  DispatchNotification(ExperimentalV2ClientNotification)
  CancelRequest(request_id~ : ExperimentalV2RequestId)
  CloseConnection
} derive(Eq, Debug)

///|
/// State and commands produced by one v2 Client reducer step.
pub(all) struct ExperimentalV2ClientStep {
  state : ExperimentalV2ClientState
  commands : Array[ExperimentalV2ClientCommand]
} derive(Eq, Debug)

///|
/// Explicit failures from Client-side v2 readiness, negotiation, and
/// capability gates.
pub(all) suberror ExperimentalV2ClientProtocolError {
  NotReady(method_name~ : String)
  AlreadyReady
  UnsupportedVersion(offered~ : Int)
  CapabilityDenied(method_name~ : String, capability~ : String)
  UnknownMethod(method_name~ : String)
} derive(Eq, Debug)

///|
/// Construct a fresh v2 Client state advertising `capabilities`; it stays
/// awaiting until the initialize result arrives.
pub fn experimental_v2_client_state_new(
  capabilities~ : ExperimentalV2ClientCapabilities,
) -> ExperimentalV2ClientState {
  { phase: ClientAwaitingInitialize, capabilities, agent: None }
}

///|
/// The `initialize` params a v2 Client sends: role-agnostic info plus its
/// own capabilities, with the protocol version pinned to 2.
pub fn experimental_v2_client_initialize_params(
  info~ : ExperimentalV2Implementation,
  capabilities~ : ExperimentalV2ClientCapabilities,
) -> ExperimentalV2InitializeParams {
  {
    protocol_version: experimental_v2_protocol_version,
    info,
    capabilities,
    meta: None,
  }
}

///|
fn experimental_v2_client_require_ready(
  state : ExperimentalV2ClientState,
  method_name : String,
) -> Unit raise ExperimentalV2ClientProtocolError {
  match state.phase {
    ClientReady => ()
    ClientAwaitingInitialize => raise NotReady(method_name~)
    ClientFailed(failure) => raise failure
  }
}

///|
fn experimental_v2_client_require_capability(
  supported : Bool,
  method_name : String,
  capability : String,
) -> Unit raise ExperimentalV2ClientProtocolError {
  if !supported {
    raise CapabilityDenied(method_name~, capability~)
  }
}

///|
fn experimental_v2_client_elicitation_form_supported(
  state : ExperimentalV2ClientState,
) -> Bool {
  match state.capabilities.elicitation {
    MarkerSupported(elicitation) =>
      match elicitation.form {
        MarkerSupported(_) => true
        MarkerUnsupported => false
      }
    MarkerUnsupported => false
  }
}

///|
fn experimental_v2_client_elicitation_url_supported(
  state : ExperimentalV2ClientState,
) -> Bool {
  match state.capabilities.elicitation {
    MarkerSupported(elicitation) =>
      match elicitation.url {
        MarkerSupported(_) => true
        MarkerUnsupported => false
      }
    MarkerUnsupported => false
  }
}

///|
/// The initialize result decides the connection: version 2 enters Ready;
/// any other version fails terminally with `UnsupportedVersion` and a
/// close command.  A caller that needs v1 must open a separate v1
/// connection through the root package.
fn experimental_v2_client_reduce_initialize_result(
  state : ExperimentalV2ClientState,
  result : ExperimentalV2InitializeResult,
) -> ExperimentalV2ClientStep raise ExperimentalV2ClientProtocolError {
  match state.phase {
    ClientReady => raise AlreadyReady
    ClientFailed(failure) => raise failure
    ClientAwaitingInitialize =>
      if result.protocol_version == experimental_v2_protocol_version {
        {
          state: { ..state, phase: ClientReady, agent: Some(result) },
          commands: [],
        }
      } else {
        {
          state: {
            ..state,
            phase: ClientFailed(
              UnsupportedVersion(offered=result.protocol_version),
            ),
          },
          commands: [CloseConnection],
        }
      }
  }
}

///|
fn experimental_v2_client_reduce_request(
  state : ExperimentalV2ClientState,
  request : ExperimentalV2ClientRequest,
) -> ExperimentalV2ClientStep raise ExperimentalV2ClientProtocolError {
  let method_name = ExperimentalV2ClientRequest::method_name(request)
  experimental_v2_client_require_ready(state, method_name)
  match request {
    SessionRequestPermission(_) =>
      // The v2 baseline defines no client capability marker for permission
      // requests (ClientCapabilities carries only `elicitation`); the method
      // is always available once ready.
      { state, commands: [DispatchRequest(request)] }
    ElicitationCreate(params) => {
      match params {
        Known(known) =>
          match known.mode {
            ElicitationForm(_) =>
              experimental_v2_client_require_capability(
                experimental_v2_client_elicitation_form_supported(state),
                method_name,
                "elicitation.form",
              )
            ElicitationUrl(_) =>
              experimental_v2_client_require_capability(
                experimental_v2_client_elicitation_url_supported(state),
                method_name,
                "elicitation.url",
              )
          }
        Extension(tag~, ..) | Future(tag~, ..) =>
          experimental_v2_client_require_capability(
            false,
            method_name,
            "elicitation." + tag,
          )
      }
      { state, commands: [DispatchRequest(request)] }
    }
  }
}

///|
/// `session/update` and `elicitation/complete` are always accepted once
/// ready; gating the completion notification on `elicitation.url` was a v1
/// rule.  `$/cancel_request` is protocol-level and allowed in any live
/// phase.
fn experimental_v2_client_reduce_notification(
  state : ExperimentalV2ClientState,
  notification : ExperimentalV2ClientNotification,
) -> ExperimentalV2ClientStep raise ExperimentalV2ClientProtocolError {
  match notification {
    SessionUpdate(_) | ElicitationComplete(_) => {
      let method_name = ExperimentalV2ClientNotification::method_name(
        notification,
      )
      experimental_v2_client_require_ready(state, method_name)
      { state, commands: [DispatchNotification(notification)] }
    }
    CancelRequest(request_id) =>
      { state, commands: [CancelRequest(request_id~)] }
  }
}

///|
/// Reduce one Client-side v2 event without performing I/O or changing any
/// external task state.  A terminal `ClientFailed` state re-raises its
/// stored failure for every event.
pub fn experimental_v2_client_reduce(
  state : ExperimentalV2ClientState,
  event : ExperimentalV2ClientEvent,
) -> ExperimentalV2ClientStep raise ExperimentalV2ClientProtocolError {
  match state.phase {
    ClientFailed(failure) => raise failure
    ClientAwaitingInitialize | ClientReady =>
      match event {
        InitializeResult(result) =>
          experimental_v2_client_reduce_initialize_result(state, result)
        AgentRequest(request) =>
          experimental_v2_client_reduce_request(state, request)
        AgentNotification(notification) =>
          experimental_v2_client_reduce_notification(state, notification)
        UnknownAgentMethod(method_name~) => raise UnknownMethod(method_name~)
      }
  }
}
