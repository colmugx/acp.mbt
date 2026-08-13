///|
using @agent {type AgentOutboundReply}

///|
using @agent_message {type AgentNotification, type AgentRequest}

///|
using @client {type ClientReply}

///|
using @client_message {type ClientNotification, type ClientRequest}

///|
using @jsonrpc {type RequestId}

///|
using @protocol_data {
  type ProtocolDecodeError,
  elicitation_complete_params_to_json,
  elicitation_create_params_to_json,
  elicitation_create_result_from_json,
  initialize_params_to_json,
  initialize_result_from_json,
  authenticate_params_to_json,
  authenticate_result_from_json,
  logout_params_to_json,
  logout_result_from_json,
  read_text_file_params_to_json,
  read_text_file_result_from_json,
  request_permission_request_to_json,
  request_permission_response_from_json,
  terminal_create_params_to_json,
  terminal_create_result_from_json,
  terminal_kill_params_to_json,
  terminal_kill_result_from_json,
  terminal_output_params_to_json,
  terminal_output_result_from_json,
  terminal_release_params_to_json,
  terminal_release_result_from_json,
  terminal_wait_for_exit_params_to_json,
  terminal_wait_for_exit_result_from_json,
  write_text_file_params_to_json,
  write_text_file_result_from_json,
}

///|
using @session_protocol {
  cancel_params_to_json,
  close_session_params_to_json,
  close_session_result_from_json,
  delete_session_params_to_json,
  delete_session_result_from_json,
  list_sessions_params_to_json,
  list_sessions_result_from_json,
  load_session_params_to_json,
  load_session_result_from_json,
  new_session_params_to_json,
  new_session_result_from_json,
  prompt_params_to_json,
  prompt_result_from_json,
  resume_session_params_to_json,
  resume_session_result_from_json,
  session_update_params_to_json,
  set_session_config_option_params_to_json,
  set_session_config_option_result_from_json,
  set_session_mode_params_to_json,
  set_session_mode_result_from_json,
}

///|
/// The opaque typed payload handed from the broker to the JSON-RPC owner loop.
/// The loop is responsible for ids, envelopes, correlation, and transport;
/// this value carries only an exact method and protocol-validated params
/// object.
#warnings("-unused_field")
priv struct BrokerWirePayload {
  method_name : String
  params : Json
}

///|
/// The static phase identifies which typed payload failed.  The underlying
/// protocol error remains attached so callers can trace the exact wire path.
#warnings("-unused_value")
priv enum BrokerCodecPhase {
  Params
  Result
} derive(Eq, Debug)

///|
/// Failures from a typed broker conversion.  There is no stringification or
/// fallback variant: every failure retains its phase, method, and original
/// protocol decoder error.
#warnings("-unused_value")
priv suberror BrokerCodecError {
  InvalidPayload(
    phase~ : BrokerCodecPhase,
    method_name~ : String,
    cause~ : ProtocolDecodeError
  )
} derive(Eq, Debug)

///|
fn broker_encode_params(
  method_name : String,
  encode : () -> Json raise ProtocolDecodeError,
) -> BrokerWirePayload raise BrokerCodecError {
  let params = encode() catch {
    cause => raise InvalidPayload(phase=Params, method_name~, cause~)
  }
  { method_name, params }
}

///|
fn[T] broker_decode_result(
  method_name : String,
  value : Json,
  decode : (Json) -> T raise ProtocolDecodeError,
) -> T raise BrokerCodecError {
  decode(value) catch {
    cause => raise InvalidPayload(phase=Result, method_name~, cause~)
  }
}

///|
fn broker_request_id_params(request_id : RequestId) -> Json {
  let fields : Map[String, Json] = Map([])
  fields["requestId"] = broker_request_id_json(request_id)
  Json::object(fields)
}

///|
fn broker_request_id_json(request_id : RequestId) -> Json {
  match request_id {
    String(value) => Json::string(value)
    Number(value) => Json::number(value.to_double(), repr=value.to_string())
    Null => Json::null()
  }
}

///|
/// Encode one typed Agent-to-Client request for the owner loop.
#warnings("-unused_value")
fn broker_client_request_payload(
  request : ClientRequest,
) -> BrokerWirePayload raise BrokerCodecError {
  match request {
    SessionRequestPermission(value) =>
      broker_encode_params("session/request_permission", () => {
        request_permission_request_to_json(value)
      })
    FsReadTextFile(value) =>
      broker_encode_params("fs/read_text_file", () => {
        read_text_file_params_to_json(value)
      })
    FsWriteTextFile(value) =>
      broker_encode_params("fs/write_text_file", () => {
        write_text_file_params_to_json(value)
      })
    TerminalCreate(value) =>
      broker_encode_params("terminal/create", () => {
        terminal_create_params_to_json(value)
      })
    TerminalOutput(value) =>
      broker_encode_params("terminal/output", () => {
        terminal_output_params_to_json(value)
      })
    TerminalWaitForExit(value) =>
      broker_encode_params("terminal/wait_for_exit", () => {
        terminal_wait_for_exit_params_to_json(value)
      })
    TerminalKill(value) =>
      broker_encode_params("terminal/kill", () => {
        terminal_kill_params_to_json(value)
      })
    TerminalRelease(value) =>
      broker_encode_params("terminal/release", () => {
        terminal_release_params_to_json(value)
      })
    ElicitationCreate(value) =>
      broker_encode_params("elicitation/create", () => {
        elicitation_create_params_to_json(value)
      })
  }
}

///|
/// Encode one typed Agent-to-Client notification for the owner loop.
#warnings("-unused_value")
fn broker_client_notification_payload(
  notification : ClientNotification,
) -> BrokerWirePayload raise BrokerCodecError {
  match notification {
    SessionUpdate(value) =>
      broker_encode_params("session/update", () => {
        session_update_params_to_json(value)
      })
    ElicitationComplete(value) =>
      broker_encode_params("elicitation/complete", () => {
        elicitation_complete_params_to_json(value)
      })
    CancelRequest(value) =>
      {
        method_name: "$/cancel_request",
        params: broker_request_id_params(value),
      }
  }
}

///|
/// Decode a successful result using the request variant that owns its
/// correlation slot.  The peer cannot select a result type by metadata.
#warnings("-unused_value")
fn broker_decode_client_request_result(
  request : ClientRequest,
  result : Json,
) -> AgentOutboundReply raise BrokerCodecError {
  match request {
    SessionRequestPermission(_) =>
      AgentReplyRequestPermission(
        broker_decode_result("session/request_permission", result, value => {
          request_permission_response_from_json(value)
        }),
      )
    FsReadTextFile(_) =>
      AgentReplyFsReadTextFile(
        broker_decode_result("fs/read_text_file", result, value => {
          read_text_file_result_from_json(value)
        }),
      )
    FsWriteTextFile(_) =>
      AgentReplyFsWriteTextFile(
        broker_decode_result("fs/write_text_file", result, value => {
          write_text_file_result_from_json(value)
        }),
      )
    TerminalCreate(_) =>
      AgentReplyTerminalCreate(
        broker_decode_result("terminal/create", result, value => {
          terminal_create_result_from_json(value)
        }),
      )
    TerminalOutput(_) =>
      AgentReplyTerminalOutput(
        broker_decode_result("terminal/output", result, value => {
          terminal_output_result_from_json(value)
        }),
      )
    TerminalWaitForExit(_) =>
      AgentReplyTerminalWaitForExit(
        broker_decode_result("terminal/wait_for_exit", result, value => {
          terminal_wait_for_exit_result_from_json(value)
        }),
      )
    TerminalKill(_) =>
      AgentReplyTerminalKill(
        broker_decode_result("terminal/kill", result, value => {
          terminal_kill_result_from_json(value)
        }),
      )
    TerminalRelease(_) =>
      AgentReplyTerminalRelease(
        broker_decode_result("terminal/release", result, value => {
          terminal_release_result_from_json(value)
        }),
      )
    ElicitationCreate(_) =>
      AgentReplyElicitationCreate(
        broker_decode_result("elicitation/create", result, value => {
          elicitation_create_result_from_json(value)
        }),
      )
  }
}

///|
/// Encode one typed Client-to-Agent request for the owner loop.
#warnings("-unused_value")
fn broker_agent_request_payload(
  request : AgentRequest,
) -> BrokerWirePayload raise BrokerCodecError {
  match request {
    Initialize(value) =>
      broker_encode_params("initialize", () => initialize_params_to_json(value))
    Authenticate(value) =>
      broker_encode_params("authenticate", () => {
        authenticate_params_to_json(value)
      })
    Logout(value) =>
      broker_encode_params("logout", () => logout_params_to_json(value))
    SessionNew(value) =>
      broker_encode_params("session/new", () => {
        new_session_params_to_json(value)
      })
    SessionLoad(value) =>
      broker_encode_params("session/load", () => {
        load_session_params_to_json(value)
      })
    SessionResume(value) =>
      broker_encode_params("session/resume", () => {
        resume_session_params_to_json(value)
      })
    SessionList(value) =>
      broker_encode_params("session/list", () => {
        list_sessions_params_to_json(value)
      })
    SessionDelete(value) =>
      broker_encode_params("session/delete", () => {
        delete_session_params_to_json(value)
      })
    SessionClose(value) =>
      broker_encode_params("session/close", () => {
        close_session_params_to_json(value)
      })
    SessionSetMode(value) =>
      broker_encode_params("session/set_mode", () => {
        set_session_mode_params_to_json(value)
      })
    SessionSetConfigOption(value) =>
      broker_encode_params("session/set_config_option", () => {
        set_session_config_option_params_to_json(value)
      })
    SessionPrompt(value) =>
      broker_encode_params("session/prompt", () => prompt_params_to_json(value))
  }
}

///|
/// Encode one typed Client-to-Agent notification for the owner loop.
#warnings("-unused_value")
fn broker_agent_notification_payload(
  notification : AgentNotification,
) -> BrokerWirePayload raise BrokerCodecError {
  match notification {
    SessionCancel(value) =>
      broker_encode_params("session/cancel", () => cancel_params_to_json(value))
    CancelRequest(value) =>
      {
        method_name: "$/cancel_request",
        params: broker_request_id_params(value),
      }
  }
}

///|
/// Decode a successful result using the originating AgentRequest variant.
#warnings("-unused_value")
fn broker_decode_agent_request_result(
  request : AgentRequest,
  result : Json,
) -> ClientReply raise BrokerCodecError {
  match request {
    Initialize(_) =>
      ClientReplyInitialize(
        broker_decode_result("initialize", result, value => {
          initialize_result_from_json(value)
        }),
      )
    Authenticate(_) =>
      ClientReplyAuthenticate(
        broker_decode_result("authenticate", result, value => {
          authenticate_result_from_json(value)
        }),
      )
    Logout(_) =>
      ClientReplyLogout(
        broker_decode_result("logout", result, value => {
          logout_result_from_json(value)
        }),
      )
    SessionNew(_) =>
      ClientReplyNewSession(
        broker_decode_result("session/new", result, value => {
          new_session_result_from_json(value)
        }),
      )
    SessionLoad(_) =>
      ClientReplyLoadSession(
        broker_decode_result("session/load", result, value => {
          load_session_result_from_json(value)
        }),
      )
    SessionResume(_) =>
      ClientReplyResumeSession(
        broker_decode_result("session/resume", result, value => {
          resume_session_result_from_json(value)
        }),
      )
    SessionList(_) =>
      ClientReplyListSessions(
        broker_decode_result("session/list", result, value => {
          list_sessions_result_from_json(value)
        }),
      )
    SessionDelete(_) =>
      ClientReplyDeleteSession(
        broker_decode_result("session/delete", result, value => {
          delete_session_result_from_json(value)
        }),
      )
    SessionClose(_) =>
      ClientReplyCloseSession(
        broker_decode_result("session/close", result, value => {
          close_session_result_from_json(value)
        }),
      )
    SessionSetMode(_) =>
      ClientReplySetMode(
        broker_decode_result("session/set_mode", result, value => {
          set_session_mode_result_from_json(value)
        }),
      )
    SessionSetConfigOption(_) =>
      ClientReplySetConfigOption(
        broker_decode_result("session/set_config_option", result, value => {
          set_session_config_option_result_from_json(value)
        }),
      )
    SessionPrompt(_) =>
      ClientReplyPrompt(
        broker_decode_result("session/prompt", result, value => {
          prompt_result_from_json(value)
        }),
      )
  }
}
