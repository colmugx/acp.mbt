///|
/// Synchronous diagnostics write over the raw `write(2)` symbol.  The runtime
/// trace seam is a plain synchronous closure, so the default stderr sink
/// cannot go through the async event loop; it goes straight to libc instead,
/// exactly like the `close` binding in `moonbitlang/async` itself.  The buffer
/// is borrowed: `write(2)` reads it during the call and never stores it.
#borrow(buffer)
extern "C" fn runtime_libc_write_ffi(
  fd : Int,
  buffer : Bytes,
  count : Int,
) -> Int = "write"

///|
/// Public wrapper over the raw diagnostics writer so the blackbox suite can
/// prove the byte path against a real pipe.  Not exported through the stable
/// facade.
pub fn runtime_libc_write(fd : Int, buffer : Bytes, count : Int) -> Int {
  runtime_libc_write_ffi(fd, buffer, count)
}

///|
/// File descriptor of the standard error stream on every POSIX target.
let runtime_stderr_fd : Int = 2

///|
/// Reduce one trace field to printable ASCII.  Any control character,
/// including a newline smuggled into a peer-supplied request id or method
/// name, becomes `?`, so one trace event can never be forged into several
/// lines or into frame-like content on the diagnostics channel.
fn runtime_trace_sanitize(value : String) -> String {
  let buffer = StringBuilder::new()
  for ch in value {
    if ch >= '\u{20}' && ch <= '\u{7e}' {
      buffer.write_char(ch)
    } else {
      buffer.write_char('?')
    }
  }
  buffer.to_string()
}

///|
/// Render one redacted trace event as exactly one diagnostics line ending in
/// a single newline.  The five trace fields keep their fixed order; every
/// value is sanitized first.  This renderer is the exact text the default
/// stderr sink writes, which keeps the diagnostics format unit-testable.
pub fn runtime_trace_stderr_line(event : RuntimeTraceEvent) -> String {
  "acp direction=" +
  runtime_trace_sanitize(event.direction) +
  " phase=" +
  runtime_trace_sanitize(event.phase) +
  " request_id=" +
  runtime_trace_sanitize(event.request_id) +
  " method=" +
  runtime_trace_sanitize(event.method_name) +
  " error=" +
  runtime_trace_sanitize(event.error_kind) +
  "\n"
}

///|
/// Static kind text for one outbound failure category.  The closed stable
/// `RuntimeError` set has no per-failure-kind strings, so the sink carries the
/// precise category here the same way the connection runtime carries it in
/// its own trace kinds.
fn runtime_outbound_failure_kind_text(
  kind : RuntimeOutboundFailureKind,
) -> String {
  match kind {
    Protocol => "protocol"
    Framing => "framing"
    Reader => "reader"
    Writer => "writer"
    Handler => "handler"
    Notification => "notification"
    EndOfInput => "end_of_input"
    EventQueue => "event_queue"
    Runtime => "runtime"
  }
}

///|
/// Best-effort synchronous write of one diagnostics record to a file
/// descriptor.  Returns the number of bytes accepted by the OS.  The sink has
/// no failure channel by type, so the raw result stays observable for tests
/// instead of being swallowed.
fn runtime_trace_write_line(fd : Int, line : String) -> Int {
  let data = @utf8.encode(line)
  runtime_libc_write(fd, data, data.length())
}

///|
/// Default trace sink: one `write(2)` per event to the real standard error.
/// Stdout is never touched here, so the protocol channel keeps carrying
/// newline-delimited ACP frames only.  The sink type
/// `(RuntimeTraceEvent) -> Unit` has no failure channel: when the OS rejects a
/// diagnostics write (for example a closed stderr under a daemon supervisor),
/// the event is dropped without inventing a failure the trace contract cannot
/// carry.  Protocol I/O failures stay fully typed at the reader/writer seams.
pub let runtime_stderr_trace : (RuntimeTraceEvent) -> Unit = event => {
  ignore(
    runtime_trace_write_line(
      runtime_stderr_fd,
      runtime_trace_stderr_line(event),
    ),
  )
}

///|
/// Serve the native ACP stdio boundary of this process.  The reader reads the
/// real stdin chunk-wise (`None` is EOF, non-empty chunks only, exactly the
/// `RuntimeReaderPort` contract).  The writer writes each complete
/// newline-delimited frame to the real stdout in one `Output::write` call:
/// `@stdio.Output` wraps the raw file descriptor with no userspace buffering
/// (`moonbitlang/async/src/stdio/stdio.mbt`), so every write is handed to the
/// operating system immediately — the pinned flush-per-write discipline holds
/// structurally because no buffered writer layer exists on this path.
///
/// The handler seams exist only for engine runners with an outbound channel.
/// `response` and `outbound_failure` are deliberate no-op observers: reply
/// delivery to parked submitters is owned by the engine's outbound channel,
/// never by these callbacks.  The legacy dispatch seams (`request`,
/// `notification`) abort fail-fast: these ports exist for owner-loop runners,
/// and a legacy handler dispatch through them would silently answer nothing,
/// so it must crash loudly instead.
///
/// Diagnostics go to the trace sink, defaulting to stderr.  Nothing in this
/// constructor writes to stdout, and it performs no I/O at all beyond binding
/// the process file descriptors.
pub fn runtime_stdio_ports(
  trace? : (RuntimeTraceEvent) -> Unit = runtime_stderr_trace,
) -> RuntimePorts {
  {
    reader: { read: max_len => @stdio.stdin.read_some(max_len~) },
    writer: { write: frame => @stdio.stdout.write(frame) },
    handlers: {
      request: _ => {
        abort(
          "runtime stdio ports serve owner-loop runners; legacy request dispatch is unreachable",
        )
      },
      notification: _ => {
        abort(
          "runtime stdio ports serve owner-loop runners; legacy notification dispatch is unreachable",
        )
      },
      response: _ => (),
      outbound_failure: Some((id, failure) => {
        trace(
          runtime_trace_event(
            "outbound",
            "outbound_failed",
            runtime_request_id_text(id),
            "",
            runtime_outbound_failure_kind_text(failure.reason),
          ),
        )
      }),
    },
    cancel_outbound: None,
    trace,
  }
}
