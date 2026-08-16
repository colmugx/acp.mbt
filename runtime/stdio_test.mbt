///|
/// Redaction proof for the default diagnostics format: a peer-supplied
/// request id or method name carrying newlines, tabs, NUL bytes, or non-ASCII
/// text can never forge additional trace lines or frame-like content.  The
/// rendered line carries all five trace fields in fixed order and ends with
/// exactly one newline.
test "stderr trace line renders one sanitized line per event" {
  let event = runtime_trace_event(
    "outbound", "phase\ninjected", "id\u{0000}probe", "method\ttab", "writer_failed",
  )
  let line = runtime_trace_stderr_line(event)
  assert_true(line.has_suffix("\n"))
  let mut newlines = 0
  for ch in line {
    if ch == '\n' {
      newlines = newlines + 1
    }
  }
  assert_eq(newlines, 1)
  assert_true(line.contains("direction=outbound"))
  assert_true(line.contains("phase=phase?injected"))
  assert_true(line.contains("request_id=id?probe"))
  assert_true(line.contains("method=method?tab"))
  assert_true(line.contains("error=writer_failed"))
  let unicode = runtime_trace_stderr_line(
    runtime_trace_event("inbound", "p", "i", "méthode", "e"),
  )
  assert_true(unicode.contains("method=m?thode"))
}

///|
/// Row G07 stdout purity, structural half: a rendered diagnostics line can
/// never parse as a JSON value, so even a misrouted diagnostics write could
/// never be mistaken for an ACP frame on the protocol channel.  The line for
/// a routing decision still carries the method name and, where one exists,
/// the request id — both sanitized.
test "trace lines carry routing fields but never parse as protocol frames" {
  let lines = [
    runtime_trace_stderr_line(
      runtime_trace_event(
        "inbound", "cancel_requested", "42", "$/cancel_request", "cancel",
      ),
    ),
    runtime_trace_stderr_line(
      runtime_trace_event(
        "runtime", "owner_trace", "", "session/update", "owner",
      ),
    ),
    runtime_trace_stderr_line(
      runtime_trace_event("outbound", "writer_written", "", "", ""),
    ),
  ]
  for line in lines {
    assert_true(line.has_suffix("\n"))
    let parsed = try @json.parse(line) catch {
      _ => None
    } noraise {
      value => Some(value)
    }
    assert_true(parsed is None)
  }
  assert_true(lines[0].contains("request_id=42"))
  assert_true(lines[0].contains("method=$/cancel_request"))
  assert_true(lines[1].contains("method=session/update"))
}

///|
/// The stdio port constructor binds the real process descriptors without
/// performing any I/O of its own, and its trace seam — default or injected —
/// is a total synchronous closure.  Invoking the default sink exercises the
/// real raw stderr write; nothing on this path can reach stdout, whose only
/// writer in this package is the frame writer of `runtime_stdio_ports`
/// itself.  The reader/writer closures over the real descriptors are the
/// same `read_some`/`write` shapes proven end-to-end over a real child
/// process in `process_test.mbt`.
test "runtime_stdio_ports binds real stdio with a total default trace" {
  let ports = runtime_stdio_ports()
  (ports.trace)(runtime_trace_event("runtime", "constructed", "", "", ""))
  let observed : Array[String] = []
  let traced = runtime_stdio_ports(trace=event => observed.push(event.phase))
  (traced.trace)(runtime_trace_event("runtime", "observed", "", "", ""))
  assert_eq(observed, ["observed"])
}

///|
/// Proof that the synchronous diagnostics writer really writes bytes through
/// a file descriptor: the same `runtime_libc_write` used for the default
/// stderr sink writes a rendered trace line into the write end of a real
/// pipe, and every byte comes back byte-identical on the read end.  This is
/// the exact syscall path `runtime_stderr_trace` takes against fd 2.
async test "raw trace writer delivers bytes through a real file descriptor" {
  let (reader, writer) = @async_pipe.pipe()
  defer reader.close()
  let line = @utf8.encode(
    runtime_trace_stderr_line(
      runtime_trace_event("outbound", "writer_written", "", "", ""),
    ),
  )
  let written = runtime_libc_write(writer.fd(), line, line.length())
  assert_eq(written, line.length())
  // The write end must close before draining: EOF is the only terminator the
  // reader accepts, mirroring how the default sink's fd-2 writes are
  // unbuffered and complete in one call.
  writer.close()
  let received : Array[Byte] = []
  while true {
    match reader.read_some(max_len=line.length()) {
      None => break
      Some(chunk) =>
        for i in 0..<chunk.length() {
          received.push(chunk[i])
        }
    }
  }
  assert_eq(received.length(), line.length())
  for i in 0..<line.length() {
    assert_eq(received[i], line[i])
  }
}
