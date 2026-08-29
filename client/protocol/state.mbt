///|
using @message {type ClientRequest, type ClientNotification}

///|
using @jsonrpc {type RequestId}

///|
using @protocol_data {type ProtocolNullable, type ClientCapabilities}

///|
/// The phase of the Client-side protocol lifecycle.
pub(all) enum ClientProtocolPhase {
  AwaitingReady
  Ready
} derive(Eq, Debug)

///|
/// Immutable Client-side state after capability negotiation data is known.
///
/// The capability field remains nullable so an omitted or explicit null
/// `clientCapabilities` value cannot be mistaken for an enabled capability.
pub(all) struct ClientProtocolState {
  phase : ClientProtocolPhase
  capabilities : ProtocolNullable[ClientCapabilities]
} derive(Eq, Debug)

///|
/// Events accepted by the pure Client-side reducer.
pub(all) enum ClientProtocolEvent {
  Ready
  Request(ClientRequest)
  Notification(ClientNotification)
} derive(Eq, Debug)

///|
/// Commands emitted for the runtime or endpoint adapter.  They are data only;
/// no async operation, task, or side effect is started by this reducer.
pub(all) enum ClientProtocolCommand {
  DispatchRequest(ClientRequest)
  DispatchNotification(ClientNotification)
  CancelRequest(request_id~ : RequestId)
} derive(Eq, Debug)

///|
/// State and commands produced by one Client reducer step.
pub(all) struct ClientProtocolStep {
  state : ClientProtocolState
  commands : Array[ClientProtocolCommand]
} derive(Eq, Debug)

///|
/// Explicit failures from Client protocol readiness and capability gates.
pub(all) suberror ClientProtocolError {
  NotReady(method_name~ : String)
  AlreadyReady
  CapabilityDenied(method_name~ : String, capability~ : String)
} derive(Eq, Debug)

///|
/// Construct a Client state that has negotiated capability data but is not yet
/// ready to receive Agent business traffic.
pub fn client_protocol_state_new(
  capabilities~ : ProtocolNullable[ClientCapabilities],
) -> ClientProtocolState {
  { phase: AwaitingReady, capabilities, }
}

///|
/// Construct a ready Client state when the caller has already completed the
/// initialize exchange.
pub fn client_protocol_state_ready(
  capabilities~ : ProtocolNullable[ClientCapabilities],
) -> ClientProtocolState {
  { phase: Ready, capabilities, }
}

///|
fn client_capabilities(
  state : ClientProtocolState,
) -> ProtocolNullable[ClientCapabilities] {
  state.capabilities
}

///|
fn client_fs_read_supported(state : ClientProtocolState) -> Bool {
  match client_capabilities(state) {
    Value(capabilities) =>
      match capabilities.fs {
        Value(fs) =>
          match fs.read_text_file {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn client_fs_write_supported(state : ClientProtocolState) -> Bool {
  match client_capabilities(state) {
    Value(capabilities) =>
      match capabilities.fs {
        Value(fs) =>
          match fs.write_text_file {
            Value(true) => true
            Omitted | Null | Value(false) => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn client_terminal_supported(state : ClientProtocolState) -> Bool {
  match client_capabilities(state) {
    Value(capabilities) =>
      match capabilities.terminal {
        Value(true) => true
        Omitted | Null | Value(false) => false
      }
    Omitted | Null => false
  }
}

///|
fn client_elicitation_form_supported(state : ClientProtocolState) -> Bool {
  match client_capabilities(state) {
    Value(capabilities) =>
      match capabilities.elicitation {
        Value(elicitation) =>
          match elicitation.form {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn client_elicitation_url_supported(state : ClientProtocolState) -> Bool {
  match client_capabilities(state) {
    Value(capabilities) =>
      match capabilities.elicitation {
        Value(elicitation) =>
          match elicitation.url {
            Value(_) => true
            Omitted | Null => false
          }
        Omitted | Null => false
      }
    Omitted | Null => false
  }
}

///|
fn client_require_ready(
  state : ClientProtocolState,
  method_name : String,
) -> Unit raise ClientProtocolError {
  match state.phase {
    AwaitingReady => raise NotReady(method_name~)
    Ready => ()
  }
}

///|
fn client_require_capability(
  supported : Bool,
  method_name : String,
  capability : String,
) -> Unit raise ClientProtocolError {
  if !supported {
    raise CapabilityDenied(method_name~, capability~)
  }
}

///|
fn client_require_terminal(
  state : ClientProtocolState,
  method_name : String,
) -> Unit raise ClientProtocolError {
  client_require_capability(
    client_terminal_supported(state),
    method_name,
    "terminal",
  )
}

///|
fn client_reduce_request(
  state : ClientProtocolState,
  request : ClientRequest,
) -> ClientProtocolStep raise ClientProtocolError {
  let method_name = request.method_name()
  client_require_ready(state, method_name)
  match request {
    SessionRequestPermission(_) =>
      { state, commands: [DispatchRequest(request)], }
    FsReadTextFile(_) => {
      client_require_capability(
        client_fs_read_supported(state),
        method_name,
        "fs.readTextFile",
      )
      { state, commands: [DispatchRequest(request)], }
    }
    FsWriteTextFile(_) => {
      client_require_capability(
        client_fs_write_supported(state),
        method_name,
        "fs.writeTextFile",
      )
      { state, commands: [DispatchRequest(request)], }
    }
    TerminalCreate(_)
    | TerminalOutput(_)
    | TerminalWaitForExit(_)
    | TerminalKill(_)
    | TerminalRelease(_) => {
      client_require_terminal(state, method_name)
      { state, commands: [DispatchRequest(request)], }
    }
    ElicitationCreate(params) => {
      match params {
        Form(_) =>
          client_require_capability(
            client_elicitation_form_supported(state),
            method_name,
            "elicitation.form",
          )
        Url(_) =>
          client_require_capability(
            client_elicitation_url_supported(state),
            method_name,
            "elicitation.url",
          )
      }
      { state, commands: [DispatchRequest(request)], }
    }
  }
}

///|
fn client_reduce_notification(
  state : ClientProtocolState,
  notification : ClientNotification,
) -> ClientProtocolStep raise ClientProtocolError {
  match notification {
    SessionUpdate(_) => {
      let method_name = notification.method_name()
      client_require_ready(state, method_name)
      { state, commands: [DispatchNotification(notification)], }
    }
    ElicitationComplete(_) => {
      let method_name = notification.method_name()
      client_require_ready(state, method_name)
      client_require_capability(
        client_elicitation_url_supported(state),
        method_name,
        "elicitation.url",
      )
      { state, commands: [DispatchNotification(notification)], }
    }
    CancelRequest(request_id) =>
      { state, commands: [CancelRequest(request_id~)], }
  }
}

///|
/// Reduce one Client protocol event without performing I/O or changing any
/// external task state.
pub fn client_protocol_reduce(
  state : ClientProtocolState,
  event : ClientProtocolEvent,
) -> ClientProtocolStep raise ClientProtocolError {
  match event {
    Ready =>
      match state.phase {
        Ready => raise AlreadyReady
        AwaitingReady => { state: { ..state, phase: Ready, }, commands: [], }
      }
    Request(request) => client_reduce_request(state, request)
    Notification(notification) =>
      client_reduce_notification(state, notification)
  }
}
