///|
using @jsonrpc {type RequestId, jsonrpc_decode_int64}

///|
using @protocol_data {
  type ElicitationCreateParams,
  type ElicitationCompleteParams,
  type ProtocolDecodeError,
  type ReadTextFileParams,
  type RequestPermissionRequest,
  type TerminalCreateParams,
  type TerminalKillParams,
  type TerminalOutputParams,
  type TerminalReleaseParams,
  type TerminalWaitForExitParams,
  type WriteTextFileParams,
  elicitation_complete_params_from_json,
  elicitation_create_params_from_json,
  protocol_reject_unknown,
  protocol_required,
  protocol_require_object,
  request_permission_request_from_json,
  read_text_file_params_from_json,
  terminal_create_params_from_json,
  terminal_kill_params_from_json,
  terminal_output_params_from_json,
  terminal_release_params_from_json,
  terminal_wait_for_exit_params_from_json,
  write_text_file_params_from_json,
}

///|
using @session_protocol {
  type SessionUpdateParams,
  session_update_params_from_json,
}

///|
/// The complete stable v1 request surface delivered to a Client.
///
/// Every variant contains a protocol-validated payload.  The closed union
/// prevents Agent-to-Client dispatch from falling through to an untyped JSON
/// handler.
pub(all) enum ClientRequest {
  SessionRequestPermission(RequestPermissionRequest)
  FsReadTextFile(ReadTextFileParams)
  FsWriteTextFile(WriteTextFileParams)
  TerminalCreate(TerminalCreateParams)
  TerminalOutput(TerminalOutputParams)
  TerminalWaitForExit(TerminalWaitForExitParams)
  TerminalKill(TerminalKillParams)
  TerminalRelease(TerminalReleaseParams)
  ElicitationCreate(ElicitationCreateParams)
} derive(Eq, Debug)

///|
/// Stable v1 notifications delivered to a Client, including the
/// bidirectional JSON-RPC cancellation notification.
pub(all) enum ClientNotification {
  SessionUpdate(SessionUpdateParams)
  ElicitationComplete(ElicitationCompleteParams)
  CancelRequest(RequestId)
} derive(Eq, Debug)

///|
/// Errors raised while mapping a method and params value to the Client-side
/// closed unions above.
pub(all) suberror ClientMessageError {
  InvalidParams(method_name~ : String, cause~ : ProtocolDecodeError)
  UnknownMethod(method_name~ : String)
  WrongDirection(method_name~ : String)
  WrongKind(method_name~ : String)
} derive(Eq, Debug)

///|
/// Return the exact wire method represented by an accepted request.
pub fn ClientRequest::method_name(self : ClientRequest) -> String {
  match self {
    SessionRequestPermission(_) => "session/request_permission"
    FsReadTextFile(_) => "fs/read_text_file"
    FsWriteTextFile(_) => "fs/write_text_file"
    TerminalCreate(_) => "terminal/create"
    TerminalOutput(_) => "terminal/output"
    TerminalWaitForExit(_) => "terminal/wait_for_exit"
    TerminalKill(_) => "terminal/kill"
    TerminalRelease(_) => "terminal/release"
    ElicitationCreate(_) => "elicitation/create"
  }
}

///|
/// Return the exact wire method represented by an accepted notification.
pub fn ClientNotification::method_name(self : ClientNotification) -> String {
  match self {
    SessionUpdate(_) => "session/update"
    ElicitationComplete(_) => "elicitation/complete"
    CancelRequest(_) => "$/cancel_request"
  }
}

///|
fn[T] client_decode_params(
  method_name : String,
  params : Json?,
  decode : (Json) -> T raise ProtocolDecodeError,
) -> T raise ClientMessageError {
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
/// Decode one Agent-to-Client request params value into the closed request
/// union.  Known Client-to-Agent methods and notifications are rejected
/// explicitly rather than being treated as unknown methods.
pub fn decode_client_request(
  method_name : String,
  params : Json?,
) -> ClientRequest raise ClientMessageError {
  match method_name {
    "session/request_permission" =>
      SessionRequestPermission(
        client_decode_params(method_name, params, value => {
          request_permission_request_from_json(value)
        }),
      )
    "fs/read_text_file" =>
      FsReadTextFile(
        client_decode_params(method_name, params, value => {
          read_text_file_params_from_json(value)
        }),
      )
    "fs/write_text_file" =>
      FsWriteTextFile(
        client_decode_params(method_name, params, value => {
          write_text_file_params_from_json(value)
        }),
      )
    "terminal/create" =>
      TerminalCreate(
        client_decode_params(method_name, params, value => {
          terminal_create_params_from_json(value)
        }),
      )
    "terminal/output" =>
      TerminalOutput(
        client_decode_params(method_name, params, value => {
          terminal_output_params_from_json(value)
        }),
      )
    "terminal/wait_for_exit" =>
      TerminalWaitForExit(
        client_decode_params(method_name, params, value => {
          terminal_wait_for_exit_params_from_json(value)
        }),
      )
    "terminal/kill" =>
      TerminalKill(
        client_decode_params(method_name, params, value => {
          terminal_kill_params_from_json(value)
        }),
      )
    "terminal/release" =>
      TerminalRelease(
        client_decode_params(method_name, params, value => {
          terminal_release_params_from_json(value)
        }),
      )
    "elicitation/create" =>
      ElicitationCreate(
        client_decode_params(method_name, params, value => {
          elicitation_create_params_from_json(value)
        }),
      )
    "session/update" | "elicitation/complete" =>
      raise WrongDirection(method_name~)
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
    | "session/prompt"
    | "session/cancel" => raise WrongDirection(method_name~)
    "$/cancel_request" => raise WrongKind(method_name~)
    _ => raise UnknownMethod(method_name~)
  }
}

///|
fn client_decode_cancel_request_id(
  value : Json,
  path~ : String,
) -> RequestId raise ProtocolDecodeError {
  match value {
    String(value) => String(value)
    Number(value, repr~) =>
      Number(
        jsonrpc_decode_int64(value, repr, path~) catch {
          _ =>
            raise InvalidField(path~, reason="expected a signed 64-bit integer")
        },
      )
    Null => Null
    _ => raise InvalidField(path~, reason="must be a string, integer, or null")
  }
}

///|
/// Decode one Agent-to-Client notification params value.  String, integer, and
/// null cancellation identifiers remain distinct typed `RequestId` values.
pub fn decode_client_notification(
  method_name : String,
  params : Json?,
) -> ClientNotification raise ClientMessageError {
  match method_name {
    "session/update" =>
      SessionUpdate(
        client_decode_params(method_name, params, value => {
          session_update_params_from_json(value)
        }),
      )
    "elicitation/complete" =>
      ElicitationComplete(
        client_decode_params(method_name, params, value => {
          elicitation_complete_params_from_json(value)
        }),
      )
    "$/cancel_request" =>
      CancelRequest(
        client_decode_params(method_name, params, value => {
          let fields = protocol_require_object(value, path=method_name)
          protocol_reject_unknown(fields, ["requestId"], prefix=method_name)
          let request_id = protocol_required(
            fields,
            "requestId",
            path=method_name + ".requestId",
          )
          client_decode_cancel_request_id(
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
    | "session/prompt"
    | "session/cancel"
    | "session/request_permission"
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
