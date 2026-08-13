///|
using @runtime {
  type RuntimeCancelOutboundHandler,
  type RuntimeHandlerPort,
  type RuntimeTraceEvent,
  type RuntimePorts,
}

///|
/// Thin native stdio adapter. The caller supplies the handler and redacted
/// trace sink; this adapter never writes diagnostics to stdout.
pub fn stdio_transport(
  handlers : RuntimeHandlerPort,
  cancel_outbound : RuntimeCancelOutboundHandler?,
  trace : (RuntimeTraceEvent) -> Unit,
) -> RuntimePorts {
  {
    reader: { read: max_len => @stdio.stdin.read_some(max_len~) },
    writer: { write: frame => @stdio.Output::write(@stdio.stdout, frame) },
    handlers,
    cancel_outbound,
    trace,
  }
}
