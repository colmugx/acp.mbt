///|
/// Inert handler seams for direct port-level tests: no engine runs here, so
/// the request/notification/response seams are never invoked.
fn runtime_process_test_handlers() -> RuntimeHandlerPort {
  {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => (),
    response: _ => (),
    outbound_failure: None,
  }
}

///|
fn runtime_process_test_traces() -> Array[RuntimeTraceEvent] {
  []
}

///|
/// Collect exactly `want` bytes from a real reader port and compare them
/// byte-for-byte with the expected frame.  `read_some` returns as soon as any
/// data is available, so a frame may legally arrive in several chunks; EOF
/// before completion, or excess bytes, fail the test instead of guessing.
async fn runtime_process_test_read_exact(
  reader : RuntimeReaderPort,
  want : Int,
  expected : Bytes,
) -> Unit {
  let received = FixedArray::make(want, b'\x00')
  let mut filled = 0
  while filled < want {
    match (reader.read)(want - filled) {
      None => fail("process reader reached EOF before the frame was complete")
      Some(chunk) =>
        for i in 0..<chunk.length() {
          if filled >= want {
            fail("process reader delivered more bytes than one frame")
          }
          received[filled] = chunk[i]
          filled = filled + 1
        }
    }
  }
  for i in 0..<want {
    assert_eq(received[i], expected[i])
  }
}

///|
/// Real subprocess round-trip over `/bin/cat`: one complete newline frame is
/// written through the constructed writer port, echoed by the real child
/// process, and read back byte-identical through the constructed reader port.
/// Closing our end of the child's stdin is the ACP shutdown signal: `cat`
/// exits on that EOF, the reader then observes EOF (`None`), and the child is
/// reaped with exit status 0 before the scope ends.
async test "process ports round-trip one frame through /bin/cat and reap the child" {
  @async.with_task_group(group => {
    let spawned = runtime_process_ports(
      group,
      handlers=runtime_process_test_handlers(),
      command="/bin/cat",
      trace=_ => (),
    )
    let frame_text = "{\"jsonrpc\":\"2.0\",\"id\":\"probe\",\"method\":\"session/update\"}\n"
    let frame = @utf8.encode(frame_text)
    (spawned.ports.writer.write)(frame)
    runtime_process_test_read_exact(spawned.ports.reader, frame.length(), frame)
    spawned.child_stdin.close()
    match (spawned.ports.reader.read)(1) {
      None => ()
      Some(_) => fail("reader must observe EOF once the child exited")
    }
    let status = spawned.child.wait()
    assert_eq(status, 0)
  })
}

///|
/// Spawn rejection, first shape: an empty command is refused by pure
/// validation with the typed `InvalidOptions` error and one trace record,
/// before any pipe or process is created.
async test "process ports reject an empty command before any spawn" {
  let traces = runtime_process_test_traces()
  let raised : Array[Unit] = []
  let unexpected : Array[Unit] = []
  @async.with_task_group(group => {
    try {
      let _ : RuntimeProcessPorts = runtime_process_ports(
        group,
        handlers=runtime_process_test_handlers(),
        command="",
        trace=event => traces.push(event),
      )
      ()
    } catch {
      error =>
        match error {
          InvalidOptions => raised.push(())
          _ => unexpected.push(())
        }
    }
  })
  assert_eq(raised.length(), 1)
  assert_eq(unexpected.length(), 0)
  assert_true(
    traces.any(event => event.error_kind == "process_command_invalid"),
  )
}

///|
/// Spawn rejection, second shape: the OS refuses a nonexistent command and
/// the failure surfaces as a typed error with one trace record carrying the
/// precise `process_spawn_failed` kind; no partial ports value escapes.
async test "process ports surface an OS spawn rejection as a typed error" {
  let traces = runtime_process_test_traces()
  let raised : Array[Unit] = []
  let unexpected : Array[Unit] = []
  @async.with_task_group(group => {
    try {
      let _ : RuntimeProcessPorts = runtime_process_ports(
        group,
        handlers=runtime_process_test_handlers(),
        command="/nonexistent/acp-spawn-probe",
        trace=event => traces.push(event),
      )
      ()
    } catch {
      error =>
        match error {
          InvalidOptions => raised.push(())
          _ => unexpected.push(())
        }
    }
  })
  assert_eq(raised.length(), 1)
  assert_eq(unexpected.length(), 0)
  assert_true(traces.any(event => event.error_kind == "process_spawn_failed"))
}

///|
/// Reap/kill semantics: a child that is still running when the connection
/// scope ends is terminated by the async process layer's graceful
/// cancellation (SIGTERM, then SIGKILL after its timeout) and reaped before
/// `with_task_group` returns — the group cannot finish while the child is
/// still alive or unreaped, and this test completes far faster than the
/// child's own 30-second lifetime.  The wait task ends cancelled by that
/// teardown, which is observable as a cancellation error from `wait()`.
async test "process ports kill and reap a live child when the scope ends" {
  let children : Array[@process.Process] = []
  @async.with_task_group(group => {
    let spawned = runtime_process_ports(
      group,
      handlers=runtime_process_test_handlers(),
      command="/bin/sleep",
      args=["30"],
      trace=_ => (),
    )
    children.push(spawned.child)
    ()
  })
  let cancelled : Array[Unit] = []
  try {
    let _ : Int = children[0].wait()
    ()
  } catch {
    _ => cancelled.push(())
  }
  assert_eq(cancelled.length(), 1)
}
