///|
fn terminal_test_meta() -> ProtocolNullable[Json] {
  Value({ "source": Json::string("test") })
}

///|
fn terminal_test_env() -> TerminalEnvVariable {
  { name: "LANG", value: "C.UTF-8", meta: Omitted, }
}

///|
test "terminal host methods round trip every wire shape" {
  let create : TerminalCreateParams = {
    session_id: "session-1",
    command: "printf",
    args: Value(["héllo", "world"]),
    env: Value([terminal_test_env()]),
    cwd: Value("/workspace"),
    output_byte_limit: Value(4096UL),
    meta: terminal_test_meta(),
  }
  let encoded_create = terminal_create_params_to_json(create)
  let decoded_create = terminal_create_params_from_json(encoded_create) catch {
    InvalidField(path~, reason~) =>
      fail(
        path + ":" + reason + " wire=" + protocol_stringify_json(encoded_create),
      )
    _ => fail("unexpected terminal integer decode error")
  }
  assert_eq(decoded_create, create)

  let create_result : TerminalCreateResult = {
    terminal_id: "terminal-1",
    meta: Null,
  }
  assert_eq(
    terminal_create_result_from_json(
      terminal_create_result_to_json(create_result),
    ),
    create_result,
  )

  let output_params : TerminalOutputParams = {
    session_id: "session-1",
    terminal_id: "terminal-1",
    meta: Omitted,
  }
  assert_eq(
    terminal_output_params_from_json(
      terminal_output_params_to_json(output_params),
    ),
    output_params,
  )

  let exit_status : TerminalExitStatus = {
    exit_code: Value(4294967295UL),
    signal: Null,
    meta: terminal_test_meta(),
  }
  let output_result : TerminalOutputResult = {
    output: "界\n",
    truncated: true,
    exit_status: Value(exit_status),
    meta: Omitted,
  }
  assert_eq(
    terminal_output_result_from_json(
      terminal_output_result_to_json(output_result),
    ),
    output_result,
  )

  let wait_params : TerminalWaitForExitParams = {
    session_id: "session-1",
    terminal_id: "terminal-1",
    meta: Null,
  }
  assert_eq(
    terminal_wait_for_exit_params_from_json(
      terminal_wait_for_exit_params_to_json(wait_params),
    ),
    wait_params,
  )
  let wait_result : TerminalWaitForExitResult = {
    exit_code: Omitted,
    signal: Value("SIGTERM"),
    meta: terminal_test_meta(),
  }
  assert_eq(
    terminal_wait_for_exit_result_from_json(
      terminal_wait_for_exit_result_to_json(wait_result),
    ),
    wait_result,
  )

  let kill_params : TerminalKillParams = {
    session_id: "session-1",
    terminal_id: "terminal-1",
    meta: Omitted,
  }
  assert_eq(
    terminal_kill_params_from_json(terminal_kill_params_to_json(kill_params)),
    kill_params,
  )
  let kill_result : TerminalKillResult = { meta: Null, }
  assert_eq(
    terminal_kill_result_from_json(terminal_kill_result_to_json(kill_result)),
    kill_result,
  )

  let release_params : TerminalReleaseParams = {
    session_id: "session-1",
    terminal_id: "terminal-1",
    meta: terminal_test_meta(),
  }
  assert_eq(
    terminal_release_params_from_json(
      terminal_release_params_to_json(release_params),
    ),
    release_params,
  )
  let release_result : TerminalReleaseResult = { meta: Omitted, }
  assert_eq(
    terminal_release_result_from_json(
      terminal_release_result_to_json(release_result),
    ),
    release_result,
  )
}

///|
test "terminal host validation rejects unsafe ids, cwd, limits and fields" {
  try
    terminal_create_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"command\":\"echo\",\"cwd\":\"relative\"}",
      ),
    )
  catch {
    InvalidPath(path="terminal/create.cwd", value="relative") => ()
    _ => fail("expected absolute cwd rejection")
  } noraise {
    _ => fail("expected absolute cwd rejection")
  }

  try
    terminal_create_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"command\":\"echo\",\"outputByteLimit\":-1}",
      ),
    )
  catch {
    InvalidField(path="terminal/create.outputByteLimit", reason=_) => ()
    _ => fail("expected non-negative output limit rejection")
  } noraise {
    _ => fail("expected non-negative output limit rejection")
  }

  try
    terminal_output_result_from_json(
      protocol_parse_json(
        "{\"output\":\"x\",\"truncated\":false,\"exitStatus\":{\"exitCode\":4294967296}}",
      ),
    )
  catch {
    InvalidField(path="terminal/output.exitStatus.exitCode", reason=_) => ()
    _ => fail("expected uint32 exit code rejection")
  } noraise {
    _ => fail("expected uint32 exit code rejection")
  }

  try
    terminal_output_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"terminalId\":\"t\",\"unknown\":true}",
      ),
    )
  catch {
    UnknownField(path="terminal/output.unknown") => ()
    _ => fail("expected unknown field rejection")
  } noraise {
    _ => fail("expected unknown field rejection")
  }

  try
    terminal_release_params_to_json({
      session_id: "s",
      terminal_id: "",
      meta: Omitted,
    })
  catch {
    InvalidField(path="terminalId", reason=_) => ()
    _ => fail("expected empty terminal id rejection")
  } noraise {
    _ => fail("expected empty terminal id rejection")
  }
}

///|
test "terminal output byte limits preserve exact uint64 values and reject invalid numbers" {
  let limits : Array[UInt64] = [9007199254740993UL, 18446744073709551615UL]
  for limit in limits {
    let create : TerminalCreateParams = {
      session_id: "session-1",
      command: "printf",
      args: Omitted,
      env: Omitted,
      cwd: Omitted,
      output_byte_limit: Value(limit),
      meta: Omitted,
    }
    assert_eq(
      terminal_create_params_from_json(terminal_create_params_to_json(create)),
      create,
    )
  }

  let invalid : Array[(String, String)] = [
    (
      "{\"sessionId\":\"s\",\"command\":\"echo\",\"outputByteLimit\":1.5}", "terminal/create.outputByteLimit",
    ),
    (
      "{\"sessionId\":\"s\",\"command\":\"echo\",\"outputByteLimit\":18446744073709551616}",
      "terminal/create.outputByteLimit",
    ),
  ]
  for pair in invalid {
    let (source, expected_path) = pair
    try terminal_create_params_from_json(protocol_parse_json(source)) catch {
      InvalidField(path=actual_path, reason=_) =>
        assert_eq(actual_path, expected_path)
      _ => fail("expected invalid terminal uint64 value")
    } noraise {
      _ => fail("expected invalid terminal uint64 value to fail")
    }
  }
}
