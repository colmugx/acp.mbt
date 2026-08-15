///|
/// Composition fail-fast for the agent stdio runner: invalid runtime options
/// are rejected before any stdio binding or stdin read happens.  The error
/// channel of the runner is the engine's untyped boundary (cancellation must
/// flow through it), so this level proves the visible failure; the typed
/// `InvalidOptions` constructor is proven at `runtime_validate_options` and
/// at the typed `runtime_process_ports` seam in the runtime suite.  If the
/// validation ever stopped raising, the runner would start serving the real
/// process stdin and this test would observe `raised` empty and fail.
async test "agent_serve_stdio validates options before binding stdio" {
  let endpoint = agent_adapter_test_endpoint()
  let raised : Array[Unit] = []
  try {
    agent_serve_stdio(
      endpoint~,
      context=agent_context(
        request_broker=_request => {
          Err(AgentContextBrokerFailure(method_name="session/new"))
        },
        notification_broker=_notification => {
          Err(AgentContextBrokerFailure(method_name="session/update"))
        },
      ),
      initial_state=agent_adapter_test_state(endpoint),
      options={ ..@runtime.runtime_default_options(), max_frame_bytes: 0 },
      trace=_ => (),
    )
    ()
  } catch {
    _ => raised.push(())
  }
  assert_eq(raised.length(), 1)
}
