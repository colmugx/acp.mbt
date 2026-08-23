///|
/// Runtime-facing commands emitted by the v2 Client adapter.  These values
/// are data only; cancellation itself is owned by the connection runtime.
/// `CloseConnection` is deliberately absent: it exists only on the Client
/// state machine's failed-initialize path, which never originates from an
/// inbound Agent message.
pub(all) enum ExperimentalV2ClientAdapterCommand {
  CancelRequest(request_id~ : ExperimentalV2RequestId)
  TraceError(method_name~ : String, error~ : @jsonrpc.JsonRpcError)
} derive(Eq, Debug)

///|
/// Typed adapter output.  Responses are wire values the owner loop
/// serializes; commands are interpreted by the runtime.
pub(all) enum ExperimentalV2ClientAdapterOutput {
  Response(@jsonrpc.JsonRpcResponse)
  Command(ExperimentalV2ClientAdapterCommand)
} derive(Eq, Debug)

///|
/// State owned by the connection owner loop.  Handler tasks receive this
/// value only through an admission result; they never mutate it.
pub(all) struct ExperimentalV2ClientAdapterState {
  protocol : ExperimentalV2ClientState
} derive(Eq, Debug)

///|
pub fn experimental_v2_client_adapter_state_new(
  protocol~ : ExperimentalV2ClientState,
) -> ExperimentalV2ClientAdapterState {
  { protocol, }
}

///|
pub fn ExperimentalV2ClientAdapterState::protocol(
  self : ExperimentalV2ClientAdapterState,
) -> ExperimentalV2ClientState {
  self.protocol
}

///|
/// One explicit state transition produced by admission or completion.
pub(all) struct ExperimentalV2ClientAdapterStep {
  state : ExperimentalV2ClientAdapterState
  outputs : Array[ExperimentalV2ClientAdapterOutput]
} derive(Eq, Debug)

///|
/// Admission is synchronous and owner-loop controlled.  Protocol failures are
/// immediate; only typed invocations cross the async task boundary.
pub(all) enum ExperimentalV2ClientAdmission {
  Immediate(ExperimentalV2ClientAdapterStep)
  Invoke(
    state~ : ExperimentalV2ClientAdapterState,
    invocation~ : ExperimentalV2ClientInvocation
  )
}

///|
/// Fail-fast adapter failures: an invalid composition boundary or a
/// completion that no longer belongs to the admitted operation.
pub(all) suberror ExperimentalV2ClientAdapterError {
  EndpointMismatch(reason~ : String)
  UnexpectedMessage(kind~ : String)
  LateCompletion(request_id~ : @jsonrpc.RequestId)
  CompletionMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
/// Failures raised while decoding one inbound v2 Client message into the
/// typed request/notification set.
pub(all) suberror ExperimentalV2ClientMessageError {
  UnknownMethod(method_name~ : String)
  InvalidParams(method_name~ : String, cause~ : ExperimentalV2DecodeError)
} derive(Eq, Debug)

///|
fn experimental_v2_client_response_id(
  id : @jsonrpc.RequestId,
) -> @jsonrpc.JsonRpcId {
  match id {
    String(value) => String(value)
    Number(value) => Number(value)
    Null => Null
  }
}

///|
/// One wire error carrying its sanitized detail on both JSON-RPC channels:
/// `message` (rendered by default) and `data` (surfaced by error builders).
/// Callers pass host-authored strings only.
fn experimental_v2_client_detailed_error(
  code~ : @jsonrpc.JsonRpcErrorCode,
  message~ : String,
) -> @jsonrpc.JsonRpcError {
  @jsonrpc.JsonRpcError::new(code~, message~, data=Json::string(message))
}

///|
fn experimental_v2_client_response(
  state : ExperimentalV2ClientAdapterState,
  id : @jsonrpc.RequestId,
  error : @jsonrpc.JsonRpcError,
) -> ExperimentalV2ClientAdapterStep {
  {
    state,
    outputs: [
      Response(
        @jsonrpc.JsonRpcResponse::error(
          id=experimental_v2_client_response_id(id),
          error~,
        ),
      ),
    ],
  }
}

///|
fn experimental_v2_client_success(
  state : ExperimentalV2ClientAdapterState,
  id : @jsonrpc.RequestId,
  result : Json,
) -> ExperimentalV2ClientAdapterStep {
  {
    state,
    outputs: [Response(@jsonrpc.JsonRpcResponse::success(id~, result~))],
  }
}

///|
fn experimental_v2_client_trace(
  state : ExperimentalV2ClientAdapterState,
  method_name : String,
  error : @jsonrpc.JsonRpcError,
) -> ExperimentalV2ClientAdapterStep {
  { state, outputs: [Command(TraceError(method_name~, error~))] }
}

///|
fn experimental_v2_client_validate_endpoint(
  state : ExperimentalV2ClientAdapterState,
  endpoint : ExperimentalV2ClientEndpoint,
) -> Unit raise ExperimentalV2ClientAdapterError {
  if state.protocol.capabilities != endpoint.capabilities() {
    raise EndpointMismatch(reason="state capabilities do not match endpoint")
  }
}

///|
fn experimental_v2_client_decode_error_message(
  error : ExperimentalV2DecodeError,
) -> String {
  match error {
    JsonParse(message~) => message
    ExpectedObject(path~) => "expected object at " + path
    ExpectedArray(path~) => "expected array at " + path
    ExpectedString(path~) => "expected string at " + path
    ExpectedBoolean(path~) => "expected boolean at " + path
    ExpectedNumber(path~) => "expected number at " + path
    MissingField(path~) => "missing field at " + path
    UnknownField(path~) => "unknown field at " + path
    InvalidField(path~, reason~) => path + ": " + reason
    InvalidDiscriminator(path~, value~) => path + ": " + value
    InvalidPath(path~, value~) => path + ": " + value
    InvalidBase64(path~) => "invalid base64 at " + path
  }
}

///|
fn experimental_v2_client_message_error(
  error : ExperimentalV2ClientMessageError,
) -> @jsonrpc.JsonRpcError {
  match error {
    InvalidParams(method_name~, cause~) =>
      experimental_v2_client_detailed_error(
        code=InvalidParams,
        message=method_name +
          ": " +
          experimental_v2_client_decode_error_message(cause),
      )
    UnknownMethod(method_name~) =>
      experimental_v2_client_detailed_error(
        code=MethodNotFound,
        message="unknown method: " + method_name,
      )
  }
}

///|
/// Typed protocol failures map onto JSON-RPC codes once, here.  Readiness
/// violations settle on `InvalidRequest`; the closed elicitation capability
/// gates settle on `ResourceNotFound`; unknown inbound names are
/// `MethodNotFound`.  The initialize-negotiation arms are total-only: no
/// inbound Agent message can produce them.
fn experimental_v2_client_protocol_error(
  error : ExperimentalV2ClientProtocolError,
) -> @jsonrpc.JsonRpcError {
  match error {
    NotReady(method_name~) =>
      experimental_v2_client_detailed_error(
        code=InvalidRequest,
        message="initialize required before " + method_name,
      )
    AlreadyReady =>
      experimental_v2_client_detailed_error(
        code=InvalidRequest,
        message="client is already initialized",
      )
    UnsupportedVersion(offered~) =>
      experimental_v2_client_detailed_error(
        code=InvalidRequest,
        message="unsupported protocol version: " + offered.to_string(),
      )
    CapabilityDenied(method_name~, capability~) =>
      experimental_v2_client_detailed_error(
        code=ResourceNotFound,
        message="capability '" +
          capability +
          "' required by " +
          method_name +
          " is not enabled",
      )
    UnknownMethod(method_name~) =>
      experimental_v2_client_detailed_error(
        code=MethodNotFound,
        message="unknown method: " + method_name,
      )
  }
}

///|
fn experimental_v2_client_handler_wire_error(
  error : ExperimentalV2ClientHandlerError,
) -> @jsonrpc.JsonRpcError {
  match error {
    Application(message~) =>
      experimental_v2_client_detailed_error(code=InternalError, message~)
    InvalidParams(message~) =>
      experimental_v2_client_detailed_error(code=InvalidParams, message~)
    Cancelled => @jsonrpc.JsonRpcError::request_cancelled()
    UnavailableOperation(method_name~) =>
      experimental_v2_client_detailed_error(
        code=ResourceNotFound,
        message="client does not implement operation: " + method_name,
      )
  }
}

///|
fn experimental_v2_client_request_params(params : Json?) -> Json {
  match params {
    Some(value) => value
    None => Json::object(Map([]))
  }
}

///|
fn[T] experimental_v2_client_decode_with(
  method_name : String,
  value : Json,
  decode : (Json) -> T raise ExperimentalV2DecodeError,
) -> T raise ExperimentalV2ClientMessageError {
  decode(value) catch {
    cause => raise InvalidParams(method_name~, cause~)
  }
}

///|
fn experimental_v2_client_decode_cancel_request(
  value : Json,
) -> ExperimentalV2RequestId raise ExperimentalV2DecodeError {
  let fields = experimental_v2_require_object(value, path="$/cancel_request")
  experimental_v2_reject_unknown(
    fields,
    ["requestId", "_meta"],
    prefix="$/cancel_request",
  )
  experimental_v2_decode_request_id(
    experimental_v2_required(
      fields,
      "requestId",
      path="$.cancel_request.requestId",
    ),
    path="$.cancel_request.requestId",
  )
}

///|
/// Decode one inbound method name and params into the typed v2 Client request
/// set.  Names outside the Agent-to-Client surface (including v1-only and
/// forward-direction names) are typed `UnknownMethod`, never guessed.
fn experimental_v2_client_decode_request(
  method_name : String,
  params : Json?,
) -> ExperimentalV2ClientRequest raise ExperimentalV2ClientMessageError {
  let value = experimental_v2_client_request_params(params)
  match method_name {
    "session/request_permission" =>
      SessionRequestPermission(
        experimental_v2_client_decode_with(method_name, value, value => {
          experimental_v2_decode_request_permission_request(value)
        }),
      )
    "elicitation/create" =>
      ElicitationCreate(
        experimental_v2_client_decode_with(method_name, value, value => {
          experimental_v2_decode_elicitation_create_request(value)
        }),
      )
    _ => raise UnknownMethod(method_name~)
  }
}

///|
fn experimental_v2_client_decode_notification(
  method_name : String,
  params : Json?,
) -> ExperimentalV2ClientNotification raise ExperimentalV2ClientMessageError {
  let value = experimental_v2_client_request_params(params)
  match method_name {
    "session/update" =>
      SessionUpdate(
        experimental_v2_client_decode_with(method_name, value, value => {
          experimental_v2_decode_update_session_notification(value)
        }),
      )
    "elicitation/complete" =>
      ElicitationComplete(
        experimental_v2_client_decode_with(method_name, value, value => {
          experimental_v2_decode_complete_elicitation_notification(value)
        }),
      )
    "$/cancel_request" =>
      CancelRequest(
        experimental_v2_client_decode_with(method_name, value, value => {
          experimental_v2_client_decode_cancel_request(value)
        }),
      )
    _ => raise UnknownMethod(method_name~)
  }
}

///|
fn experimental_v2_client_adapter_reduce_request(
  state : ExperimentalV2ClientAdapterState,
  request : ExperimentalV2ClientRequest,
) -> Result[ExperimentalV2ClientStep, @jsonrpc.JsonRpcError] {
  try
    experimental_v2_client_reduce(state.protocol, AgentRequest(request))
  catch {
    error => Err(experimental_v2_client_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn experimental_v2_client_adapter_reduce_notification(
  state : ExperimentalV2ClientAdapterState,
  notification : ExperimentalV2ClientNotification,
) -> Result[ExperimentalV2ClientStep, @jsonrpc.JsonRpcError] {
  try
    experimental_v2_client_reduce(
      state.protocol,
      AgentNotification(notification),
    )
  catch {
    error => Err(experimental_v2_client_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn experimental_v2_client_admit_request(
  state : ExperimentalV2ClientAdapterState,
  id : @jsonrpc.RequestId,
  request : ExperimentalV2ClientRequest,
) -> ExperimentalV2ClientAdmission {
  match experimental_v2_client_adapter_reduce_request(state, request) {
    Err(error) => Immediate(experimental_v2_client_response(state, id, error))
    Ok(step) => {
      let next : ExperimentalV2ClientAdapterState = { protocol: step.state }
      match request {
        SessionRequestPermission(params) =>
          Invoke(
            state=next,
            invocation=RequestPermissionInvocation(id~, params~),
          )
        ElicitationCreate(params) =>
          Invoke(
            state=next,
            invocation=ElicitationCreateInvocation(id~, params~),
          )
      }
    }
  }
}

///|
fn experimental_v2_client_admit_notification(
  state : ExperimentalV2ClientAdapterState,
  notification : ExperimentalV2ClientNotification,
) -> ExperimentalV2ClientAdmission {
  match notification {
    SessionUpdate(params) =>
      match
        experimental_v2_client_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(
            experimental_v2_client_trace(state, "session/update", error),
          )
        Ok(step) =>
          Invoke(
            state={ protocol: step.state },
            invocation=SessionUpdateInvocation(params~),
          )
      }
    ElicitationComplete(params) =>
      match
        experimental_v2_client_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(
            experimental_v2_client_trace(state, "elicitation/complete", error),
          )
        Ok(step) =>
          Invoke(
            state={ protocol: step.state },
            invocation=ElicitationCompleteInvocation(params~),
          )
      }
    CancelRequest(request_id) =>
      match
        experimental_v2_client_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(
            experimental_v2_client_trace(state, "$/cancel_request", error),
          )
        Ok(step) =>
          Immediate({
            state: { protocol: step.state },
            outputs: [Command(CancelRequest(request_id~))],
          })
      }
  }
}

///|
/// Decode and admit one Agent-to-Client JSON-RPC message.  Synchronous and
/// pure from the owner loop's perspective; it never calls an application
/// handler.
pub fn experimental_v2_client_adapter_admit(
  state : ExperimentalV2ClientAdapterState,
  endpoint : ExperimentalV2ClientEndpoint,
  message : @jsonrpc.JsonRpcMessage,
) -> ExperimentalV2ClientAdmission raise ExperimentalV2ClientAdapterError {
  experimental_v2_client_validate_endpoint(state, endpoint)
  match message {
    Request(request) => {
      let id = request.id
      let decoded = try
        experimental_v2_client_decode_request(
          request.method_name,
          request.params,
        )
      catch {
        error => Err(experimental_v2_client_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) =>
          Immediate(experimental_v2_client_response(state, id, error))
        Ok(request) => experimental_v2_client_admit_request(state, id, request)
      }
    }
    Notification(notification) => {
      let decoded = try
        experimental_v2_client_decode_notification(
          notification.method_name,
          notification.params,
        )
      catch {
        error => Err(experimental_v2_client_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) =>
          Immediate(
            experimental_v2_client_trace(state, notification.method_name, error),
          )
        Ok(notification) =>
          experimental_v2_client_admit_notification(state, notification)
      }
    }
    Response(_) => raise UnexpectedMessage(kind="response")
  }
}

///|
fn[T] experimental_v2_client_complete_result(
  state : ExperimentalV2ClientAdapterState,
  id : @jsonrpc.RequestId,
  result : Result[T, ExperimentalV2ClientHandlerError],
  encode : (T) -> Json raise ExperimentalV2DecodeError,
) -> ExperimentalV2ClientAdapterStep {
  match result {
    Err(error) =>
      experimental_v2_client_response(
        state,
        id,
        experimental_v2_client_handler_wire_error(error),
      )
    Ok(value) => {
      let encoded : Result[Json, @jsonrpc.JsonRpcError] = try
        encode(value)
      catch {
        _ => Err(@jsonrpc.JsonRpcError::internal_error())
      } noraise {
        json => Ok(json)
      }
      match encoded {
        Ok(json) => experimental_v2_client_success(state, id, json)
        Err(error) => experimental_v2_client_response(state, id, error)
      }
    }
  }
}

///|
fn experimental_v2_client_permission_option_offered(
  params : ExperimentalV2RequestPermissionRequest,
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
/// Permission cancellation is a normal ACP response, an unknown selected
/// option is a local invalid-params failure, and open-union outcomes
/// (extensions or future values authored by this client) pass through for
/// byte-faithful replay.  The admitted request remains the source of truth
/// for the option membership check.
fn experimental_v2_client_complete_permission(
  state : ExperimentalV2ClientAdapterState,
  id : @jsonrpc.RequestId,
  params : ExperimentalV2RequestPermissionRequest,
  result : Result[
    ExperimentalV2RequestPermissionResponse,
    ExperimentalV2ClientHandlerError,
  ],
) -> ExperimentalV2ClientAdapterStep {
  match result {
    Err(Cancelled) =>
      experimental_v2_client_complete_result(
        state,
        id,
        Ok({ outcome: Known(OutcomeCancelled), meta: None }),
        experimental_v2_encode_request_permission_response,
      )
    Err(error) =>
      experimental_v2_client_response(
        state,
        id,
        experimental_v2_client_handler_wire_error(error),
      )
    Ok(response) => {
      let valid = match response.outcome {
        Known(OutcomeCancelled) => true
        Known(OutcomeSelected(selected)) =>
          experimental_v2_client_permission_option_offered(
            params,
            selected.option_id,
          )
        Extension(..) | Future(..) => true
      }
      if valid {
        experimental_v2_client_complete_result(
          state,
          id,
          Ok(response),
          experimental_v2_encode_request_permission_response,
        )
      } else {
        experimental_v2_client_response(
          state,
          id,
          experimental_v2_client_detailed_error(
            code=InvalidParams,
            message="selected option was not offered by the request",
          ),
        )
      }
    }
  }
}

///|
fn experimental_v2_client_complete_notification(
  state : ExperimentalV2ClientAdapterState,
  method_name : String,
  result : Result[Unit, ExperimentalV2ClientHandlerError],
) -> ExperimentalV2ClientAdapterStep {
  match result {
    Ok(_) => { state, outputs: [] }
    Err(error) =>
      experimental_v2_client_trace(
        state,
        method_name,
        experimental_v2_client_handler_wire_error(error),
      )
  }
}

///|
/// Complete one admitted invocation in the owner loop.  The adapter checks
/// the typed variant and the wire id; correlation lifetime belongs to the
/// connection engine that owns the task table.  A duplicate, late, or
/// constructor-mismatched completion fails explicitly instead of producing a
/// second response.
pub fn experimental_v2_client_adapter_complete(
  state : ExperimentalV2ClientAdapterState,
  invocation : ExperimentalV2ClientInvocation,
  completion : ExperimentalV2ClientCompletion,
) -> ExperimentalV2ClientAdapterStep raise ExperimentalV2ClientAdapterError {
  match invocation {
    RequestPermissionInvocation(id~, params~) =>
      match completion {
        RequestPermissionCompleted(id=completion_id, result~) if completion_id ==
          id =>
          experimental_v2_client_complete_permission(state, id, params, result)
        RequestPermissionCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/request_permission")
      }
    ElicitationCreateInvocation(id~, params=_) =>
      match completion {
        ElicitationCreateCompleted(id=completion_id, result~) if completion_id ==
          id =>
          experimental_v2_client_complete_result(
            state, id, result, experimental_v2_encode_elicitation_create_response,
          )
        ElicitationCreateCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="elicitation/create")
      }
    SessionUpdateInvocation(params=_) =>
      match completion {
        SessionUpdateCompleted(result~) =>
          experimental_v2_client_complete_notification(
            state, "session/update", result,
          )
        _ => raise CompletionMismatch(method_name="session/update")
      }
    ElicitationCompleteInvocation(params=_) =>
      match completion {
        ElicitationCompleteCompleted(result~) =>
          experimental_v2_client_complete_notification(
            state, "elicitation/complete", result,
          )
        _ => raise CompletionMismatch(method_name="elicitation/complete")
      }
  }
}
