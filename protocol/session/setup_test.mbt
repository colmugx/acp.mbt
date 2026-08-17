///|
fn session_setup_test_meta() -> ProtocolNullable[Json] {
  Omitted
}

///|
fn session_setup_test_server() -> McpServer {
  Stdio({
    name: "files",
    command: "/usr/local/bin/mcp-files",
    args: ["--root", "/workspace"],
    env: [],
    meta: session_setup_test_meta(),
  })
}

///|
fn session_setup_test_modes() -> SessionModeState {
  {
    current_mode_id: "ask",
    available_modes: [
      {
        id: "ask",
        name: "Ask",
        description: Null,
        meta: session_setup_test_meta(),
      },
      {
        id: "code",
        name: "Code",
        description: Omitted,
        meta: session_setup_test_meta(),
      },
    ],
    meta: session_setup_test_meta(),
  }
}

///|
fn session_setup_test_option() -> SessionConfigOption {
  {
    id: "confirm",
    name: "Confirm actions",
    description: Omitted,
    category: Value(Mode),
    kind: Boolean({ current_value: true }),
    meta: session_setup_test_meta(),
  }
}

///|
test "session new load and resume preserve roots mcp and distinct result types" {
  let new_params : NewSessionParams = {
    cwd: "/workspace",
    additional_directories: Value(["/workspace/shared"]),
    mcp_servers: [session_setup_test_server()],
    meta: Null,
  }
  assert_eq(
    new_session_params_from_json(new_session_params_to_json(new_params)),
    new_params,
  )

  let load_params : LoadSessionParams = {
    mcp_servers: [session_setup_test_server()],
    cwd: "/workspace",
    additional_directories: Value(["/workspace/shared"]),
    session_id: "s-load",
    meta: Omitted,
  }
  assert_eq(
    load_session_params_from_json(load_session_params_to_json(load_params)),
    load_params,
  )

  let resume_params : ResumeSessionParams = {
    session_id: "s-resume",
    cwd: "/workspace",
    additional_directories: Omitted,
    mcp_servers: Omitted,
    meta: Value({ "trace": Json::string("resume") }),
  }
  assert_eq(
    resume_session_params_from_json(
      resume_session_params_to_json(resume_params),
    ),
    resume_params,
  )

  let new_result : NewSessionResult = {
    session_id: "s-new",
    modes: Value(session_setup_test_modes()),
    config_options: Value([session_setup_test_option()]),
    meta: Null,
  }
  assert_eq(
    new_session_result_from_json(new_session_result_to_json(new_result)),
    new_result,
  )

  let load_result : LoadSessionResult = {
    modes: Null,
    config_options: Null,
    meta: Omitted,
  }
  assert_eq(
    load_session_result_from_json(load_session_result_to_json(load_result)),
    load_result,
  )

  let resume_result : ResumeSessionResult = {
    modes: Omitted,
    config_options: Omitted,
    meta: Value({ "replay": Json::boolean(false) }),
  }
  assert_eq(
    resume_session_result_from_json(
      resume_session_result_to_json(resume_result),
    ),
    resume_result,
  )
}

///|
test "session setup preserves omitted and null result fields" {
  let omitted = new_session_result_from_json(
    protocol_parse_json("{\"sessionId\":\"s\"}"),
  )
  assert_eq(omitted.modes, Omitted)
  assert_eq(omitted.config_options, Omitted)

  let nulls = new_session_result_from_json(
    protocol_parse_json(
      "{\"sessionId\":\"s\",\"modes\":null,\"configOptions\":null}",
    ),
  )
  assert_eq(nulls.modes, Null)
  assert_eq(nulls.config_options, Null)
}

///|
test "session setup rejects invalid roots null arrays and unknown fields" {
  try
    new_session_params_from_json(
      protocol_parse_json("{\"cwd\":\"relative\",\"mcpServers\":[]}"),
    )
  catch {
    InvalidPath(path="session/new.cwd", value="relative") => ()
    _ => fail("expected relative cwd rejection")
  } noraise {
    _ => fail("expected relative cwd rejection")
  }

  try
    new_session_params_from_json(
      protocol_parse_json(
        "{\"cwd\":\"/workspace\",\"additionalDirectories\":[\"relative\"],\"mcpServers\":[]}",
      ),
    )
  catch {
    InvalidPath(path="session/new.additionalDirectories[0]", value="relative") =>
      ()
    _ => fail("expected relative additional directory rejection")
  } noraise {
    _ => fail("expected relative additional directory rejection")
  }

  try
    resume_session_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"cwd\":\"/workspace\",\"mcpServers\":null}",
      ),
    )
  catch {
    InvalidField(path="session/resume.mcpServers", reason=_) => ()
    _ => fail("expected null mcpServers rejection")
  } noraise {
    _ => fail("expected null mcpServers rejection")
  }

  try
    load_session_params_from_json(
      protocol_parse_json(
        "{\"mcpServers\":[],\"cwd\":\"/workspace\",\"additionalDirectories\":null,\"sessionId\":\"s\"}",
      ),
    )
  catch {
    InvalidField(path="session/load.additionalDirectories", reason=_) => ()
    _ => fail("expected null additional directory rejection")
  } noraise {
    _ => fail("expected null additional directory rejection")
  }

  try
    new_session_params_from_json(
      protocol_parse_json(
        "{\"cwd\":\"/workspace\",\"mcpServers\":[],\"extra\":true}",
      ),
    )
  catch {
    UnknownField(path="session/new.extra") => ()
    _ => fail("expected setup unknown field rejection")
  } noraise {
    _ => fail("expected setup unknown field rejection")
  }
}

///|
test "session setup reports required fields and nested mcp paths" {
  try
    new_session_params_from_json(
      protocol_parse_json("{\"cwd\":\"/workspace\"}"),
    )
  catch {
    MissingField(path="session/new.mcpServers") => ()
    _ => fail("expected missing mcpServers")
  } noraise {
    _ => fail("expected missing mcpServers")
  }

  try
    new_session_params_from_json(
      protocol_parse_json(
        "{\"cwd\":\"/workspace\",\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"x\",\"command\":\"relative\",\"args\":[],\"env\":[]}]}",
      ),
    )
  catch {
    InvalidPath(path="session/new.mcpServers[0].command", value="relative") =>
      ()
    _ => fail("expected nested mcp path rejection")
  } noraise {
    _ => fail("expected nested mcp path rejection")
  }
}

///|
test "session new accepts untagged stdio mcp server per wire schema" {
  // Stdio is the untagged McpServer variant: editors send no "type" field.
  let params = new_session_params_from_json(
    protocol_parse_json(
      "{\"cwd\":\"/workspace\",\"mcpServers\":[{\"name\":\"fs\",\"command\":\"/usr/local/bin/mcp-fs\",\"args\":[\"--readonly\"],\"env\":[]}]}",
    ),
  )
  guard params.mcp_servers[0]
    is Stdio({ name: "fs", command: "/usr/local/bin/mcp-fs", .. }) else {
    fail("expected untagged stdio mcp server")
  }
  // An explicit "stdio" tag stays accepted for backwards compatibility.
  let tagged = new_session_params_from_json(
    protocol_parse_json(
      "{\"cwd\":\"/workspace\",\"mcpServers\":[{\"type\":\"stdio\",\"name\":\"fs\",\"command\":\"/usr/local/bin/mcp-fs\",\"args\":[],\"env\":[]}]}",
    ),
  )
  guard tagged.mcp_servers[0] is Stdio(_) else {
    fail("expected tagged stdio mcp server")
  }
  // Round trip still holds through the tagged encoder.
  assert_eq(
    new_session_params_from_json(new_session_params_to_json(params)),
    params,
  )
  try
    new_session_params_from_json(
      protocol_parse_json(
        "{\"cwd\":\"/workspace\",\"mcpServers\":[{\"type\":null}]}",
      ),
    )
  catch {
    ExpectedString(path="session/new.mcpServers[0].type") => ()
    _ => fail("expected null type rejection")
  } noraise {
    _ => fail("expected null type rejection")
  }
}

///|
test "session new result rejects an empty session id in both directions" {
  try
    new_session_result_from_json(
      protocol_parse_json("{\"sessionId\":\"\",\"modes\":null}"),
    )
  catch {
    InvalidField(path="session/new.sessionId", reason=_) => ()
    _ => fail("expected empty session id rejection on decode")
  } noraise {
    _ => fail("expected empty session id rejection on decode")
  }

  let empty : NewSessionResult = {
    session_id: "",
    modes: Omitted,
    config_options: Omitted,
    meta: Omitted,
  }
  try new_session_result_to_json(empty) catch {
    InvalidField(path="sessionId", reason=_) => ()
    _ => fail("expected empty session id rejection on encode")
  } noraise {
    _ => fail("expected empty session id rejection on encode")
  }
}
