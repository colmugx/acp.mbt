///|
using @agent_message {
  type AgentMessageError,
  type AgentNotification,
  type AgentRequest,
  decode_agent_notification,
  decode_agent_request,
}

///|
using @acp_error {type AgentCompositionError, type HandlerError}

///|
using @agent_protocol {
  type AgentProtocolConfig,
  type AgentProtocolError,
  type AgentProtocolState,
  type AgentProtocolStep,
  agent_protocol_reduce,
}

///|
using @client_message {type ClientNotification, type ClientRequest}

///|
using @connection {
  type RuntimeOutboundChannel,
  type RuntimeOwnerEffect,
  type RuntimeOwnerNotificationAdmission,
  type RuntimeOwnerNotificationCompletion,
  type RuntimeOwnerPort,
  type RuntimeOwnerRequestAdmission,
  type RuntimeOwnerRequestCompletion,
  connection_runtime_run_owner,
  connection_runtime_run_owner_with_outbound,
}

///|
using @runtime {
  type RuntimeHandlerResult,
  type RuntimeOptions,
  type RuntimePorts,
  type RuntimeTraceEvent,
  runtime_default_options,
  runtime_stderr_trace,
  runtime_stdio_ports,
  runtime_validate_options,
}

///|
using @jsonrpc {
  type JsonRpcError,
  type JsonRpcId,
  type JsonRpcMessage,
  type JsonRpcNotification,
  type JsonRpcResponse,
  type RequestId,
}

///|
using @protocol_data {
  type AgentAuthCapabilities,
  type AgentCapabilities,
  type AgentMcpCapabilities,
  type AgentPromptCapabilities,
  type AgentSessionCapabilities,
  type AuthMethod,
  type AuthenticateParams,
  type AuthenticateResult,
  type CapabilityMarker,
  type ElicitationCompleteParams,
  type ElicitationCreateParams,
  type ElicitationCreateResult,
  type Implementation,
  type InitializeParams,
  type InitializeResult,
  type LogoutParams,
  type LogoutResult,
  type ProtocolDecodeError,
  type ProtocolNullable,
  type ReadTextFileParams,
  type ReadTextFileResult,
  type RequestPermissionRequest,
  type RequestPermissionResponse,
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
  initialize_result_to_json,
  authenticate_result_to_json,
  logout_result_to_json,
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
  close_session_result_to_json,
  delete_session_result_to_json,
  list_sessions_result_to_json,
  load_session_result_to_json,
  new_session_result_to_json,
  prompt_result_to_json,
  resume_session_result_to_json,
  set_session_config_option_result_to_json,
  set_session_mode_result_to_json,
}
