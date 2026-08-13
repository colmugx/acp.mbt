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
