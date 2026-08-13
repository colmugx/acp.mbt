///|
using @agent_message {type AgentNotification, type AgentRequest}

///|
using @client_protocol {
  type ClientProtocolError,
  type ClientProtocolState,
  type ClientProtocolStep,
  client_protocol_reduce,
}

///|
using @jsonrpc {
  type JsonRpcError,
  type JsonRpcId,
  type JsonRpcMessage,
  type JsonRpcResponse,
  type RequestId,
}

///|
using @message {
  type ClientMessageError,
  type ClientNotification,
  type ClientRequest,
  decode_client_notification,
  decode_client_request,
}

///|
using @protocol_data {
  type AuthenticateParams,
  type AuthenticateResult,
  type CapabilityMarker,
  type ClientCapabilities,
  type ClientElicitationCapabilities,
  type ClientFileSystemCapabilities,
  type ElicitationCompleteParams,
  type ElicitationCreateParams,
  type ElicitationCreateResult,
  type ElicitationFormParams,
  type ElicitationUrlParams,
  type Implementation,
  type InitializeParams,
  type InitializeResult,
  type LogoutParams,
  type LogoutResult,
  type ProtocolDecodeError,
  type ProtocolNullable,
  type ReadTextFileParams,
  type ReadTextFileResult,
  type RequestPermissionRequest,
  type RequestPermissionResponse,
  type TerminalCreateParams,
  type TerminalCreateResult,
  type TerminalKillParams,
  type TerminalKillResult,
  type TerminalOutputParams,
  type TerminalOutputResult,
  type TerminalReleaseParams,
  type TerminalReleaseResult,
  type TerminalWaitForExitParams,
  type TerminalWaitForExitResult,
  type WriteTextFileParams,
  type WriteTextFileResult,
  elicitation_create_result_to_json,
  read_text_file_result_to_json,
  request_permission_response_to_json,
  terminal_create_result_to_json,
  terminal_kill_result_to_json,
  terminal_output_result_to_json,
  terminal_release_result_to_json,
  terminal_wait_for_exit_result_to_json,
  write_text_file_result_to_json,
}

///|
using @session_protocol {
  type CancelParams,
  type CloseSessionParams,
  type CloseSessionResult,
  type DeleteSessionParams,
  type DeleteSessionResult,
  type ListSessionsParams,
  type ListSessionsResult,
  type LoadSessionParams,
  type LoadSessionResult,
  type NewSessionParams,
  type NewSessionResult,
  type PromptParams,
  type PromptResult,
  type ResumeSessionParams,
  type ResumeSessionResult,
  type SessionUpdateParams,
  type SetSessionConfigOptionParams,
  type SetSessionConfigOptionResult,
  type SetSessionModeParams,
  type SetSessionModeResult,
}

///|
/// Runtime intents emitted by the Client adapter.  These values are data
/// only; cancellation itself is owned by the connection/reducer runtime.
pub(all) enum ClientAdapterCommand {
  CancelRequest(request_id~ : RequestId)
  TraceError(method_name~ : String, error~ : JsonRpcError)
} derive(Eq, Debug)

///|
/// Wire responses and runtime trace intents produced by one adapter step.
pub(all) enum ClientAdapterOutput {
  Response(JsonRpcResponse)
  Command(ClientAdapterCommand)
} derive(Eq, Debug)

///|
/// Adapter state contains only the protocol lifecycle and negotiated
/// capabilities.  Request correlation and task tokens remain in the
/// connection/reducer owner; the adapter does not mirror them.
pub(all) struct ClientAdapterState {
  protocol : ClientProtocolState
} derive(Eq, Debug)

///|
pub fn client_adapter_state_new(
  protocol~ : ClientProtocolState,
) -> ClientAdapterState {
  { protocol, }
}

///|
pub fn ClientAdapterState::protocol(
  self : ClientAdapterState,
) -> ClientProtocolState {
  self.protocol
}

///|
/// The explicit state/output result of an admission or completion step.
pub(all) struct ClientAdapterStep {
  state : ClientAdapterState
  outputs : Array[ClientAdapterOutput]
} derive(Eq, Debug)

///|
/// Admission is synchronous and pure.  Only `Invoke` crosses the async
/// handler boundary; `Immediate` already contains its complete owner-loop
/// state transition and output.
pub(all) enum ClientAdapterAdmission {
  Immediate(ClientAdapterStep)
  Invoke(state~ : ClientAdapterState, invocation~ : ClientAdapterInvocation)
}

///|
/// Invalid adapter composition or a completion whose closed-union variant or
/// request id does not match the admitted operation.  Duplicate/late task
/// events are owned by the connection reducer and are not shadowed here.
pub(all) suberror ClientAdapterError {
  EndpointMismatch(reason~ : String)
  UnexpectedMessage(kind~ : String)
  CompletionMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
fn client_adapter_response_id(id : RequestId) -> JsonRpcId {
  match id {
    String(value) => String(value)
    Number(value) => Number(value)
    Null => Null
  }
}

///|
fn client_adapter_response(
  state : ClientAdapterState,
  id : RequestId,
  error : JsonRpcError,
) -> ClientAdapterStep {
  {
    state,
    outputs: [
      Response(
        JsonRpcResponse::error(id=client_adapter_response_id(id), error~),
      ),
    ],
  }
}

///|
fn client_adapter_success(
  state : ClientAdapterState,
  id : RequestId,
  result : Json,
) -> ClientAdapterStep {
  { state, outputs: [Response(JsonRpcResponse::success(id~, result~))] }
}

///|
fn client_adapter_trace(
  state : ClientAdapterState,
  method_name : String,
  error : JsonRpcError,
) -> ClientAdapterStep {
  { state, outputs: [Command(TraceError(method_name~, error~))] }
}

///|
fn client_adapter_validate_endpoint(
  state : ClientAdapterState,
  endpoint : ClientEndpoint,
) -> Unit raise ClientAdapterError {
  let expected : ProtocolNullable[ClientCapabilities] = Value(
    endpoint.capabilities(),
  )
  if state.protocol.capabilities != expected {
    raise EndpointMismatch(reason="state capabilities do not match endpoint")
  }
}

///|
/// Adapter errors deliberately use stable, payload-free protocol messages.
/// Detailed decoder errors stay internal and are not copied into a response.
fn client_adapter_message_error(error : ClientMessageError) -> JsonRpcError {
  match error {
    InvalidParams(..) =>
      JsonRpcError::new(code=InvalidParams, message="invalid params")
    UnknownMethod(_) => JsonRpcError::method_not_found()
    WrongDirection(_) => JsonRpcError::method_not_found()
    WrongKind(_) => JsonRpcError::invalid_request()
  }
}

///|
fn client_adapter_protocol_error(error : ClientProtocolError) -> JsonRpcError {
  match error {
    NotReady(_) => JsonRpcError::invalid_request()
    AlreadyReady => JsonRpcError::invalid_request()
    CapabilityDenied(..) => JsonRpcError::resource_not_found()
  }
}

///|
fn client_adapter_handler_error(error : HandlerError) -> JsonRpcError {
  match error {
    Application(_) => JsonRpcError::internal_error()
    Cancelled => JsonRpcError::request_cancelled()
    UnavailableOperation(_) => JsonRpcError::resource_not_found()
  }
}

///|
fn client_adapter_reduce_request(
  state : ClientAdapterState,
  request : ClientRequest,
) -> Result[ClientProtocolStep, JsonRpcError] {
  try client_protocol_reduce(state.protocol, Request(request)) catch {
    error => Err(client_adapter_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn client_adapter_reduce_notification(
  state : ClientAdapterState,
  notification : ClientNotification,
) -> Result[ClientProtocolStep, JsonRpcError] {
  try client_protocol_reduce(state.protocol, Notification(notification)) catch {
    error => Err(client_adapter_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
/// Normalize handler failures without confusing an application-raised
/// `Cancelled` value with the async runtime's cancellation exception.
/// Unknown exceptions are intentionally redacted rather than stringified.
async fn[T] client_adapter_call(
  handler : async () -> T,
) -> Result[T, HandlerError] noraise {
  try handler() catch {
    error =>
      if @async.is_cancellation_error(error) {
        Err(Cancelled)
      } else {
        match error {
          HandlerError::Application(_) =>
            Err(Application(message="handler failure"))
          HandlerError::Cancelled => Err(Cancelled)
          HandlerError::UnavailableOperation(method_name~) =>
            Err(UnavailableOperation(method_name~))
          _ => Err(Application(message="handler failure"))
        }
      }
  } noraise {
    value => Ok(value)
  }
}

///|
fn[T] client_adapter_encode(
  value : T,
  encode : (T) -> Json raise ProtocolDecodeError,
) -> Result[Json, JsonRpcError] {
  try encode(value) catch {
    _ => Err(JsonRpcError::internal_error())
  } noraise {
    result => Ok(result)
  }
}

///|
fn[T] client_adapter_complete_result(
  state : ClientAdapterState,
  id : RequestId,
  result : Result[T, HandlerError],
  encode : (T) -> Json raise ProtocolDecodeError,
) -> ClientAdapterStep {
  match result {
    Err(error) =>
      client_adapter_response(state, id, client_adapter_handler_error(error))
    Ok(value) =>
      match client_adapter_encode(value, encode) {
        Err(error) => client_adapter_response(state, id, error)
        Ok(result) => client_adapter_success(state, id, result)
      }
  }
}

///|
fn client_adapter_permission_option_offered(
  params : RequestPermissionRequest,
  option_id : String,
) -> Bool {
  for option in params.options {
    if option.option_id == option_id {
      return true
    }
  }
  false
}

///|
fn client_adapter_permission_response(
  state : ClientAdapterState,
  id : RequestId,
  response : RequestPermissionResponse,
) -> ClientAdapterStep {
  match client_adapter_encode(response, request_permission_response_to_json) {
    Err(error) => client_adapter_response(state, id, error)
    Ok(result) => client_adapter_success(state, id, result)
  }
}

///|
/// Permission cancellation is a normal ACP response, while an unknown
/// selected option is a local invalid-params failure.  The admitted request
/// remains the source of truth for the option membership check.
fn client_adapter_complete_permission(
  state : ClientAdapterState,
  id : RequestId,
  params : RequestPermissionRequest,
  result : Result[RequestPermissionResponse, HandlerError],
) -> ClientAdapterStep {
  match result {
    Err(Cancelled) =>
      client_adapter_permission_response(state, id, {
        outcome: Cancelled,
        meta: Omitted,
      })
    Err(error) =>
      client_adapter_response(state, id, client_adapter_handler_error(error))
    Ok(response) => {
      let valid = match response.outcome {
        Cancelled => true
        Selected(selected) =>
          client_adapter_permission_option_offered(params, selected.option_id)
      }
      if valid {
        client_adapter_permission_response(state, id, response)
      } else {
        client_adapter_response(
          state,
          id,
          JsonRpcError::new(code=InvalidParams, message="invalid params"),
        )
      }
    }
  }
}

///|
fn client_adapter_complete_notification(
  state : ClientAdapterState,
  method_name : String,
  result : Result[Unit, HandlerError],
) -> ClientAdapterStep {
  match result {
    Ok(_) => { state, outputs: [] }
    Err(error) =>
      client_adapter_trace(
        state,
        method_name,
        client_adapter_handler_error(error),
      )
  }
}

///|
fn client_adapter_request_invocation(
  state : ClientAdapterState,
  id : RequestId,
  request : ClientRequest,
) -> ClientAdapterAdmission {
  match request {
    SessionRequestPermission(params) =>
      Invoke(state~, invocation=RequestPermissionInvocation(id~, params~))
    FsReadTextFile(params) =>
      Invoke(state~, invocation=FsReadTextFileInvocation(id~, params~))
    FsWriteTextFile(params) =>
      Invoke(state~, invocation=FsWriteTextFileInvocation(id~, params~))
    TerminalCreate(params) =>
      Invoke(state~, invocation=TerminalCreateInvocation(id~, params~))
    TerminalOutput(params) =>
      Invoke(state~, invocation=TerminalOutputInvocation(id~, params~))
    TerminalWaitForExit(params) =>
      Invoke(state~, invocation=TerminalWaitForExitInvocation(id~, params~))
    TerminalKill(params) =>
      Invoke(state~, invocation=TerminalKillInvocation(id~, params~))
    TerminalRelease(params) =>
      Invoke(state~, invocation=TerminalReleaseInvocation(id~, params~))
    ElicitationCreate(params) =>
      Invoke(state~, invocation=ElicitationCreateInvocation(id~, params~))
  }
}

///|
fn client_adapter_admit_request(
  state : ClientAdapterState,
  id : RequestId,
  request : ClientRequest,
) -> ClientAdapterAdmission {
  match client_adapter_reduce_request(state, request) {
    Err(error) => Immediate(client_adapter_response(state, id, error))
    Ok(step) =>
      client_adapter_request_invocation({ protocol: step.state }, id, request)
  }
}

///|
fn client_adapter_admit_notification(
  state : ClientAdapterState,
  notification : ClientNotification,
) -> ClientAdapterAdmission {
  match notification {
    SessionUpdate(params) =>
      match client_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(client_adapter_trace(state, "session/update", error))
        Ok(step) =>
          Invoke(
            state={ protocol: step.state },
            invocation=SessionUpdateInvocation(params~),
          )
      }
    ElicitationComplete(params) =>
      match client_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(client_adapter_trace(state, "elicitation/complete", error))
        Ok(step) =>
          Invoke(
            state={ protocol: step.state },
            invocation=ElicitationCompleteInvocation(params~),
          )
      }
    CancelRequest(request_id) =>
      match client_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(client_adapter_trace(state, "$/cancel_request", error))
        Ok(step) =>
          Immediate({
            state: { protocol: step.state },
            outputs: [Command(CancelRequest(request_id~))],
          })
      }
  }
}

///|
/// Decode and admit one Agent-to-Client JSON-RPC message.  No endpoint
/// handler is called by this function.
pub fn client_adapter_admit(
  state : ClientAdapterState,
  endpoint : ClientEndpoint,
  message : JsonRpcMessage,
) -> ClientAdapterAdmission raise ClientAdapterError {
  client_adapter_validate_endpoint(state, endpoint)
  match message {
    Request(request) => {
      let id = request.id
      let decoded = try
        decode_client_request(request.method_name, request.params)
      catch {
        error => Err(client_adapter_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) => Immediate(client_adapter_response(state, id, error))
        Ok(request) => client_adapter_admit_request(state, id, request)
      }
    }
    Notification(notification) => {
      let decoded = try
        decode_client_notification(
          notification.method_name,
          notification.params,
        )
      catch {
        error => Err(client_adapter_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) =>
          Immediate(
            client_adapter_trace(state, notification.method_name, error),
          )
        Ok(notification) =>
          client_adapter_admit_notification(state, notification)
      }
    }
    Response(_) => raise UnexpectedMessage(kind="response")
  }
}

///|
/// Execute exactly one already-admitted typed operation.  This phase has no
/// protocol state and cannot emit a response, trace, queue operation, or
/// cancellation intent.
pub async fn client_adapter_execute(
  invocation : ClientAdapterInvocation,
  endpoint : ClientEndpoint,
) -> ClientAdapterCompletion noraise {
  match invocation {
    RequestPermissionInvocation(id~, params~) =>
      RequestPermissionCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.request_permission(params)
        }),
      )
    FsReadTextFileInvocation(id~, params~) =>
      FsReadTextFileCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.read_text_file(params)
        }),
      )
    FsWriteTextFileInvocation(id~, params~) =>
      FsWriteTextFileCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.write_text_file(params)
        }),
      )
    TerminalCreateInvocation(id~, params~) =>
      TerminalCreateCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.terminal_create(params)
        }),
      )
    TerminalOutputInvocation(id~, params~) =>
      TerminalOutputCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.terminal_output(params)
        }),
      )
    TerminalWaitForExitInvocation(id~, params~) =>
      TerminalWaitForExitCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.terminal_wait_for_exit(params)
        }),
      )
    TerminalKillInvocation(id~, params~) =>
      TerminalKillCompleted(
        id~,
        result=client_adapter_call(async fn() { endpoint.terminal_kill(params) }),
      )
    TerminalReleaseInvocation(id~, params~) =>
      TerminalReleaseCompleted(
        id~,
        result=client_adapter_call(async fn() {
          endpoint.terminal_release(params)
        }),
      )
    ElicitationCreateInvocation(id~, params~) =>
      match params {
        Form(params) =>
          ElicitationCreateCompleted(
            id~,
            result=client_adapter_call(async fn() {
              endpoint.elicitation_form(params)
            }),
          )
        Url(params) =>
          ElicitationCreateCompleted(
            id~,
            result=client_adapter_call(async fn() {
              endpoint.elicitation_url(params)
            }),
          )
      }
    SessionUpdateInvocation(params~) =>
      SessionUpdateCompleted(
        result=client_adapter_call(async fn() {
          endpoint.session_update(params)
        }),
      )
    ElicitationCompleteInvocation(params~) =>
      ElicitationCompleteCompleted(
        result=client_adapter_call(async fn() {
          endpoint.elicitation_complete(params)
        }),
      )
  }
}

///|
/// Complete one admitted invocation in the owner loop.  The adapter checks
/// only the typed variant and request id; correlation lifetime belongs to the
/// connection reducer that owns the task table.
pub fn client_adapter_complete(
  state : ClientAdapterState,
  invocation : ClientAdapterInvocation,
  completion : ClientAdapterCompletion,
) -> ClientAdapterStep raise ClientAdapterError {
  match invocation {
    RequestPermissionInvocation(id~, params~) =>
      match completion {
        RequestPermissionCompleted(id=completion_id, result~) if completion_id ==
          id => client_adapter_complete_permission(state, id, params, result)
        RequestPermissionCompleted(..) | _ =>
          raise CompletionMismatch(method_name="session/request_permission")
      }
    FsReadTextFileInvocation(id~, params=_) =>
      match completion {
        FsReadTextFileCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, read_text_file_result_to_json,
          )
        FsReadTextFileCompleted(..) | _ =>
          raise CompletionMismatch(method_name="fs/read_text_file")
      }
    FsWriteTextFileInvocation(id~, params=_) =>
      match completion {
        FsWriteTextFileCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, write_text_file_result_to_json,
          )
        FsWriteTextFileCompleted(..) | _ =>
          raise CompletionMismatch(method_name="fs/write_text_file")
      }
    TerminalCreateInvocation(id~, params=_) =>
      match completion {
        TerminalCreateCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, terminal_create_result_to_json,
          )
        TerminalCreateCompleted(..) | _ =>
          raise CompletionMismatch(method_name="terminal/create")
      }
    TerminalOutputInvocation(id~, params=_) =>
      match completion {
        TerminalOutputCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, terminal_output_result_to_json,
          )
        TerminalOutputCompleted(..) | _ =>
          raise CompletionMismatch(method_name="terminal/output")
      }
    TerminalWaitForExitInvocation(id~, params=_) =>
      match completion {
        TerminalWaitForExitCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, terminal_wait_for_exit_result_to_json,
          )
        TerminalWaitForExitCompleted(..) | _ =>
          raise CompletionMismatch(method_name="terminal/wait_for_exit")
      }
    TerminalKillInvocation(id~, params=_) =>
      match completion {
        TerminalKillCompleted(id=completion_id, result~) if completion_id == id =>
          client_adapter_complete_result(
            state, id, result, terminal_kill_result_to_json,
          )
        TerminalKillCompleted(..) | _ =>
          raise CompletionMismatch(method_name="terminal/kill")
      }
    TerminalReleaseInvocation(id~, params=_) =>
      match completion {
        TerminalReleaseCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, terminal_release_result_to_json,
          )
        TerminalReleaseCompleted(..) | _ =>
          raise CompletionMismatch(method_name="terminal/release")
      }
    ElicitationCreateInvocation(id~, params=_) =>
      match completion {
        ElicitationCreateCompleted(id=completion_id, result~) if completion_id ==
          id =>
          client_adapter_complete_result(
            state, id, result, elicitation_create_result_to_json,
          )
        ElicitationCreateCompleted(..) | _ =>
          raise CompletionMismatch(method_name="elicitation/create")
      }
    SessionUpdateInvocation(params=_) =>
      match completion {
        SessionUpdateCompleted(result~) =>
          client_adapter_complete_notification(state, "session/update", result)
        _ => raise CompletionMismatch(method_name="session/update")
      }
    ElicitationCompleteInvocation(params=_) =>
      match completion {
        ElicitationCompleteCompleted(result~) =>
          client_adapter_complete_notification(
            state, "elicitation/complete", result,
          )
        _ => raise CompletionMismatch(method_name="elicitation/complete")
      }
  }
}
