///|
/// SDK-scope acceptance tests for row G01 of
/// docs/implementation-plan/04-v1-completeness-matrix.md at the session wire
/// surface owned by this package.

///|
/// Row G01: cwd is the always-present primary root and additionalDirectories
/// ride the wire as an ordered array.  The codec preserves the exact order for
/// every session method that carries roots, and rejects one relative member
/// with its indexed path.  Boundary: assembling the effective ordered root
/// list ([cwd] followed by additionalDirectories) for permission checks is
/// application/service scope; the SDK guarantees the wire surface stays
/// ordered, absolute, and capability-gated (agent protocol state denies
/// additionalDirectories without the advertised marker).
test "matrix G01 additional directories keep exact wire order per method" {
  let ordered = ["/workspace", "/vault/cache", "/logs"]
  let new_params : NewSessionParams = {
    cwd: "/workspace",
    additional_directories: Value(ordered),
    mcp_servers: [],
    meta: Omitted,
  }
  assert_eq(
    new_session_params_from_json(new_session_params_to_json(new_params)).additional_directories,
    Value(ordered),
  )
  let load_params : LoadSessionParams = {
    mcp_servers: [],
    cwd: "/workspace",
    additional_directories: Value(ordered),
    session_id: "s",
    meta: Omitted,
  }
  assert_eq(
    load_session_params_from_json(load_session_params_to_json(load_params)).additional_directories,
    Value(ordered),
  )
  let resume_params : ResumeSessionParams = {
    session_id: "s",
    cwd: "/workspace",
    additional_directories: Value(ordered),
    mcp_servers: Omitted,
    meta: Omitted,
  }
  assert_eq(
    resume_session_params_from_json(
      resume_session_params_to_json(resume_params),
    ).additional_directories,
    Value(ordered),
  )
  let fork_params : ForkSessionParams = {
    cwd: "/workspace",
    session_id: "s",
    additional_directories: Value(ordered),
    mcp_servers: Omitted,
    meta: Omitted,
  }
  assert_eq(
    fork_session_params_from_json(fork_session_params_to_json(fork_params)).additional_directories,
    Value(ordered),
  )
  try
    new_session_params_from_json(
      protocol_parse_json(
        "{\"cwd\":\"/workspace\",\"additionalDirectories\":[\"/ok\",\"relative\"],\"mcpServers\":[]}",
      ),
    )
  catch {
    InvalidPath(path="session/new.additionalDirectories[1]", value="relative") =>
      ()
    _ => fail("expected indexed relative root rejection")
  } noraise {
    _ => fail("expected roots decoding to fail")
  }
}
