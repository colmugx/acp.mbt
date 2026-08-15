///|
/// The spawned-agent handle handed back with client-side process ports.  The
/// `ports` value drives the single connection engine; `child`, `child_stdin`,
/// and `child_stdout` expose the real `moonbitlang/async` process seams so a
/// composition root can close the child's stdin (the ACP stdio shutdown
/// signal), wait for the exit status, or cancel the child without any wrapper
/// API duplicating the underlying library.
pub(all) struct RuntimeProcessPorts {
  ports : RuntimePorts
  child : @process.Process
  child_stdin : @process.WriteToProcess
  child_stdout : @process.ReadFromProcess
}

///|
/// Construct the client side of one ACP stdio connection over a spawned child
/// process.  The child's stdin is the writer target and its stdout is the
/// reader source; the child's stderr is redirected to this process's real
/// stderr so agent diagnostics stay diagnostics and stdout stays pure frames.
/// Both pipe ends are raw, unbuffered `@process` handles, so every frame
/// write is delivered to the operating system in that call — the pinned
/// flush-per-write discipline, structurally identical to
/// `runtime_stdio_ports`.
///
/// The child is spawned with `no_wait = true` inside the caller's task group:
/// when the group terminates, the async process layer cancels its wait task,
/// which gracefully terminates the child (then forcefully after its timeout)
/// and reaps it.  Child lifetime is therefore bound to the structured
/// concurrency scope that owns the connection — no background reaper loop, no
/// detached process.  A well-behaved agent additionally observes the stdin EOF
/// a composition sends through `child_stdin.close()` before teardown.
///
/// Fail-fast mapping (the closed stable `RuntimeError` set has no process
/// category, so each failure keeps its precise kind in the trace, mirroring
/// the documented closest-category mapping of the outbound channel):
/// an empty command is rejected as `InvalidOptions` before any OS call; a
/// failed stdout pipe is `ReaderFailed` and a failed stdin pipe is
/// `WriterFailed` (the seam that could not be constructed); an OS spawn
/// rejection — including a missing command — is `InvalidOptions` with trace
/// kind `process_spawn_failed`, because the caller's process configuration
/// was rejected before any I/O seam ever ran.  Every failure is typed and
/// accompanied by one trace event; nothing degrades silently.
pub async fn[G] runtime_process_ports(
  group : @async.TaskGroup[G],
  handlers~ : RuntimeHandlerPort,
  command~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String],
  inherit_env? : Bool = true,
  cancel_outbound? : RuntimeCancelOutboundHandler? = None,
  trace? : (RuntimeTraceEvent) -> Unit = runtime_stderr_trace,
) -> RuntimeProcessPorts raise RuntimeError {
  if command.is_empty() {
    trace(
      runtime_trace_event(
        "runtime", "process_spawn_rejected", "", "", "process_command_invalid",
      ),
    )
    raise InvalidOptions
  }
  let (child_stdin_end, child_stdin) = @process.write_to_process() catch {
    _ => {
      trace(
        runtime_trace_event(
          "runtime", "process_spawn_rejected", "", "", "process_stdin_pipe_failed",
        ),
      )
      raise WriterFailed
    }
  }
  let (child_stdout, child_stdout_end) = @process.read_from_process() catch {
    _ => {
      child_stdin.close()
      trace(
        runtime_trace_event(
          "runtime", "process_spawn_rejected", "", "", "process_stdout_pipe_failed",
        ),
      )
      raise ReaderFailed
    }
  }
  let child = @process.spawn(
    group,
    command,
    args,
    extra_env?,
    inherit_env~,
    stdin=child_stdin_end,
    stdout=child_stdout_end,
    stderr=@stdio.stderr,
    no_wait=true,
  ) catch {
    _ => {
      child_stdin.close()
      child_stdout.close()
      trace(
        runtime_trace_event(
          "runtime", "process_spawn_rejected", "", "", "process_spawn_failed",
        ),
      )
      raise InvalidOptions
    }
  }
  {
    ports: {
      reader: { read: max_len => child_stdout.read_some(max_len~) },
      writer: { write: frame => child_stdin.write(frame) },
      handlers,
      cancel_outbound,
      trace,
    },
    child,
    child_stdin,
    child_stdout,
  }
}
