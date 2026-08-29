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
  SessionForkInvocation(id~ : RequestId, params~ : ForkSessionParams)
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
  SessionForkCompleted(
    id~ : RequestId,
    result~ : Result[ForkSessionResult, HandlerError]
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
    SessionForkInvocation(id~, params~) =>
      SessionForkCompleted(
        id~,
        result=agent_adapter_call(async fn() {
          endpoint.fork_session(context, params)
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

///|
/// The stable wire method name of one typed invocation.  Runtime bridges use
/// it for trace intents only; it never replaces the typed completion.
pub fn agent_adapter_invocation_method_name(
  invocation : AgentAdapterInvocation,
) -> String {
  match invocation {
    AuthenticateInvocation(id=_, params=_) => "authenticate"
    LogoutInvocation(id=_, params=_) => "logout"
    SessionNewInvocation(id=_, params=_) => "session/new"
    SessionLoadInvocation(id=_, params=_) => "session/load"
    SessionResumeInvocation(id=_, params=_) => "session/resume"
    SessionForkInvocation(id=_, params=_) => "session/fork"
    SessionListInvocation(id=_, params=_) => "session/list"
    SessionDeleteInvocation(id=_, params=_) => "session/delete"
    SessionCloseInvocation(id=_, params=_) => "session/close"
    SessionSetModeInvocation(id=_, params=_) => "session/set_mode"
    SessionSetConfigOptionInvocation(id=_, params=_) =>
      "session/set_config_option"
    SessionPromptInvocation(id=_, params=_) => "session/prompt"
    SessionCancelInvocation(params=_) => "session/cancel"
  }
}

///|
/// Synthesize the redacted typed failure completion for one invocation,
/// following the `agent_adapter_call` convention for unknown failures.  The
/// owner task boundary uses this when async execution itself fails before a
/// typed completion exists.
pub fn agent_adapter_failure_completion(
  invocation : AgentAdapterInvocation,
) -> AgentAdapterCompletion {
  match invocation {
    AuthenticateInvocation(id~, params=_) =>
      AuthenticateCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    LogoutInvocation(id~, params=_) =>
      LogoutCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionNewInvocation(id~, params=_) =>
      SessionNewCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionLoadInvocation(id~, params=_) =>
      SessionLoadCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionResumeInvocation(id~, params=_) =>
      SessionResumeCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionForkInvocation(id~, params=_) =>
      SessionForkCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionListInvocation(id~, params=_) =>
      SessionListCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionDeleteInvocation(id~, params=_) =>
      SessionDeleteCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionCloseInvocation(id~, params=_) =>
      SessionCloseCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionSetModeInvocation(id~, params=_) =>
      SessionSetModeCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionSetConfigOptionInvocation(id~, params=_) =>
      SessionSetConfigOptionCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionPromptInvocation(id~, params=_) =>
      SessionPromptCompleted(
        id~,
        result=Err(Application(message="agent handler failed")),
      )
    SessionCancelInvocation(params=_) =>
      SessionCancelCompleted(
        result=Err(Application(message="agent handler failed")),
      )
  }
}

///|
/// Synthesize the typed cancellation completion for one invocation.  The
/// owner loop uses this when it grants an inbound cancellation so the
/// reservation and wire id settle through the normal completion path.
pub fn agent_adapter_cancel_completion(
  invocation : AgentAdapterInvocation,
) -> AgentAdapterCompletion {
  match invocation {
    AuthenticateInvocation(id~, params=_) =>
      AuthenticateCompleted(id~, result=Err(Cancelled))
    LogoutInvocation(id~, params=_) =>
      LogoutCompleted(id~, result=Err(Cancelled))
    SessionNewInvocation(id~, params=_) =>
      SessionNewCompleted(id~, result=Err(Cancelled))
    SessionLoadInvocation(id~, params=_) =>
      SessionLoadCompleted(id~, result=Err(Cancelled))
    SessionResumeInvocation(id~, params=_) =>
      SessionResumeCompleted(id~, result=Err(Cancelled))
    SessionForkInvocation(id~, params=_) =>
      SessionForkCompleted(id~, result=Err(Cancelled))
    SessionListInvocation(id~, params=_) =>
      SessionListCompleted(id~, result=Err(Cancelled))
    SessionDeleteInvocation(id~, params=_) =>
      SessionDeleteCompleted(id~, result=Err(Cancelled))
    SessionCloseInvocation(id~, params=_) =>
      SessionCloseCompleted(id~, result=Err(Cancelled))
    SessionSetModeInvocation(id~, params=_) =>
      SessionSetModeCompleted(id~, result=Err(Cancelled))
    SessionSetConfigOptionInvocation(id~, params=_) =>
      SessionSetConfigOptionCompleted(id~, result=Err(Cancelled))
    SessionPromptInvocation(id~, params=_) =>
      SessionPromptCompleted(id~, result=Err(Cancelled))
    SessionCancelInvocation(params=_) =>
      SessionCancelCompleted(result=Err(Cancelled))
  }
}
