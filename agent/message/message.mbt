///|
/// The complete stable v1 request surface accepted by an Agent.
pub(all) enum AgentRequest {
  Initialize(@protocol.InitializeParams)
  Authenticate(@protocol.AuthenticateParams)
  Logout(@protocol.LogoutParams)
  SessionNew(@session_protocol.NewSessionParams)
  SessionLoad(@session_protocol.LoadSessionParams)
  SessionResume(@session_protocol.ResumeSessionParams)
  SessionList(@session_protocol.ListSessionsParams)
  SessionDelete(@session_protocol.DeleteSessionParams)
  SessionClose(@session_protocol.CloseSessionParams)
  SessionSetMode(@session_protocol.SetSessionModeParams)
  SessionSetConfigOption(@session_protocol.SetSessionConfigOptionParams)
  SessionPrompt(@session_protocol.PromptParams)
} derive(Eq, Debug)

///|
/// Stable v1 notifications accepted by an Agent.
pub(all) enum AgentNotification {
  SessionCancel(@session_protocol.CancelParams)
  CancelRequest(@jsonrpc.RequestId)
} derive(Eq, Debug)

///|
/// Errors raised while mapping a JSON-RPC method and params value to the
/// Agent-side closed unions above.
pub(all) suberror AgentMessageError {
  InvalidParams(method_name~ : String, cause~ : @protocol.ProtocolDecodeError)
  UnknownMethod(method_name~ : String)
  WrongDirection(method_name~ : String)
  WrongKind(method_name~ : String)
} derive(Eq, Debug)

///|
pub fn AgentRequest::method_name(self : AgentRequest) -> String {
  match self {
    Initialize(_) => "initialize"
    Authenticate(_) => "authenticate"
    Logout(_) => "logout"
    SessionNew(_) => "session/new"
    SessionLoad(_) => "session/load"
    SessionResume(_) => "session/resume"
    SessionList(_) => "session/list"
    SessionDelete(_) => "session/delete"
    SessionClose(_) => "session/close"
    SessionSetMode(_) => "session/set_mode"
    SessionSetConfigOption(_) => "session/set_config_option"
    SessionPrompt(_) => "session/prompt"
  }
}

///|
pub fn AgentNotification::method_name(self : AgentNotification) -> String {
  match self {
    SessionCancel(_) => "session/cancel"
    CancelRequest(_) => "$/cancel_request"
  }
}

///|
fn[T] agent_decode_params(
  method_name : String,
  params : Json?,
  decode : (Json) -> T raise @protocol.ProtocolDecodeError,
) -> T raise AgentMessageError {
  let value = match params {
    Some(value) => value
    None =>
      raise InvalidParams(
        method_name~,
        cause=MissingField(path=method_name + ".params"),
      )
  }
  decode(value) catch {
    error => raise InvalidParams(method_name~, cause=error)
  }
}

///|
pub fn decode_agent_request(
  method_name : String,
  params : Json?,
) -> AgentRequest raise AgentMessageError {
  match method_name {
    "initialize" =>
      Initialize(
        agent_decode_params(method_name, params, value => {
          @protocol.initialize_params_from_json(value)
        }),
      )
    "authenticate" =>
      Authenticate(
        agent_decode_params(method_name, params, value => {
          @protocol.authenticate_params_from_json(value)
        }),
      )
    "logout" =>
      Logout(
        agent_decode_params(method_name, params, value => {
          @protocol.logout_params_from_json(value)
        }),
      )
    "session/new" =>
      SessionNew(
        agent_decode_params(method_name, params, value => {
          @session_protocol.new_session_params_from_json(value)
        }),
      )
    "session/load" =>
      SessionLoad(
        agent_decode_params(method_name, params, value => {
          @session_protocol.load_session_params_from_json(value)
        }),
      )
    "session/resume" =>
      SessionResume(
        agent_decode_params(method_name, params, value => {
          @session_protocol.resume_session_params_from_json(value)
        }),
      )
    "session/list" =>
      SessionList(
        agent_decode_params(method_name, params, value => {
          @session_protocol.list_sessions_params_from_json(value)
        }),
      )
    "session/delete" =>
      SessionDelete(
        agent_decode_params(method_name, params, value => {
          @session_protocol.delete_session_params_from_json(value)
        }),
      )
    "session/close" =>
      SessionClose(
        agent_decode_params(method_name, params, value => {
          @session_protocol.close_session_params_from_json(value)
        }),
      )
    "session/set_mode" =>
      SessionSetMode(
        agent_decode_params(method_name, params, value => {
          @session_protocol.set_session_mode_params_from_json(value)
        }),
      )
    "session/set_config_option" =>
      SessionSetConfigOption(
        agent_decode_params(method_name, params, value => {
          @session_protocol.set_session_config_option_params_from_json(value)
        }),
      )
    "session/prompt" =>
      SessionPrompt(
        agent_decode_params(method_name, params, value => {
          @session_protocol.prompt_params_from_json(value)
        }),
      )
    "session/cancel" | "$/cancel_request" => raise WrongKind(method_name~)
    "session/request_permission"
    | "fs/read_text_file"
    | "fs/write_text_file"
    | "terminal/create"
    | "terminal/output"
    | "terminal/wait_for_exit"
    | "terminal/kill"
    | "terminal/release"
    | "elicitation/create" => raise WrongDirection(method_name~)
    _ => raise UnknownMethod(method_name~)
  }
}

///|
fn agent_decode_cancel_request_id(
  value : Json,
  path~ : String,
) -> @jsonrpc.RequestId raise @protocol.ProtocolDecodeError {
  match value {
    String(value) => String(value)
    Number(value, repr~) =>
      Number(
        @jsonrpc.jsonrpc_decode_int64(value, repr, path~) catch {
          _ =>
            raise InvalidField(path~, reason="must be a signed 64-bit integer")
        },
      )
    Null => Null
    _ => raise InvalidField(path~, reason="must be a string, integer, or null")
  }
}

///|
pub fn decode_agent_notification(
  method_name : String,
  params : Json?,
) -> AgentNotification raise AgentMessageError {
  match method_name {
    "session/cancel" =>
      SessionCancel(
        agent_decode_params(method_name, params, value => {
          @session_protocol.cancel_params_from_json(value)
        }),
      )
    "$/cancel_request" =>
      CancelRequest(
        agent_decode_params(method_name, params, value => {
          let fields = @protocol.protocol_require_object(
            value,
            path=method_name,
          )
          @protocol.protocol_reject_unknown(
            fields,
            ["requestId"],
            prefix=method_name,
          )
          let request_id = @protocol.protocol_required(
            fields,
            "requestId",
            path=method_name + ".requestId",
          )
          agent_decode_cancel_request_id(
            request_id,
            path=method_name + ".requestId",
          )
        }),
      )
    "initialize"
    | "authenticate"
    | "logout"
    | "session/new"
    | "session/load"
    | "session/resume"
    | "session/list"
    | "session/delete"
    | "session/close"
    | "session/set_mode"
    | "session/set_config_option"
    | "session/prompt" => raise WrongKind(method_name~)
    "session/request_permission"
    | "fs/read_text_file"
    | "fs/write_text_file"
    | "terminal/create"
    | "terminal/output"
    | "terminal/wait_for_exit"
    | "terminal/kill"
    | "terminal/release"
    | "elicitation/create"
    | "session/update"
    | "elicitation/complete" => raise WrongDirection(method_name~)
    _ => raise UnknownMethod(method_name~)
  }
}
