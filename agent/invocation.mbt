///|
/// A typed operation admitted by the Agent adapter.  The operation carries
/// only immutable protocol values; connection state is owned by the caller
/// that admitted it.
pub(all) enum AgentAdapterInvocation {
  AuthenticateInvocation(id~ : RequestId, params~ : AuthenticateParams)
  LogoutInvocation(id~ : RequestId, params~ : LogoutParams)
  SessionNewInvocation(id~ : RequestId, params~ : NewSessionParams)
  SessionLoadInvocation(id~ : RequestId, params~ : LoadSessionParams)
  SessionResumeInvocation(id~ : RequestId, params~ : ResumeSessionParams)
  SessionListInvocation(id~ : RequestId, params~ : ListSessionsParams)
  SessionDeleteInvocation(id~ : RequestId, params~ : DeleteSessionParams)
  SessionCloseInvocation(id~ : RequestId, params~ : CloseSessionParams)
  SessionSetModeInvocation(id~ : RequestId, params~ : SetSessionModeParams)
  SessionSetConfigOptionInvocation(
    id~ : RequestId,
    params~ : SetSessionConfigOptionParams
  )
  SessionPromptInvocation(id~ : RequestId, params~ : PromptParams)
  SessionCancelInvocation(params~ : CancelParams)
} derive(Eq, Debug)

///|
/// The result of one typed handler invocation.  No wire response is produced
/// here: the owner loop serializes this completion through
/// `agent_adapter_complete`.
pub(all) enum AgentAdapterCompletion {
  AuthenticateCompleted(
    id~ : RequestId,
    result~ : Result[AuthenticateResult, HandlerError]
  )
  LogoutCompleted(id~ : RequestId, result~ : Result[LogoutResult, HandlerError])
  SessionNewCompleted(
    id~ : RequestId,
    result~ : Result[NewSessionResult, HandlerError]
  )
  SessionLoadCompleted(
    id~ : RequestId,
    result~ : Result[LoadSessionResult, HandlerError]
  )
  SessionResumeCompleted(
    id~ : RequestId,
    result~ : Result[ResumeSessionResult, HandlerError]
  )
  SessionListCompleted(
    id~ : RequestId,
    result~ : Result[ListSessionsResult, HandlerError]
  )
  SessionDeleteCompleted(
    id~ : RequestId,
    result~ : Result[DeleteSessionResult, HandlerError]
  )
  SessionCloseCompleted(
    id~ : RequestId,
    result~ : Result[CloseSessionResult, HandlerError]
  )
  SessionSetModeCompleted(
    id~ : RequestId,
    result~ : Result[SetSessionModeResult, HandlerError]
  )
  SessionSetConfigOptionCompleted(
    id~ : RequestId,
    result~ : Result[SetSessionConfigOptionResult, HandlerError]
  )
  SessionPromptCompleted(
    id~ : RequestId,
    result~ : Result[PromptResult, HandlerError]
  )
  SessionCancelCompleted(result~ : Result[Unit, HandlerError])
} derive(Eq, Debug)

///|
/// Execute one already-admitted typed operation.  This function has no
/// protocol state parameter and cannot emit stdout; it only returns a typed
/// completion for the owner loop.
pub async fn agent_adapter_execute(
  invocation : AgentAdapterInvocation,
  endpoint : AgentEndpoint,
  context : AgentContext,
) -> AgentAdapterCompletion noraise {
  match invocation {
    AuthenticateInvocation(id~, params~) =>
      AuthenticateCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.authenticate(context, params)
        }),
      )
    LogoutInvocation(id~, params~) =>
      LogoutCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.logout(context, params)
        }),
      )
    SessionNewInvocation(id~, params~) =>
      SessionNewCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.new_session(context, params)
        }),
      )
    SessionLoadInvocation(id~, params~) =>
      SessionLoadCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.load_session(context, params)
        }),
      )
    SessionResumeInvocation(id~, params~) =>
      SessionResumeCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.resume_session(context, params)
        }),
      )
    SessionListInvocation(id~, params~) =>
      SessionListCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.list_sessions(context, params)
        }),
      )
    SessionDeleteInvocation(id~, params~) =>
      SessionDeleteCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.delete_session(context, params)
        }),
      )
    SessionCloseInvocation(id~, params~) =>
      SessionCloseCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.close_session(context, params)
        }),
      )
    SessionSetModeInvocation(id~, params~) =>
      SessionSetModeCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.set_mode(context, params)
        }),
      )
    SessionSetConfigOptionInvocation(id~, params~) =>
      SessionSetConfigOptionCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.set_config_option(context, params)
        }),
      )
    SessionPromptInvocation(id~, params~) =>
      SessionPromptCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.prompt(context, params)
        }),
      )
    SessionCancelInvocation(params~) =>
      SessionCancelCompleted(
        result=agent_adapter_call(async fn() {
          endpoint.cancel(context, params)
        }),
      )
  }
}
