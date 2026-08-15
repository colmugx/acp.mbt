///|
/// One immutable typed operation admitted by the Client adapter.  The
/// invocation carries protocol data only; connection state remains with the
/// owner loop that supplied the admission state.
pub(all) enum ClientAdapterInvocation {
  RequestPermissionInvocation(
    id~ : RequestId,
    params~ : RequestPermissionRequest
  )
  FsReadTextFileInvocation(id~ : RequestId, params~ : ReadTextFileParams)
  FsWriteTextFileInvocation(id~ : RequestId, params~ : WriteTextFileParams)
  TerminalCreateInvocation(id~ : RequestId, params~ : TerminalCreateParams)
  TerminalOutputInvocation(id~ : RequestId, params~ : TerminalOutputParams)
  TerminalWaitForExitInvocation(
    id~ : RequestId,
    params~ : TerminalWaitForExitParams
  )
  TerminalKillInvocation(id~ : RequestId, params~ : TerminalKillParams)
  TerminalReleaseInvocation(id~ : RequestId, params~ : TerminalReleaseParams)
  ElicitationCreateInvocation(
    id~ : RequestId,
    params~ : ElicitationCreateParams
  )
  SessionUpdateInvocation(params~ : SessionUpdateParams)
  ElicitationCompleteInvocation(params~ : ElicitationCompleteParams)
} derive(Eq, Debug)

///|
/// Typed completion returned by the async handler phase.  No state update or
/// response is produced until the owner loop passes this value to
/// `client_adapter_complete`.
pub(all) enum ClientAdapterCompletion {
  RequestPermissionCompleted(
    id~ : RequestId,
    result~ : Result[RequestPermissionResponse, HandlerError]
  )
  FsReadTextFileCompleted(
    id~ : RequestId,
    result~ : Result[ReadTextFileResult, HandlerError]
  )
  FsWriteTextFileCompleted(
    id~ : RequestId,
    result~ : Result[WriteTextFileResult, HandlerError]
  )
  TerminalCreateCompleted(
    id~ : RequestId,
    result~ : Result[TerminalCreateResult, HandlerError]
  )
  TerminalOutputCompleted(
    id~ : RequestId,
    result~ : Result[TerminalOutputResult, HandlerError]
  )
  TerminalWaitForExitCompleted(
    id~ : RequestId,
    result~ : Result[TerminalWaitForExitResult, HandlerError]
  )
  TerminalKillCompleted(
    id~ : RequestId,
    result~ : Result[TerminalKillResult, HandlerError]
  )
  TerminalReleaseCompleted(
    id~ : RequestId,
    result~ : Result[TerminalReleaseResult, HandlerError]
  )
  ElicitationCreateCompleted(
    id~ : RequestId,
    result~ : Result[ElicitationCreateResult, HandlerError]
  )
  SessionUpdateCompleted(result~ : Result[Unit, HandlerError])
  ElicitationCompleteCompleted(result~ : Result[Unit, HandlerError])
} derive(Eq, Debug)

///|
/// The stable wire method name of one typed invocation.  Runtime bridges use
/// it for trace intents only; it never replaces the typed completion.
pub fn client_adapter_invocation_method_name(
  invocation : ClientAdapterInvocation,
) -> String {
  match invocation {
    RequestPermissionInvocation(id=_, params=_) => "session/request_permission"
    FsReadTextFileInvocation(id=_, params=_) => "fs/read_text_file"
    FsWriteTextFileInvocation(id=_, params=_) => "fs/write_text_file"
    TerminalCreateInvocation(id=_, params=_) => "terminal/create"
    TerminalOutputInvocation(id=_, params=_) => "terminal/output"
    TerminalWaitForExitInvocation(id=_, params=_) => "terminal/wait_for_exit"
    TerminalKillInvocation(id=_, params=_) => "terminal/kill"
    TerminalReleaseInvocation(id=_, params=_) => "terminal/release"
    ElicitationCreateInvocation(id=_, params=_) => "elicitation/create"
    SessionUpdateInvocation(params=_) => "session/update"
    ElicitationCompleteInvocation(params=_) => "elicitation/complete"
  }
}

///|
/// Synthesize the redacted typed failure completion for one invocation,
/// following the `client_adapter_call` convention for unknown failures.  The
/// owner task boundary uses this when async execution itself fails before a
/// typed completion exists.
pub fn client_adapter_failure_completion(
  invocation : ClientAdapterInvocation,
) -> ClientAdapterCompletion {
  match invocation {
    RequestPermissionInvocation(id~, params=_) =>
      RequestPermissionCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    FsReadTextFileInvocation(id~, params=_) =>
      FsReadTextFileCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    FsWriteTextFileInvocation(id~, params=_) =>
      FsWriteTextFileCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    TerminalCreateInvocation(id~, params=_) =>
      TerminalCreateCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    TerminalOutputInvocation(id~, params=_) =>
      TerminalOutputCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    TerminalWaitForExitInvocation(id~, params=_) =>
      TerminalWaitForExitCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    TerminalKillInvocation(id~, params=_) =>
      TerminalKillCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    TerminalReleaseInvocation(id~, params=_) =>
      TerminalReleaseCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    ElicitationCreateInvocation(id~, params=_) =>
      ElicitationCreateCompleted(
        id~,
        result=Err(Application(message="client handler failed")),
      )
    SessionUpdateInvocation(params=_) =>
      SessionUpdateCompleted(
        result=Err(Application(message="client handler failed")),
      )
    ElicitationCompleteInvocation(params=_) =>
      ElicitationCompleteCompleted(
        result=Err(Application(message="client handler failed")),
      )
  }
}

///|
/// Synthesize the typed cancellation completion for one invocation.  The
/// owner loop uses this when it grants an inbound cancellation so the wire id
/// settles through the normal completion path.
pub fn client_adapter_cancel_completion(
  invocation : ClientAdapterInvocation,
) -> ClientAdapterCompletion {
  match invocation {
    RequestPermissionInvocation(id~, params=_) =>
      RequestPermissionCompleted(id~, result=Err(Cancelled))
    FsReadTextFileInvocation(id~, params=_) =>
      FsReadTextFileCompleted(id~, result=Err(Cancelled))
    FsWriteTextFileInvocation(id~, params=_) =>
      FsWriteTextFileCompleted(id~, result=Err(Cancelled))
    TerminalCreateInvocation(id~, params=_) =>
      TerminalCreateCompleted(id~, result=Err(Cancelled))
    TerminalOutputInvocation(id~, params=_) =>
      TerminalOutputCompleted(id~, result=Err(Cancelled))
    TerminalWaitForExitInvocation(id~, params=_) =>
      TerminalWaitForExitCompleted(id~, result=Err(Cancelled))
    TerminalKillInvocation(id~, params=_) =>
      TerminalKillCompleted(id~, result=Err(Cancelled))
    TerminalReleaseInvocation(id~, params=_) =>
      TerminalReleaseCompleted(id~, result=Err(Cancelled))
    ElicitationCreateInvocation(id~, params=_) =>
      ElicitationCreateCompleted(id~, result=Err(Cancelled))
    SessionUpdateInvocation(params=_) =>
      SessionUpdateCompleted(result=Err(Cancelled))
    ElicitationCompleteInvocation(params=_) =>
      ElicitationCompleteCompleted(result=Err(Cancelled))
  }
}
