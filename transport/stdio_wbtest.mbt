///|
using @runtime {runtime_trace_event}

///|
test "stdio adapter preserves the injected redacted trace sink" {
  let traces : Array[RuntimeTraceEvent] = []
  let handlers : RuntimeHandlerPort = {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => (),
    response: _ => (),
    outbound_failure: None,
  }
  let ports = stdio_transport(handlers, None, event => traces.push(event))
  (ports.trace)(runtime_trace_event("test", "adapter", "", "", ""))
  assert_eq(traces.length(), 1)
}
