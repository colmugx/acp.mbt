///|
using @acp_error {type AgentCompositionError, type HandlerError}

///|
using @agent_protocol {type AgentProtocolConfig, agent_protocol_state_new}

///|
using @client_message {type ClientNotification, type ClientRequest}

///|
using @jsonrpc {
  type JsonRpcErrorCode,
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
  type TerminalCreateParams,
  type TerminalKillParams,
  type TerminalOutputParams,
  type TerminalReleaseParams,
  type TerminalWaitForExitParams,
  type WriteTextFileParams,
  protocol_parse_json,
}

///|
using @session_protocol {
  type CancelParams,
  type CloseSessionParams,
  type CloseSessionResult,
  type DeleteSessionParams,
  type DeleteSessionResult,
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
  type SessionUpdateParams,
  type SetSessionConfigOptionParams,
  type SetSessionConfigOptionResult,
  type SetSessionModeParams,
  type SetSessionModeResult,
}
