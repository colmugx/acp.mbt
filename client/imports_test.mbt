///|
/// Shared blackbox-test imports for the client package.  `using` declarations
/// are package-scoped across test files, so they are consolidated here (the
/// same pattern as agent/imports_test.mbt) instead of being repeated in each
/// *_test.mbt file.

///|
using @acp_error {type ClientCompositionError, type HandlerError}

///|
using @agent_message {type AgentNotification, type AgentRequest}

///|
using @client_protocol {client_protocol_state_new, client_protocol_state_ready}

///|
using @jsonrpc {
  type JsonRpcErrorCode,
  type JsonRpcId,
  type JsonRpcMessage,
  type JsonRpcNotification,
  type JsonRpcRequest,
  type JsonRpcResponse,
  type RequestId,
}

///|
using @protocol_data {
  type AuthenticateParams,
  type ElicitationCompleteParams,
  type ElicitationCreateResult,
  type ElicitationFormParams,
  type ElicitationUrlParams,
  type Implementation,
  type InitializeParams,
  type LogoutParams,
  type ProtocolDecodeError,
  type ProtocolNullable,
  type ReadTextFileParams,
  type ReadTextFileResult,
  type RequestPermissionRequest,
  type RequestPermissionResponse,
  type SessionUpdate,
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
  elicitation_create_result_from_json,
  protocol_parse_json,
  read_text_file_result_from_json,
  request_permission_response_from_json,
  terminal_create_result_from_json,
  terminal_output_result_from_json,
  terminal_wait_for_exit_result_from_json,
  write_text_file_result_from_json,
}

///|
using @session_protocol {
  type CloseSessionParams,
  type DeleteSessionParams,
  type ListSessionsParams,
  type LoadSessionParams,
  type NewSessionParams,
  type PromptParams,
  type ResumeSessionParams,
  type SessionUpdateParams,
  type SetSessionConfigOptionParams,
  type SetSessionModeParams,
}
