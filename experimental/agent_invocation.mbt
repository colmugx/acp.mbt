///|
/// One typed v2 Agent operation admitted by the adapter.  It carries only
/// immutable protocol values; connection state stays with the owner that
/// admitted it.  Envelope correlation reuses `@jsonrpc.RequestId` because the
/// invocation crosses the shared JSON-RPC engine boundary.
pub(all) enum ExperimentalV2AgentInvocation {
  AuthLoginInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2LoginParams
  )
  AuthLogoutInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2LogoutParams
  )
  SessionNewInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2NewSessionParams
  )
  SessionListInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2ListSessionsParams
  )
  SessionResumeInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2ResumeSessionParams
  )
  SessionCloseInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2CloseSessionParams
  )
  SessionPromptInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2PromptParams
  )
  SessionSetConfigOptionInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2SetConfigOptionParams
  )
  SessionDeleteInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2DeleteSessionParams
  )
  SessionForkInvocation(
    id~ : @jsonrpc.RequestId,
    params~ : ExperimentalV2ForkSessionParams
  )
} derive(Eq, Debug)

///|
/// The typed result of one executed invocation.  No wire response is produced
/// here; the owner loop serializes this completion through
/// `experimental_v2_agent_adapter_complete`.
pub(all) enum ExperimentalV2AgentCompletion {
  AuthLoginCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[ExperimentalV2LoginResult, ExperimentalV2AgentHandlerError]
  )
  AuthLogoutCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2LogoutResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionNewCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2NewSessionResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionListCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2ListSessionsResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionResumeCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2ResumeSessionResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionCloseCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2CloseSessionResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionPromptCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2PromptResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionSetConfigOptionCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2SetConfigOptionResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionDeleteCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2DeleteSessionResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
  SessionForkCompleted(
    id~ : @jsonrpc.RequestId,
    result~ : Result[
      ExperimentalV2ForkSessionResult,
      ExperimentalV2AgentHandlerError,
    ]
  )
} derive(Eq, Debug)

///|
/// Convert one executed handler's outcome into the typed completion result
/// without re-normalizing: the endpoint seam has already prefixed typed
/// failures with their method name, so they pass through unchanged and only
/// a foreign exception gets the generic application message.
async fn[T] experimental_v2_agent_execute_call(
  handler : async () -> T,
) -> Result[T, ExperimentalV2AgentHandlerError] noraise {
  try handler() catch {
    error =>
      if @async.is_cancellation_error(error) {
        Err(Cancelled)
      } else {
        match error {
          ExperimentalV2AgentHandlerError::Application(message~) =>
            Err(Application(message~))
          ExperimentalV2AgentHandlerError::InvalidParams(message~) =>
            Err(InvalidParams(message~))
          ExperimentalV2AgentHandlerError::Cancelled => Err(Cancelled)
          ExperimentalV2AgentHandlerError::UnavailableOperation(method_name~) =>
            Err(UnavailableOperation(method_name~))
          _ =>
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
/// Execute one already-admitted typed operation against the endpoint and its
/// outbound context.  This function owns no protocol state and cannot emit
/// stdout; it returns exactly one typed completion for the owner loop, with
/// service failures normalized to the v2 handler error.
pub async fn experimental_v2_agent_execute(
  invocation : ExperimentalV2AgentInvocation,
  endpoint : ExperimentalV2AgentEndpoint,
  context : ExperimentalV2AgentContext,
) -> ExperimentalV2AgentCompletion noraise {
  match invocation {
    AuthLoginInvocation(id~, params~) =>
      AuthLoginCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.auth_login(context, params)
        }),
      )
    AuthLogoutInvocation(id~, params~) =>
      AuthLogoutCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.auth_logout(context, params)
        }),
      )
    SessionNewInvocation(id~, params~) =>
      SessionNewCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.new_session(context, params)
        }),
      )
    SessionListInvocation(id~, params~) =>
      SessionListCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.list_sessions(context, params)
        }),
      )
    SessionResumeInvocation(id~, params~) =>
      SessionResumeCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.resume_session(context, params)
        }),
      )
    SessionCloseInvocation(id~, params~) =>
      SessionCloseCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.close_session(context, params)
        }),
      )
    SessionPromptInvocation(id~, params~) =>
      SessionPromptCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.prompt(context, params)
        }),
      )
    SessionSetConfigOptionInvocation(id~, params~) =>
      SessionSetConfigOptionCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.set_config_option(context, params)
        }),
      )
    SessionDeleteInvocation(id~, params~) =>
      SessionDeleteCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.delete_session(context, params)
        }),
      )
    SessionForkInvocation(id~, params~) =>
      SessionForkCompleted(
        id~,
        result=experimental_v2_agent_execute_call(async fn() {
          endpoint.fork_session(context, params)
        }),
      )
  }
}

///|
/// The stable wire method name of one typed invocation.  Runtime bridges use
/// it for trace intents only; it never replaces the typed completion.
pub fn experimental_v2_agent_invocation_method_name(
  invocation : ExperimentalV2AgentInvocation,
) -> String {
  match invocation {
    AuthLoginInvocation(id=_, params=_) => "auth/login"
    AuthLogoutInvocation(id=_, params=_) => "auth/logout"
    SessionNewInvocation(id=_, params=_) => "session/new"
    SessionListInvocation(id=_, params=_) => "session/list"
    SessionResumeInvocation(id=_, params=_) => "session/resume"
    SessionCloseInvocation(id=_, params=_) => "session/close"
    SessionPromptInvocation(id=_, params=_) => "session/prompt"
    SessionSetConfigOptionInvocation(id=_, params=_) =>
      "session/set_config_option"
    SessionDeleteInvocation(id=_, params=_) => "session/delete"
    SessionForkInvocation(id=_, params=_) => "session/fork"
  }
}

///|
fn experimental_v2_agent_failed_completion(
  invocation : ExperimentalV2AgentInvocation,
  error~ : ExperimentalV2AgentHandlerError,
) -> ExperimentalV2AgentCompletion {
  match invocation {
    AuthLoginInvocation(id~, params=_) =>
      AuthLoginCompleted(id~, result=Err(error))
    AuthLogoutInvocation(id~, params=_) =>
      AuthLogoutCompleted(id~, result=Err(error))
    SessionNewInvocation(id~, params=_) =>
      SessionNewCompleted(id~, result=Err(error))
    SessionListInvocation(id~, params=_) =>
      SessionListCompleted(id~, result=Err(error))
    SessionResumeInvocation(id~, params=_) =>
      SessionResumeCompleted(id~, result=Err(error))
    SessionCloseInvocation(id~, params=_) =>
      SessionCloseCompleted(id~, result=Err(error))
    SessionPromptInvocation(id~, params=_) =>
      SessionPromptCompleted(id~, result=Err(error))
    SessionSetConfigOptionInvocation(id~, params=_) =>
      SessionSetConfigOptionCompleted(id~, result=Err(error))
    SessionDeleteInvocation(id~, params=_) =>
      SessionDeleteCompleted(id~, result=Err(error))
    SessionForkInvocation(id~, params=_) =>
      SessionForkCompleted(id~, result=Err(error))
  }
}

///|
/// Synthesize the redacted typed failure completion for one invocation.  The
/// owner task boundary uses this when async execution itself fails before a
/// typed completion exists.
pub fn experimental_v2_agent_failure_completion(
  invocation : ExperimentalV2AgentInvocation,
) -> ExperimentalV2AgentCompletion {
  experimental_v2_agent_failed_completion(
    invocation,
    error=Application(message="agent handler failed"),
  )
}

///|
/// Synthesize the typed cancellation completion for one invocation.  The
/// owner loop uses this when it grants an inbound cancellation so the
/// reservation and wire id settle through the normal completion path.
pub fn experimental_v2_agent_cancel_completion(
  invocation : ExperimentalV2AgentInvocation,
) -> ExperimentalV2AgentCompletion {
  experimental_v2_agent_failed_completion(invocation, error=Cancelled)
}
