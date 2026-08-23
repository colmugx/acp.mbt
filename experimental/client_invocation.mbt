///|
/// One immutable typed Agent-to-Client operation admitted by the v2 Client
/// adapter.  The invocation carries protocol data only; connection state
/// remains with the owner loop that supplied the admission state.  Envelope
/// correlation reuses `@jsonrpc.RequestId` because the invocation crosses the
/// shared JSON-RPC engine boundary.
pub(all) enum ExperimentalV2ClientInvocation {
  RequestPermissionInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2RequestPermissionRequest
  )
  ElicitationCreateInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2ElicitationCreateRequest
  )
  SessionUpdateInvocation(params~ : ExperimentalV2UpdateSessionNotification)
  ElicitationCompleteInvocation(
    params~ : ExperimentalV2CompleteElicitationNotification
  )
} derive(Eq, Debug)

///|
/// The typed result of one executed invocation.  No wire response is produced
/// here; the owner loop serializes this completion through
/// `experimental_v2_client_adapter_complete`.
pub(all) enum ExperimentalV2ClientCompletion {
  RequestPermissionCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2RequestPermissionResponse,
      ExperimentalV2ClientHandlerError,
    ]
  )
  ElicitationCreateCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2ElicitationCreateResponse,
      ExperimentalV2ClientHandlerError,
    ]
  )
  SessionUpdateCompleted(
    result~ : Result[Unit, ExperimentalV2ClientHandlerError]
  )
  ElicitationCompleteCompleted(
    result~ : Result[Unit, ExperimentalV2ClientHandlerError]
  )
} derive(Eq, Debug)

///|
/// The stable wire method name of one typed invocation.  Runtime bridges use
/// it for trace intents only; it never replaces the typed completion.
pub fn experimental_v2_client_invocation_method_name(
  invocation : ExperimentalV2ClientInvocation,
) -> String {
  match invocation {
    RequestPermissionInvocation(id=_, params=_) => "session/request_permission"
    ElicitationCreateInvocation(id=_, params=_) => "elicitation/create"
    SessionUpdateInvocation(params=_) => "session/update"
    ElicitationCompleteInvocation(params=_) => "elicitation/complete"
  }
}

///|
/// Convert one executed handler's outcome into the typed completion result
/// without re-normalizing: the endpoint seam has already prefixed typed
/// failures with their method name, so they pass through unchanged and only a
/// foreign exception gets the generic application message.
async fn[T] experimental_v2_client_execute_call(
  handler : async () -> T,
) -> Result[T, ExperimentalV2ClientHandlerError] noraise {
  try handler() catch {
    error =>
      if @async.is_cancellation_error(error) {
        Err(Cancelled)
      } else {
        match error {
          ExperimentalV2ClientHandlerError::Application(message~) =>
            Err(Application(message~))
          ExperimentalV2ClientHandlerError::InvalidParams(message~) =>
            Err(InvalidParams(message~))
          ExperimentalV2ClientHandlerError::Cancelled => Err(Cancelled)
          ExperimentalV2ClientHandlerError::UnavailableOperation(method_name~) =>
            Err(UnavailableOperation(method_name~))
          _ =>
            Err(
              Application(message="client handler failed: " + error.to_string()),
            )
        }
      }
  } noraise {
    value => Ok(value)
  }
}

///|
/// Execute one already-admitted typed operation against the endpoint.  This
/// function owns no protocol state and cannot emit stdout; it returns exactly
/// one typed completion for the owner loop, with service failures normalized
/// to the v2 Client handler error.
pub async fn experimental_v2_client_execute(
  invocation : ExperimentalV2ClientInvocation,
  endpoint : ExperimentalV2ClientEndpoint,
) -> ExperimentalV2ClientCompletion noraise {
  match invocation {
    RequestPermissionInvocation(id~, params~) =>
      RequestPermissionCompleted(
        id~,
        result=experimental_v2_client_execute_call(async fn() {
          endpoint.request_permission(params)
        }),
      )
    ElicitationCreateInvocation(id~, params~) =>
      ElicitationCreateCompleted(
        id~,
        result=experimental_v2_client_execute_call(async fn() {
          endpoint.elicitation_create(params)
        }),
      )
    SessionUpdateInvocation(params~) =>
      SessionUpdateCompleted(
        result=experimental_v2_client_execute_call(async fn() {
          endpoint.session_update(params)
        }),
      )
    ElicitationCompleteInvocation(params~) =>
      ElicitationCompleteCompleted(
        result=experimental_v2_client_execute_call(async fn() {
          endpoint.elicitation_complete(params)
        }),
      )
  }
}

///|
fn experimental_v2_client_failed_completion(
  invocation : ExperimentalV2ClientInvocation,
  error~ : ExperimentalV2ClientHandlerError,
) -> ExperimentalV2ClientCompletion {
  match invocation {
    RequestPermissionInvocation(id~, params=_) =>
      RequestPermissionCompleted(id~, result=Err(error))
    ElicitationCreateInvocation(id~, params=_) =>
      ElicitationCreateCompleted(id~, result=Err(error))
    SessionUpdateInvocation(params=_) =>
      SessionUpdateCompleted(result=Err(error))
    ElicitationCompleteInvocation(params=_) =>
      ElicitationCompleteCompleted(result=Err(error))
  }
}

///|
/// Synthesize the redacted typed failure completion for one invocation.  The
/// owner task boundary uses this when async execution itself fails before a
/// typed completion exists.
pub fn experimental_v2_client_failure_completion(
  invocation : ExperimentalV2ClientInvocation,
) -> ExperimentalV2ClientCompletion {
  experimental_v2_client_failed_completion(
    invocation,
    error=Application(message="client handler failed"),
  )
}

///|
/// Synthesize the typed cancellation completion for one invocation.  The
/// owner loop uses this when it grants an inbound cancellation so the wire id
/// settles through the normal completion path.
pub fn experimental_v2_client_cancel_completion(
  invocation : ExperimentalV2ClientInvocation,
) -> ExperimentalV2ClientCompletion {
  experimental_v2_client_failed_completion(invocation, error=Cancelled)
}
