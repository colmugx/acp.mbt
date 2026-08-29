///|
/// Runtime-facing commands emitted by the Agent adapter.  These values are
/// intents only; the adapter never owns tasks, queues, or connection state.
pub(all) enum AgentAdapterCommand {
  CancelRequest(request_id~ : RequestId)
  TraceError(method_name~ : String, error~ : JsonRpcError)
  CloseConnection(reason~ : String)
} derive(Eq, Debug)

///|
/// Typed adapter output.  Responses and notifications are wire values that
/// the owner loop serializes; commands are interpreted by the native runtime.
pub(all) enum AgentAdapterOutput {
  Response(JsonRpcResponse)
  Notification(JsonRpcNotification)
  Command(AgentAdapterCommand)
} derive(Eq, Debug)

///|
/// Authentication/lifecycle reservations are immutable protocol state.  A
/// pending reservation prevents a second state-changing request from using a
/// stale snapshot while its first handler is still running.
pub(all) enum AgentAdapterReservation {
  Idle
  AuthenticatePending(RequestId)
  LogoutPending(RequestId)
} derive(Eq, Debug)

///|
/// State owned by the connection/reducer loop.  Handler tasks receive a copy
/// of this value only through an admission result; they never mutate it.
pub(all) struct AgentAdapterState {
  protocol : AgentProtocolState
  reservation : AgentAdapterReservation
} derive(Eq, Debug)

///|
pub fn agent_adapter_state_new(
  protocol~ : AgentProtocolState,
) -> AgentAdapterState {
  { protocol, reservation: Idle, }
}

///|
pub fn AgentAdapterState::protocol(
  self : AgentAdapterState,
) -> AgentProtocolState {
  self.protocol
}

///|
pub fn AgentAdapterState::reservation(
  self : AgentAdapterState,
) -> AgentAdapterReservation {
  self.reservation
}

///|
/// One explicit state transition produced by admission or completion.
pub(all) struct AgentAdapterStep {
  state : AgentAdapterState
  outputs : Array[AgentAdapterOutput]
} derive(Eq, Debug)

///|
/// Admission is synchronous and owner-loop controlled.  Initialize and
/// protocol errors are immediate; only typed invocations cross the async task
/// boundary.
pub(all) enum AgentAdapterAdmission {
  Immediate(AgentAdapterStep)
  Invoke(state~ : AgentAdapterState, invocation~ : AgentAdapterInvocation)
}

///|
/// Fail-fast adapter failures indicate an invalid composition boundary or a
/// completion that no longer belongs to the owner-held reservation.
pub(all) suberror AgentAdapterError {
  EndpointMismatch(reason~ : String)
  UnexpectedMessage(kind~ : String)
  LateCompletion(request_id~ : RequestId)
  CompletionMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
fn agent_adapter_response_id(id : RequestId) -> JsonRpcId {
  match id {
    String(value) => String(value)
    Number(value) => Number(value)
    Null => Null
  }
}

///|
fn agent_adapter_response(
  state : AgentAdapterState,
  id : RequestId,
  error : JsonRpcError,
) -> AgentAdapterStep {
  {
    state,
    outputs: [
      Response(JsonRpcResponse::error(id=agent_adapter_response_id(id), error~)),
    ],
  }
}

///|
fn agent_adapter_success(
  state : AgentAdapterState,
  id : RequestId,
  result : Json,
) -> AgentAdapterStep {
  { state, outputs: [Response(JsonRpcResponse::success(id~, result~))], }
}

///|
fn agent_adapter_trace(
  state : AgentAdapterState,
  method_name : String,
  error : JsonRpcError,
) -> AgentAdapterStep {
  { state, outputs: [Command(TraceError(method_name~, error~))], }
}

///|
fn agent_adapter_endpoint_config(
  endpoint : AgentEndpoint,
) -> AgentProtocolConfig {
  {
    agent_capabilities: Value(endpoint.capabilities()),
    auth_methods: endpoint.auth_methods(),
    agent_info: Value(endpoint.info()),
  }
}

///|
fn agent_adapter_validate_endpoint(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
) -> Unit raise AgentAdapterError {
  let expected = agent_adapter_endpoint_config(endpoint)
  if state.protocol.config.agent_capabilities != expected.agent_capabilities {
    raise EndpointMismatch(reason="state capabilities do not match endpoint")
  }
  if state.protocol.config.auth_methods != expected.auth_methods {
    raise EndpointMismatch(reason="state auth methods do not match endpoint")
  }
  match state.protocol.config.agent_info {
    Omitted | Null => ()
    Value(info) =>
      match expected.agent_info {
        Value(expected_info) if info != expected_info =>
          raise EndpointMismatch(
            reason="state agent info does not match endpoint",
          )
        _ => ()
      }
  }
}

///|
fn agent_adapter_state_with_endpoint(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
) -> AgentAdapterState {
  {
    ..state,
    protocol: {
      ..state.protocol,
      config: agent_adapter_endpoint_config(endpoint),
    },
  }
}

///|
fn agent_adapter_decode_error_message(error : ProtocolDecodeError) -> String {
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
/// One wire error that carries its human-readable detail on both JSON-RPC
/// channels: `message` (what editors render by default) and `data` (the
/// field Zed's error builder surfaces). Every caller passes an
/// already-sanitized, host-authored string — this helper never wraps raw
/// payloads or stack detail; it only stops the adapter from discarding what
/// handlers chose to tell the user.
fn agent_adapter_detailed_error(
  code~ : @jsonrpc.JsonRpcErrorCode,
  message~ : String,
) -> JsonRpcError {
  JsonRpcError::new(code~, message~, data=Json::string(message))
}

///|
fn agent_adapter_message_error(error : AgentMessageError) -> JsonRpcError {
  match error {
    InvalidParams(method_name~, cause~) =>
      agent_adapter_detailed_error(
        code=InvalidParams,
        message=method_name + ": " + agent_adapter_decode_error_message(cause),
      )
    UnknownMethod(method_name~) =>
      agent_adapter_detailed_error(
        code=MethodNotFound,
        message="unknown method: " + method_name,
      )
    WrongDirection(method_name~) =>
      agent_adapter_detailed_error(
        code=MethodNotFound,
        message="method is not an agent request: " + method_name,
      )
    WrongKind(method_name~) =>
      agent_adapter_detailed_error(
        code=InvalidRequest,
        message="wrong message kind for method: " + method_name,
      )
  }
}

///|
fn agent_adapter_protocol_error(error : AgentProtocolError) -> JsonRpcError {
  match error {
    AuthenticationRequired(method_name~) =>
      agent_adapter_detailed_error(
        code=AuthRequired,
        message="authentication required before " + method_name,
      )
    AuthenticationMethodNotAdvertised(method_id~) =>
      agent_adapter_detailed_error(
        code=AuthRequired,
        message="authentication method is not advertised: " + method_id,
      )
    NotAuthenticated =>
      agent_adapter_detailed_error(
        code=AuthRequired,
        message="agent is not authenticated",
      )
    CapabilityDenied(method_name~, capability~) =>
      agent_adapter_detailed_error(
        code=ResourceNotFound,
        message="capability '" +
          capability +
          "' required by " +
          method_name +
          " is not enabled",
      )
    NotInitialized(method_name~) =>
      agent_adapter_detailed_error(
        code=InvalidRequest,
        message="initialize required before " + method_name,
      )
    AlreadyInitialized =>
      agent_adapter_detailed_error(
        code=InvalidRequest,
        message="agent is already initialized",
      )
    AuthenticationNotRequired =>
      agent_adapter_detailed_error(
        code=InvalidRequest,
        message="authentication is not required",
      )
    AlreadyAuthenticated =>
      agent_adapter_detailed_error(
        code=InvalidRequest,
        message="agent is already authenticated",
      )
    InvalidEvent(reason~) =>
      agent_adapter_detailed_error(code=InvalidRequest, message=reason)
  }
}

///|
fn agent_adapter_handler_error(error : HandlerError) -> JsonRpcError {
  match error {
    Application(message~) =>
      agent_adapter_detailed_error(code=InternalError, message~)
    InvalidParams(message~) =>
      agent_adapter_detailed_error(code=InvalidParams, message~)
    Cancelled => JsonRpcError::request_cancelled()
    UnavailableOperation(method_name~) =>
      agent_adapter_detailed_error(
        code=ResourceNotFound,
        message="agent does not implement operation: " + method_name,
      )
  }
}

///|
fn agent_adapter_reduce_request(
  state : AgentAdapterState,
  request : AgentRequest,
) -> Result[AgentProtocolStep, JsonRpcError] {
  try agent_protocol_reduce(state.protocol, Request(request)) catch {
    error => Err(agent_adapter_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn agent_adapter_reduce_notification(
  state : AgentAdapterState,
  notification : AgentNotification,
) -> Result[AgentProtocolStep, JsonRpcError] {
  try agent_protocol_reduce(state.protocol, Notification(notification)) catch {
    error => Err(agent_adapter_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn[T] agent_adapter_encode_success(
  state : AgentAdapterState,
  id : RequestId,
  value : T,
  encode : (T) -> Json raise ProtocolDecodeError,
) -> Result[AgentAdapterStep, JsonRpcError] {
  try encode(value) catch {
    error =>
      Err(
        agent_adapter_detailed_error(
          code=InternalError,
          message="failed to encode response: " +
            agent_adapter_decode_error_message(error),
        ),
      )
  } noraise {
    result => Ok(agent_adapter_success(state, id, result))
  }
}

///|
async fn[T] agent_adapter_call(
  handler : async () -> T,
) -> Result[T, HandlerError] noraise {
  try handler() catch {
    error =>
      if @async.is_cancellation_error(error) {
        Err(Cancelled)
      } else {
        match error {
          HandlerError::Application(message~) => Err(Application(message~))
          HandlerError::InvalidParams(message~) => Err(InvalidParams(message~))
          HandlerError::Cancelled => Err(Cancelled)
          HandlerError::UnavailableOperation(method_name~) =>
            Err(UnavailableOperation(method_name~))
          _ =>
            // An unexpected exception is a handler defect: name it with the
            // error's display text so a user can paste it to a developer.
            Err(
              Application(message="agent handler failed: " + error.to_string()),
            )
        }
      }
  } noraise {
    value => Ok(value)
  }
}

///|
fn agent_adapter_busy(
  state : AgentAdapterState,
  id : RequestId,
) -> AgentAdapterAdmission {
  Immediate(agent_adapter_response(state, id, JsonRpcError::invalid_request()))
}

///|
fn agent_adapter_release_reservation(
  state : AgentAdapterState,
  id : RequestId,
) -> AgentAdapterState raise AgentAdapterError {
  match state.reservation {
    AuthenticatePending(reserved) if reserved == id =>
      { ..state, reservation: Idle, }
    LogoutPending(reserved) if reserved == id => { ..state, reservation: Idle, }
    _ => raise LateCompletion(request_id=id)
  }
}

///|
fn agent_adapter_reservation_busy(state : AgentAdapterState) -> Bool {
  match state.reservation {
    Idle => false
    AuthenticatePending(_) | LogoutPending(_) => true
  }
}

///|
fn agent_adapter_initialize(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
  id : RequestId,
  params : InitializeParams,
) -> AgentAdapterAdmission {
  match agent_adapter_reduce_request(state, Initialize(params)) {
    Err(error) => Immediate(agent_adapter_response(state, id, error))
    Ok(step) => {
      let next_state = agent_adapter_state_with_endpoint(
        { ..state, protocol: step.state, },
        endpoint,
      )
      let result : InitializeResult = {
        protocol_version: 1,
        agent_capabilities: Value(endpoint.capabilities()),
        auth_methods: endpoint.auth_methods(),
        agent_info: Value(endpoint.info()),
        meta: Omitted,
      }
      let encoded : Result[Json, ProtocolDecodeError] = Ok(
        initialize_result_to_json(result),
      ) catch {
        error => Err(error)
      }
      match encoded {
        Err(error) =>
          Immediate(
            agent_adapter_response(
              next_state,
              id,
              agent_adapter_detailed_error(
                code=InternalError,
                message="failed to encode initialize result: " +
                  agent_adapter_decode_error_message(error),
              ),
            ),
          )
        Ok(json) => Immediate(agent_adapter_success(next_state, id, json))
      }
    }
  }
}

///|
fn agent_adapter_authenticate(
  state : AgentAdapterState,
  id : RequestId,
  params : AuthenticateParams,
) -> AgentAdapterAdmission {
  if agent_adapter_reservation_busy(state) {
    return agent_adapter_busy(state, id)
  }
  match agent_adapter_reduce_request(state, Authenticate(params)) {
    Err(error) => Immediate(agent_adapter_response(state, id, error))
    Ok(step) =>
      Invoke(
        state={ protocol: step.state, reservation: AuthenticatePending(id), },
        invocation=AuthenticateInvocation(id~, params~),
      )
  }
}

///|
fn agent_adapter_logout(
  state : AgentAdapterState,
  id : RequestId,
  params : LogoutParams,
) -> AgentAdapterAdmission {
  if agent_adapter_reservation_busy(state) {
    return agent_adapter_busy(state, id)
  }
  match agent_adapter_reduce_request(state, Logout(params)) {
    Err(error) => Immediate(agent_adapter_response(state, id, error))
    Ok(step) =>
      Invoke(
        state={ protocol: step.state, reservation: LogoutPending(id), },
        invocation=LogoutInvocation(id~, params~),
      )
  }
}

///|
fn agent_adapter_session_request(
  state : AgentAdapterState,
  id : RequestId,
  request : AgentRequest,
  invocation : AgentAdapterInvocation,
) -> AgentAdapterAdmission {
  match state.reservation {
    LogoutPending(_) => return agent_adapter_busy(state, id)
    AuthenticatePending(_) | Idle => ()
  }
  match agent_adapter_reduce_request(state, request) {
    Err(error) => Immediate(agent_adapter_response(state, id, error))
    Ok(step) => Invoke(state={ ..state, protocol: step.state, }, invocation~)
  }
}

///|
fn agent_adapter_admit_request(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
  id : RequestId,
  request : AgentRequest,
) -> AgentAdapterAdmission {
  match request {
    Initialize(params) => agent_adapter_initialize(state, endpoint, id, params)
    Authenticate(params) => agent_adapter_authenticate(state, id, params)
    Logout(params) => agent_adapter_logout(state, id, params)
    SessionNew(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionNewInvocation(id~, params~),
      )
    SessionLoad(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionLoadInvocation(id~, params~),
      )
    SessionResume(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionResumeInvocation(id~, params~),
      )
    SessionFork(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionForkInvocation(id~, params~),
      )
    SessionList(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionListInvocation(id~, params~),
      )
    SessionDelete(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionDeleteInvocation(id~, params~),
      )
    SessionClose(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionCloseInvocation(id~, params~),
      )
    SessionSetMode(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionSetModeInvocation(id~, params~),
      )
    SessionSetConfigOption(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionSetConfigOptionInvocation(id~, params~),
      )
    SessionPrompt(params) =>
      agent_adapter_session_request(
        state,
        id,
        request,
        SessionPromptInvocation(id~, params~),
      )
  }
}

///|
fn agent_adapter_admit_notification(
  state : AgentAdapterState,
  notification : AgentNotification,
) -> AgentAdapterAdmission {
  match notification {
    SessionCancel(params) =>
      match agent_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(agent_adapter_trace(state, "session/cancel", error))
        Ok(step) =>
          Invoke(
            state={ protocol: step.state, reservation: state.reservation, },
            invocation=SessionCancelInvocation(params~),
          )
      }
    CancelRequest(request_id) =>
      match agent_adapter_reduce_notification(state, notification) {
        Err(error) =>
          Immediate(agent_adapter_trace(state, "$/cancel_request", error))
        Ok(step) =>
          Immediate({
            state: { ..state, protocol: step.state, },
            outputs: [Command(CancelRequest(request_id~))],
          })
      }
  }
}

///|
/// Decode and admit one message.  This function is synchronous and pure from
/// the owner loop's perspective; it never calls an application handler.
pub fn agent_adapter_admit(
  state : AgentAdapterState,
  endpoint : AgentEndpoint,
  message : JsonRpcMessage,
) -> AgentAdapterAdmission raise AgentAdapterError {
  agent_adapter_validate_endpoint(state, endpoint)
  match message {
    Request(request) => {
      let id = request.id
      let decoded = try
        decode_agent_request(request.method_name, request.params)
      catch {
        error => Err(agent_adapter_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) => Immediate(agent_adapter_response(state, id, error))
        Ok(request) => agent_adapter_admit_request(state, endpoint, id, request)
      }
    }
    Notification(notification) => {
      let decoded = try
        decode_agent_notification(notification.method_name, notification.params)
      catch {
        error => Err(agent_adapter_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) =>
          Immediate(agent_adapter_trace(state, notification.method_name, error))
        Ok(notification) =>
          agent_adapter_admit_notification(state, notification)
      }
    }
    Response(_) => raise UnexpectedMessage(kind="response")
  }
}

///|
fn[T] agent_adapter_complete_result(
  state : AgentAdapterState,
  id : RequestId,
  result : Result[T, HandlerError],
  encode : (T) -> Json raise ProtocolDecodeError,
) -> AgentAdapterStep {
  match result {
    Err(error) =>
      agent_adapter_response(state, id, agent_adapter_handler_error(error))
    Ok(value) =>
      match agent_adapter_encode_success(state, id, value, encode) {
        Ok(step) => step
        Err(error) => agent_adapter_response(state, id, error)
      }
  }
}

///|
fn agent_adapter_complete_authenticate(
  state : AgentAdapterState,
  id : RequestId,
  params : AuthenticateParams,
  result : Result[AuthenticateResult, HandlerError],
) -> AgentAdapterStep raise AgentAdapterError {
  let released = agent_adapter_release_reservation(state, id)
  match result {
    Err(error) =>
      agent_adapter_response(released, id, agent_adapter_handler_error(error))
    Ok(value) => {
      let reduced = agent_protocol_reduce(
        released.protocol,
        AuthenticationSucceeded(method_id=params.method_id),
      ) catch {
        error =>
          return agent_adapter_response(
            released,
            id,
            agent_adapter_protocol_error(error),
          )
      }
      let next = { ..released, protocol: reduced.state, }
      match
        agent_adapter_encode_success(
          next, id, value, authenticate_result_to_json,
        ) {
        Ok(step) => step
        Err(error) => agent_adapter_response(next, id, error)
      }
    }
  }
}

///|
fn agent_adapter_complete_logout(
  state : AgentAdapterState,
  id : RequestId,
  result : Result[LogoutResult, HandlerError],
) -> AgentAdapterStep raise AgentAdapterError {
  let released = agent_adapter_release_reservation(state, id)
  match result {
    Err(error) =>
      agent_adapter_response(released, id, agent_adapter_handler_error(error))
    Ok(value) => {
      let reduced = agent_protocol_reduce(released.protocol, LoggedOut) catch {
        error =>
          return agent_adapter_response(
            released,
            id,
            agent_adapter_protocol_error(error),
          )
      }
      let next = { ..released, protocol: reduced.state, }
      match
        agent_adapter_encode_success(next, id, value, logout_result_to_json) {
        Ok(step) => step
        Err(error) => agent_adapter_response(next, id, error)
      }
    }
  }
}

///|
/// Complete one admitted invocation in the owner loop.  A state-changing
/// completion must match its immutable reservation; duplicate/late auth and
/// logout completions fail explicitly instead of producing a second response.
pub fn agent_adapter_complete(
  state : AgentAdapterState,
  invocation : AgentAdapterInvocation,
  completion : AgentAdapterCompletion,
) -> AgentAdapterStep raise AgentAdapterError {
  match invocation {
    AuthenticateInvocation(id~, params~) =>
      match completion {
        AuthenticateCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_authenticate(state, id, params, result)
        AuthenticateCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="authenticate")
      }
    LogoutInvocation(id~, params=_) =>
      match completion {
        LogoutCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_logout(state, id, result)
        LogoutCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="logout")
      }
    SessionNewInvocation(id~, params=_) =>
      match completion {
        SessionNewCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, new_session_result_to_json,
          )
        SessionNewCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/new")
      }
    SessionLoadInvocation(id~, params=_) =>
      match completion {
        SessionLoadCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, load_session_result_to_json,
          )
        SessionLoadCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/load")
      }
    SessionResumeInvocation(id~, params=_) =>
      match completion {
        SessionResumeCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, resume_session_result_to_json,
          )
        SessionResumeCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/resume")
      }
    SessionForkInvocation(id~, params=_) =>
      match completion {
        SessionForkCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, fork_session_result_to_json,
          )
        SessionForkCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/fork")
      }
    SessionListInvocation(id~, params=_) =>
      match completion {
        SessionListCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, list_sessions_result_to_json,
          )
        SessionListCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/list")
      }
    SessionDeleteInvocation(id~, params=_) =>
      match completion {
        SessionDeleteCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, delete_session_result_to_json,
          )
        SessionDeleteCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/delete")
      }
    SessionCloseInvocation(id~, params=_) =>
      match completion {
        SessionCloseCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, close_session_result_to_json,
          )
        SessionCloseCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/close")
      }
    SessionSetModeInvocation(id~, params=_) =>
      match completion {
        SessionSetModeCompleted(id=completion_id, result~) if completion_id ==
          id =>
          agent_adapter_complete_result(
            state, id, result, set_session_mode_result_to_json,
          )
        SessionSetModeCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/set_mode")
      }
    SessionSetConfigOptionInvocation(id~, params=_) =>
      match completion {
        SessionSetConfigOptionCompleted(id=completion_id, result~) if completion_id ==
          id =>
          agent_adapter_complete_result(
            state, id, result, set_session_config_option_result_to_json,
          )
        SessionSetConfigOptionCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/set_config_option")
      }
    SessionPromptInvocation(id~, params=_) =>
      match completion {
        SessionPromptCompleted(id=completion_id, result~) if completion_id == id =>
          agent_adapter_complete_result(
            state, id, result, prompt_result_to_json,
          )
        SessionPromptCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/prompt")
      }
    SessionCancelInvocation(_) =>
      match completion {
        SessionCancelCompleted(result~) =>
          match result {
            Ok(_) => { state, outputs: [], }
            Err(error) =>
              agent_adapter_trace(
                state,
                "session/cancel",
                agent_adapter_handler_error(error),
              )
          }
        _ => raise CompletionMismatch(method_name="session/cancel")
      }
  }
}
