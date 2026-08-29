///|
using @acp_error {type AgentCompositionError, type HandlerError}

///|
using @agent_protocol {type AgentProtocolConfig, agent_protocol_state_new}

///|
using @client_message {type ClientNotification, type ClientRequest}

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
  type AuthMethod,
  type AuthenticateParams,
  type AuthenticateResult,
  type ElicitationCompleteParams,
  type ElicitationCreateParams,
  type Implementation,
  type LogoutParams,
  type LogoutResult,
  type ReadTextFileParams,
  type RequestPermissionRequest,
  type SessionConfigOption,
  type SessionInfo,
  type TerminalCreateParams,
  type TerminalKillParams,
  type TerminalOutputParams,
  type TerminalReleaseParams,
  type TerminalWaitForExitParams,
  type WriteTextFileParams,
  initialize_result_from_json,
  protocol_parse_json,
}

///|
using @session_protocol {
  type CancelParams,
  type CloseSessionParams,
  type CloseSessionResult,
  type DeleteSessionParams,
  type DeleteSessionResult,
  type ForkSessionParams,
  type ForkSessionResult,
  type ListSessionsParams,
  type ListSessionsResult,
  type LoadSessionParams,
  type LoadSessionResult,
  type NewSessionParams,
  type NewSessionResult,
  type PromptParams,
  type PromptResult,
  type ResumeSessionParams,
  type ResumeSessionResult,
  type SessionMode,
  type SessionModeState,
  type SessionUpdateParams,
  type SetSessionConfigOptionParams,
  type SetSessionConfigOptionResult,
  type SetSessionModeParams,
  type SetSessionModeResult,
  type StopReason,
  close_session_result_from_json,
  delete_session_result_from_json,
  fork_session_result_from_json,
  list_sessions_result_from_json,
  load_session_result_from_json,
  new_session_result_from_json,
  prompt_result_from_json,
  resume_session_result_from_json,
  set_session_config_option_result_from_json,
  set_session_mode_result_from_json,
}
