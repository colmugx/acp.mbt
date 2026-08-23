///|
/// Runtime-facing commands emitted by the v2 Agent adapter.  These values are
/// intents only; the adapter never owns tasks, queues, or connection state.
/// `CloseConnection` is deliberately absent: the v2 Agent state machine never
/// closes on a protocol failure — a rejected `initialize` version is answered
/// with this endpoint's own version and the endpoint stays pre-initialized.
pub(all) enum ExperimentalV2AgentAdapterCommand {
  CancelRequest(request_id~ : ExperimentalV2RequestId)
  TraceError(method_name~ : String, error~ : @jsonrpc.JsonRpcError)
} derive(Eq, Debug)

///|
/// Typed adapter output.  Responses are wire values the owner loop
/// serializes; commands are interpreted by the runtime.
pub(all) enum ExperimentalV2AgentAdapterOutput {
  Response(@jsonrpc.JsonRpcResponse)
  Notification(@jsonrpc.JsonRpcNotification)
  Command(ExperimentalV2AgentAdapterCommand)
} derive(Eq, Debug)

///|
/// Single-flight reservation for the two v2 state-changing auth requests.  A
/// pending reservation prevents a second auth request from racing the first
/// handler against a stale authentication snapshot.
pub(all) enum ExperimentalV2AgentReservation {
  Idle
  LoginPending(@jsonrpc.RequestId)
  LogoutPending(@jsonrpc.RequestId)
} derive(Eq, Debug)

///|
/// State owned by the connection owner loop.  Handler tasks receive this
/// value only through an admission result; they never mutate it.
pub(all) struct ExperimentalV2AgentAdapterState {
  protocol : ExperimentalV2AgentState
  reservation : ExperimentalV2AgentReservation
} derive(Eq, Debug)

///|
pub fn experimental_v2_agent_adapter_state_new(
  protocol~ : ExperimentalV2AgentState,
) -> ExperimentalV2AgentAdapterState {
  { protocol, reservation: Idle }
}

///|
pub fn ExperimentalV2AgentAdapterState::protocol(
  self : ExperimentalV2AgentAdapterState,
) -> ExperimentalV2AgentState {
  self.protocol
}

///|
pub fn ExperimentalV2AgentAdapterState::reservation(
  self : ExperimentalV2AgentAdapterState,
) -> ExperimentalV2AgentReservation {
  self.reservation
}

///|
/// One explicit state transition produced by admission or completion.
pub(all) struct ExperimentalV2AgentAdapterStep {
  state : ExperimentalV2AgentAdapterState
  outputs : Array[ExperimentalV2AgentAdapterOutput]
} derive(Eq, Debug)

///|
/// Admission is synchronous and owner-loop controlled.  Initialize answers
/// and protocol failures are immediate; only typed invocations cross the
/// async task boundary.
pub(all) enum ExperimentalV2AgentAdmission {
  Immediate(ExperimentalV2AgentAdapterStep)
  Invoke(
    state~ : ExperimentalV2AgentAdapterState,
    invocation~ : ExperimentalV2AgentInvocation
  )
}

///|
/// Fail-fast adapter failures: an invalid composition boundary or a
/// completion that no longer belongs to the owner-held reservation.
pub(all) suberror ExperimentalV2AgentAdapterError {
  EndpointMismatch(reason~ : String)
  UnexpectedMessage(kind~ : String)
  LateCompletion(request_id~ : @jsonrpc.RequestId)
  CompletionMismatch(method_name~ : String)
} derive(Eq, Debug)

///|
/// Failures raised while decoding one inbound v2 Agent message into the
/// typed request/notification set.
pub(all) suberror ExperimentalV2AgentMessageError {
  UnknownMethod(method_name~ : String)
  InvalidParams(method_name~ : String, cause~ : ExperimentalV2DecodeError)
} derive(Eq, Debug)

///|
fn experimental_v2_agent_response_id(
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
fn experimental_v2_agent_detailed_error(
  code~ : @jsonrpc.JsonRpcErrorCode,
  message~ : String,
) -> @jsonrpc.JsonRpcError {
  @jsonrpc.JsonRpcError::new(code~, message~, data=Json::string(message))
}

///|
fn experimental_v2_agent_response(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  error : @jsonrpc.JsonRpcError,
) -> ExperimentalV2AgentAdapterStep {
  {
    state,
    outputs: [
      Response(
        @jsonrpc.JsonRpcResponse::error(
          id=experimental_v2_agent_response_id(id),
          error~,
        ),
      ),
    ],
  }
}

///|
fn experimental_v2_agent_success(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  result : Json,
) -> ExperimentalV2AgentAdapterStep {
  {
    state,
    outputs: [Response(@jsonrpc.JsonRpcResponse::success(id~, result~))],
  }
}

///|
fn experimental_v2_agent_trace(
  state : ExperimentalV2AgentAdapterState,
  method_name : String,
  error : @jsonrpc.JsonRpcError,
) -> ExperimentalV2AgentAdapterStep {
  { state, outputs: [Command(TraceError(method_name~, error~))] }
}

///|
fn experimental_v2_agent_validate_endpoint(
  state : ExperimentalV2AgentAdapterState,
  endpoint : ExperimentalV2AgentEndpoint,
) -> Unit raise ExperimentalV2AgentAdapterError {
  let expected = endpoint.config()
  if state.protocol.config.info != expected.info {
    raise EndpointMismatch(reason="state agent info does not match endpoint")
  }
  if state.protocol.config.capabilities != expected.capabilities {
    raise EndpointMismatch(reason="state capabilities do not match endpoint")
  }
  if state.protocol.config.auth_methods != expected.auth_methods {
    raise EndpointMismatch(reason="state auth methods do not match endpoint")
  }
}

///|
fn experimental_v2_agent_decode_error_message(
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
fn experimental_v2_agent_message_error(
  error : ExperimentalV2AgentMessageError,
) -> @jsonrpc.JsonRpcError {
  match error {
    InvalidParams(method_name~, cause~) =>
      experimental_v2_agent_detailed_error(
        code=InvalidParams,
        message=method_name +
          ": " +
          experimental_v2_agent_decode_error_message(cause),
      )
    UnknownMethod(method_name~) =>
      experimental_v2_agent_detailed_error(
        code=MethodNotFound,
        message="unknown method: " + method_name,
      )
  }
}

///|
/// Typed protocol failures map onto JSON-RPC codes once, here.  Auth-state
/// violations that require a login settle on `AuthRequired`; capability gates
/// settle on `ResourceNotFound`; negotiation and phase failures are
/// `InvalidRequest`; unknown inbound names are `MethodNotFound`.
fn experimental_v2_agent_protocol_error(
  error : ExperimentalV2AgentProtocolError,
) -> @jsonrpc.JsonRpcError {
  match error {
    NotInitialized(method_name~) =>
      experimental_v2_agent_detailed_error(
        code=InvalidRequest,
        message="initialize required before " + method_name,
      )
    AlreadyInitialized =>
      experimental_v2_agent_detailed_error(
        code=InvalidRequest,
        message="agent is already initialized",
      )
    AuthNotAdvertised(method_name~) =>
      experimental_v2_agent_detailed_error(
        code=InvalidRequest,
        message="authentication is not advertised: " + method_name,
      )
    AuthMethodNotAdvertised(method_id~) =>
      experimental_v2_agent_detailed_error(
        code=AuthRequired,
        message="authentication method is not advertised: " + method_id,
      )
    AlreadyLoggedIn =>
      experimental_v2_agent_detailed_error(
        code=InvalidRequest,
        message="agent is already logged in",
      )
    NotLoggedIn =>
      experimental_v2_agent_detailed_error(
        code=AuthRequired,
        message="agent is not logged in",
      )
    CapabilityDenied(method_name~, capability~) =>
      experimental_v2_agent_detailed_error(
        code=ResourceNotFound,
        message="capability '" +
          capability +
          "' required by " +
          method_name +
          " is not enabled",
      )
    UnknownMethod(method_name~) =>
      experimental_v2_agent_detailed_error(
        code=MethodNotFound,
        message="unknown method: " + method_name,
      )
  }
}

///|
fn experimental_v2_agent_handler_wire_error(
  error : ExperimentalV2AgentHandlerError,
) -> @jsonrpc.JsonRpcError {
  match error {
    Application(message~) =>
      experimental_v2_agent_detailed_error(code=InternalError, message~)
    InvalidParams(message~) =>
      experimental_v2_agent_detailed_error(code=InvalidParams, message~)
    Cancelled => @jsonrpc.JsonRpcError::request_cancelled()
    UnavailableOperation(method_name~) =>
      experimental_v2_agent_detailed_error(
        code=ResourceNotFound,
        message="agent does not implement operation: " + method_name,
      )
  }
}

///|
fn experimental_v2_agent_request_params(params : Json?) -> Json {
  match params {
    Some(value) => value
    None => Json::object(Map([]))
  }
}

///|
fn[T] experimental_v2_agent_decode_with(
  method_name : String,
  value : Json,
  decode : (Json) -> T raise ExperimentalV2DecodeError,
) -> T raise ExperimentalV2AgentMessageError {
  decode(value) catch {
    cause => raise InvalidParams(method_name~, cause~)
  }
}

///|
fn experimental_v2_agent_decode_cancel_request(
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
/// Decode one inbound method name and params into the typed v2 Agent request
/// set.  Names outside the manifest (including v1-only and agent-to-client
/// names) are typed `UnknownMethod`, never guessed.
fn experimental_v2_agent_decode_request(
  method_name : String,
  params : Json?,
) -> ExperimentalV2AgentRequest raise ExperimentalV2AgentMessageError {
  let value = experimental_v2_agent_request_params(params)
  match method_name {
    "initialize" =>
      Initialize(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_initialize_params(value)
        }),
      )
    "auth/login" =>
      AuthLogin(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_login_params(value)
        }),
      )
    "auth/logout" =>
      AuthLogout(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_logout_params(value)
        }),
      )
    "session/new" =>
      SessionNew(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_new_session_params(value)
        }),
      )
    "session/prompt" =>
      SessionPrompt(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_prompt_params(value)
        }),
      )
    "session/list" =>
      SessionList(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_list_sessions_params(value)
        }),
      )
    "session/delete" =>
      SessionDelete(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_delete_session_params(value)
        }),
      )
    "session/resume" =>
      SessionResume(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_resume_session_params(value)
        }),
      )
    "session/close" =>
      SessionClose(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_close_session_params(value)
        }),
      )
    "session/set_config_option" =>
      SessionSetConfigOption(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_set_config_option(value)
        }),
      )
    _ => raise UnknownMethod(method_name~)
  }
}

///|
fn experimental_v2_agent_decode_notification(
  method_name : String,
  params : Json?,
) -> ExperimentalV2AgentNotification raise ExperimentalV2AgentMessageError {
  let value = experimental_v2_agent_request_params(params)
  match method_name {
    "session/cancel" =>
      SessionCancel(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_decode_cancel_session_params(value)
        }),
      )
    "$/cancel_request" =>
      CancelRequest(
        experimental_v2_agent_decode_with(method_name, value, value => {
          experimental_v2_agent_decode_cancel_request(value)
        }),
      )
    _ => raise UnknownMethod(method_name~)
  }
}

///|
fn experimental_v2_agent_adapter_reduce_request(
  state : ExperimentalV2AgentAdapterState,
  request : ExperimentalV2AgentRequest,
) -> Result[ExperimentalV2AgentStep, @jsonrpc.JsonRpcError] {
  try
    experimental_v2_agent_reduce(state.protocol, ClientRequest(request))
  catch {
    error => Err(experimental_v2_agent_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn experimental_v2_agent_adapter_reduce_notification(
  state : ExperimentalV2AgentAdapterState,
  notification : ExperimentalV2AgentNotification,
) -> Result[ExperimentalV2AgentStep, @jsonrpc.JsonRpcError] {
  try
    experimental_v2_agent_reduce(
      state.protocol,
      ClientNotification(notification),
    )
  catch {
    error => Err(experimental_v2_agent_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn experimental_v2_agent_adapter_reduce_event(
  state : ExperimentalV2AgentAdapterState,
  event : ExperimentalV2AgentEvent,
) -> Result[ExperimentalV2AgentStep, @jsonrpc.JsonRpcError] {
  try experimental_v2_agent_reduce(state.protocol, event) catch {
    error => Err(experimental_v2_agent_protocol_error(error))
  } noraise {
    step => Ok(step)
  }
}

///|
fn experimental_v2_agent_busy(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
) -> ExperimentalV2AgentAdmission {
  Immediate(
    experimental_v2_agent_response(
      state,
      id,
      experimental_v2_agent_detailed_error(
        code=InvalidRequest,
        message="agent is busy handling another state-changing request",
      ),
    ),
  )
}

///|
fn experimental_v2_agent_reservation_busy(
  state : ExperimentalV2AgentAdapterState,
) -> Bool {
  match state.reservation {
    Idle => false
    LoginPending(_) | LogoutPending(_) => true
  }
}

///|
fn experimental_v2_agent_release_reservation(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
) -> ExperimentalV2AgentAdapterState raise ExperimentalV2AgentAdapterError {
  match state.reservation {
    LoginPending(reserved) if reserved == id => { ..state, reservation: Idle }
    LogoutPending(reserved) if reserved == id => { ..state, reservation: Idle }
    _ => raise LateCompletion(request_id=id)
  }
}

///|
/// `initialize` is immediate on both negotiation outcomes.  A version-2 offer
/// enters `AgentInitialized`; any other offer is answered with this
/// endpoint's own version 2 and the state is left untouched — v2 never
/// downgrades, so a peer that cannot use 2 must reconnect elsewhere.
fn experimental_v2_agent_admit_initialize(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  params : ExperimentalV2InitializeParams,
) -> ExperimentalV2AgentAdmission {
  match
    experimental_v2_agent_adapter_reduce_request(state, Initialize(params)) {
    Err(error) => Immediate(experimental_v2_agent_response(state, id, error))
    Ok(step) => {
      let next_state : ExperimentalV2AgentAdapterState = {
        ..state,
        protocol: step.state,
      }
      let result = experimental_v2_agent_initialize_result(
        state.protocol.config,
      )
      let encoded : Result[Json, ExperimentalV2DecodeError] = try
        experimental_v2_encode_initialize_result(result)
      catch {
        error => Err(error)
      } noraise {
        json => Ok(json)
      }
      match encoded {
        Err(cause) =>
          Immediate(
            experimental_v2_agent_response(
              next_state,
              id,
              experimental_v2_agent_detailed_error(
                code=InternalError,
                message="failed to encode initialize result: " +
                  experimental_v2_agent_decode_error_message(cause),
              ),
            ),
          )
        Ok(json) =>
          Immediate(experimental_v2_agent_success(next_state, id, json))
      }
    }
  }
}

///|
fn experimental_v2_agent_admit_login(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  params : ExperimentalV2LoginParams,
) -> ExperimentalV2AgentAdmission {
  if experimental_v2_agent_reservation_busy(state) {
    return experimental_v2_agent_busy(state, id)
  }
  match experimental_v2_agent_adapter_reduce_request(state, AuthLogin(params)) {
    Err(error) => Immediate(experimental_v2_agent_response(state, id, error))
    Ok(step) =>
      Invoke(
        state={ protocol: step.state, reservation: LoginPending(id) },
        invocation=AuthLoginInvocation(id~, params~),
      )
  }
}

///|
fn experimental_v2_agent_admit_logout(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  params : ExperimentalV2LogoutParams,
) -> ExperimentalV2AgentAdmission {
  if experimental_v2_agent_reservation_busy(state) {
    return experimental_v2_agent_busy(state, id)
  }
  match
    experimental_v2_agent_adapter_reduce_request(state, AuthLogout(params)) {
    Err(error) => Immediate(experimental_v2_agent_response(state, id, error))
    Ok(step) =>
      Invoke(
        state={ protocol: step.state, reservation: LogoutPending(id) },
        invocation=AuthLogoutInvocation(id~, params~),
      )
  }
}

///|
/// Session requests run concurrently with a pending login (v2 does not gate
/// sessions on authentication) but never over a pending logout, whose
/// handler is already tearing the authenticated surface down.
fn experimental_v2_agent_admit_session_request(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  request : ExperimentalV2AgentRequest,
  invocation : ExperimentalV2AgentInvocation,
) -> ExperimentalV2AgentAdmission {
  match state.reservation {
    LogoutPending(_) => return experimental_v2_agent_busy(state, id)
    LoginPending(_) | Idle => ()
  }
  match experimental_v2_agent_adapter_reduce_request(state, request) {
    Err(error) => Immediate(experimental_v2_agent_response(state, id, error))
    Ok(step) => Invoke(state={ ..state, protocol: step.state }, invocation~)
  }
}

///|
fn experimental_v2_agent_admit_request(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  request : ExperimentalV2AgentRequest,
) -> ExperimentalV2AgentAdmission {
  match request {
    Initialize(params) =>
      experimental_v2_agent_admit_initialize(state, id, params)
    AuthLogin(params) => experimental_v2_agent_admit_login(state, id, params)
    AuthLogout(params) => experimental_v2_agent_admit_logout(state, id, params)
    SessionNew(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionNewInvocation(id~, params~),
      )
    SessionList(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionListInvocation(id~, params~),
      )
    SessionResume(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionResumeInvocation(id~, params~),
      )
    SessionClose(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionCloseInvocation(id~, params~),
      )
    SessionPrompt(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionPromptInvocation(id~, params~),
      )
    SessionSetConfigOption(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionSetConfigOptionInvocation(id~, params~),
      )
    SessionDelete(params) =>
      experimental_v2_agent_admit_session_request(
        state,
        id,
        request,
        SessionDeleteInvocation(id~, params~),
      )
  }
}

///|
/// `session/cancel` is consumed at the protocol layer: the reducer validates
/// the phase, and the session-scoped work cancellation it commands is the
/// application's own state, not an owner-loop invocation.  The step carries
/// no outputs.
fn experimental_v2_agent_admit_cancel_session(
  state : ExperimentalV2AgentAdapterState,
  notification : ExperimentalV2AgentNotification,
) -> ExperimentalV2AgentAdmission {
  match experimental_v2_agent_adapter_reduce_notification(state, notification) {
    Err(error) =>
      Immediate(experimental_v2_agent_trace(state, "session/cancel", error))
    Ok(step) =>
      Immediate({ state: { ..state, protocol: step.state }, outputs: [] })
  }
}

///|
fn experimental_v2_agent_admit_cancel_request(
  state : ExperimentalV2AgentAdapterState,
  notification : ExperimentalV2AgentNotification,
  request_id : ExperimentalV2RequestId,
) -> ExperimentalV2AgentAdmission {
  match experimental_v2_agent_adapter_reduce_notification(state, notification) {
    Err(error) =>
      Immediate(experimental_v2_agent_trace(state, "$/cancel_request", error))
    Ok(step) =>
      Immediate({
        state: { ..state, protocol: step.state },
        outputs: [Command(CancelRequest(request_id~))],
      })
  }
}

///|
/// Decode and admit one message.  Synchronous and pure from the owner loop's
/// perspective; it never calls an application handler.
pub fn experimental_v2_agent_adapter_admit(
  state : ExperimentalV2AgentAdapterState,
  endpoint : ExperimentalV2AgentEndpoint,
  message : @jsonrpc.JsonRpcMessage,
) -> ExperimentalV2AgentAdmission raise ExperimentalV2AgentAdapterError {
  experimental_v2_agent_validate_endpoint(state, endpoint)
  match message {
    Request(request) => {
      let id = request.id
      let decoded = try
        experimental_v2_agent_decode_request(
          request.method_name,
          request.params,
        )
      catch {
        error => Err(experimental_v2_agent_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) =>
          Immediate(experimental_v2_agent_response(state, id, error))
        Ok(request) => experimental_v2_agent_admit_request(state, id, request)
      }
    }
    Notification(notification) => {
      let decoded = try
        experimental_v2_agent_decode_notification(
          notification.method_name,
          notification.params,
        )
      catch {
        error => Err(experimental_v2_agent_message_error(error))
      } noraise {
        value => Ok(value)
      }
      match decoded {
        Err(error) =>
          Immediate(
            experimental_v2_agent_trace(state, notification.method_name, error),
          )
        Ok(typed) =>
          match typed {
            SessionCancel(_) =>
              experimental_v2_agent_admit_cancel_session(state, typed)
            CancelRequest(request_id) =>
              experimental_v2_agent_admit_cancel_request(
                state, typed, request_id,
              )
          }
      }
    }
    Response(_) => raise UnexpectedMessage(kind="response")
  }
}

///|
fn[T] experimental_v2_agent_complete_result(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  result : Result[T, ExperimentalV2AgentHandlerError],
  encode : (T) -> Json raise ExperimentalV2DecodeError,
) -> ExperimentalV2AgentAdapterStep {
  match result {
    Err(error) =>
      experimental_v2_agent_response(
        state,
        id,
        experimental_v2_agent_handler_wire_error(error),
      )
    Ok(value) => {
      let encoded : Result[Json, @jsonrpc.JsonRpcError] = try
        encode(value)
      catch {
        cause =>
          Err(
            experimental_v2_agent_detailed_error(
              code=InternalError,
              message="failed to encode response: " +
                experimental_v2_agent_decode_error_message(cause),
            ),
          )
      } noraise {
        json => Ok(json)
      }
      match encoded {
        Ok(json) => experimental_v2_agent_success(state, id, json)
        Err(error) => experimental_v2_agent_response(state, id, error)
      }
    }
  }
}

///|
/// A successful login commits `LoginSucceeded` through the reducer after the
/// reservation is released; a failed handler leaves the protocol untouched in
/// `AuthPending`.
fn experimental_v2_agent_complete_login(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  params : ExperimentalV2LoginParams,
  result : Result[ExperimentalV2LoginResult, ExperimentalV2AgentHandlerError],
) -> ExperimentalV2AgentAdapterStep raise ExperimentalV2AgentAdapterError {
  let released = experimental_v2_agent_release_reservation(state, id)
  match result {
    Err(error) =>
      experimental_v2_agent_response(
        released,
        id,
        experimental_v2_agent_handler_wire_error(error),
      )
    Ok(value) => {
      let reduced = experimental_v2_agent_adapter_reduce_event(
        released,
        LoginSucceeded(method_id=params.method_id),
      )
      match reduced {
        Err(error) => experimental_v2_agent_response(released, id, error)
        Ok(step) =>
          experimental_v2_agent_complete_result(
            { ..released, protocol: step.state },
            id,
            Ok(value),
            experimental_v2_encode_login_result,
          )
      }
    }
  }
}

///|
/// A successful logout commits `LoggedOut` through the reducer after the
/// reservation is released; a failed handler stays `AuthLoggedIn`.
fn experimental_v2_agent_complete_logout(
  state : ExperimentalV2AgentAdapterState,
  id : @jsonrpc.RequestId,
  result : Result[ExperimentalV2LogoutResult, ExperimentalV2AgentHandlerError],
) -> ExperimentalV2AgentAdapterStep raise ExperimentalV2AgentAdapterError {
  let released = experimental_v2_agent_release_reservation(state, id)
  match result {
    Err(error) =>
      experimental_v2_agent_response(
        released,
        id,
        experimental_v2_agent_handler_wire_error(error),
      )
    Ok(value) => {
      let reduced = experimental_v2_agent_adapter_reduce_event(
        released,
        LoggedOut,
      )
      match reduced {
        Err(error) => experimental_v2_agent_response(released, id, error)
        Ok(step) =>
          experimental_v2_agent_complete_result(
            { ..released, protocol: step.state },
            id,
            Ok(value),
            experimental_v2_encode_logout_result,
          )
      }
    }
  }
}

///|
/// Complete one admitted invocation in the owner loop.  A state-changing
/// completion must match its immutable reservation; duplicate/late auth
/// completions and constructor mismatches fail explicitly instead of
/// producing a second response.
pub fn experimental_v2_agent_adapter_complete(
  state : ExperimentalV2AgentAdapterState,
  invocation : ExperimentalV2AgentInvocation,
  completion : ExperimentalV2AgentCompletion,
) -> ExperimentalV2AgentAdapterStep raise ExperimentalV2AgentAdapterError {
  match invocation {
    AuthLoginInvocation(id~, params~) =>
      match completion {
        AuthLoginCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_login(state, id, params, result)
        AuthLoginCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="auth/login")
      }
    AuthLogoutInvocation(id~, params=_) =>
      match completion {
        AuthLogoutCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_logout(state, id, result)
        AuthLogoutCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="auth/logout")
      }
    SessionNewInvocation(id~, params=_) =>
      match completion {
        SessionNewCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_new_session_result,
          )
        SessionNewCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/new")
      }
    SessionListInvocation(id~, params=_) =>
      match completion {
        SessionListCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_list_sessions_result,
          )
        SessionListCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/list")
      }
    SessionResumeInvocation(id~, params=_) =>
      match completion {
        SessionResumeCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_resume_session_result,
          )
        SessionResumeCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/resume")
      }
    SessionCloseInvocation(id~, params=_) =>
      match completion {
        SessionCloseCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_close_session_result,
          )
        SessionCloseCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/close")
      }
    SessionPromptInvocation(id~, params=_) =>
      match completion {
        SessionPromptCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_prompt_result,
          )
        SessionPromptCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/prompt")
      }
    SessionSetConfigOptionInvocation(id~, params=_) =>
      match completion {
        SessionSetConfigOptionCompleted(id=completion_id, result~) if completion_id ==
          id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_set_config_option_result,
          )
        SessionSetConfigOptionCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/set_config_option")
      }
    SessionDeleteInvocation(id~, params=_) =>
      match completion {
        SessionDeleteCompleted(id=completion_id, result~) if completion_id == id =>
          experimental_v2_agent_complete_result(
            state, id, result, experimental_v2_encode_delete_session_result,
          )
        SessionDeleteCompleted(id=completion_id, result=_) =>
          raise LateCompletion(request_id=completion_id)
        _ => raise CompletionMismatch(method_name="session/delete")
      }
  }
}
