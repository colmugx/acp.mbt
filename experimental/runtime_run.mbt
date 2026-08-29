///|
/// Run one v2 Agent connection on the single native owner-loop engine.  This
/// is a thin composition of `connection_runtime_run_owner` with
/// `experimental_v2_agent_runtime_owner_port`: it validates the options
/// fail-fast and creates no connection state of its own.
pub async fn experimental_v2_agent_runtime_run(
  endpoint~ : ExperimentalV2AgentEndpoint,
  context~ : ExperimentalV2AgentContext,
  initial_state~ : ExperimentalV2AgentAdapterState,
  ports~ : @runtime.RuntimePorts,
  options~ : @runtime.RuntimeOptions,
) -> Unit {
  @runtime.runtime_validate_options(options)
  @connection.connection_runtime_run_owner(
    ports,
    options,
    experimental_v2_agent_runtime_owner_port(
      endpoint~,
      context~,
      initial_state~,
    ),
  )
}

///|
/// Run one v2 Agent connection on the single native owner-loop engine with
/// the engine-level outbound channel handed to the Agent context factory.
/// The factory runs after the connection-local queues and shutdown state
/// exist and before the loop starts; it typically builds
/// `experimental_v2_agent_context_over_channel` so handlers running
/// mid-execution can issue reverse requests and stream notifications through
/// the real engine.  This runner adds no second loop or channel state of its
/// own: it validates the options fail-fast and reuses the same single
/// reader/writer/reducer engine as `experimental_v2_agent_runtime_run`.
pub async fn experimental_v2_agent_runtime_run_with_outbound(
  endpoint~ : ExperimentalV2AgentEndpoint,
  context_factory~ : (
    @connection.RuntimeOutboundChannel[ExperimentalV2AgentCompletion],
  ) -> ExperimentalV2AgentContext,
  initial_state~ : ExperimentalV2AgentAdapterState,
  ports~ : @runtime.RuntimePorts,
  options~ : @runtime.RuntimeOptions,
) -> Unit {
  @runtime.runtime_validate_options(options)
  @connection.connection_runtime_run_owner_with_outbound(ports, options, channel => {
    experimental_v2_agent_runtime_owner_port(
      endpoint~,
      context=context_factory(channel),
      initial_state~,
    )
  })
}

///|
/// Serve this process's real stdio as one v2 Agent connection with a fixed
/// outbound context: inbound ACP frames arrive on stdin, outbound frames
/// (including one final response per request) go to stdout, and every
/// diagnostic goes to the trace sink (stderr by default).  This is a thin
/// composition of `experimental_v2_agent_runtime_run` over
/// `runtime_stdio_ports`: it validates the options fail-fast before any I/O
/// binding and creates no connection state of its own.  The loop ends when
/// stdin reaches EOF or the engine fails.  With `batch` the reader port is
/// wrapped by `experimental_v2_batch_expanding_ports`: inbound v2 batch
/// frames are expanded into single-object frames before the shared
/// engine's object-only decode; replies still go out per frame, which the
/// v2 transport rules allow.
pub async fn experimental_v2_agent_serve_stdio(
  endpoint~ : ExperimentalV2AgentEndpoint,
  context~ : ExperimentalV2AgentContext,
  initial_state~ : ExperimentalV2AgentAdapterState,
  options? : @runtime.RuntimeOptions = @runtime.runtime_default_options(),
  trace? : (@runtime.RuntimeTraceEvent) -> Unit = @runtime.runtime_stderr_trace,
  batch? : Bool = false,
) -> Unit {
  @runtime.runtime_validate_options(options)
  experimental_v2_agent_runtime_run(
    endpoint~,
    context~,
    initial_state~,
    ports=experimental_v2_agent_serve_stdio_ports(trace, batch, options),
    options~,
  )
}

///|
/// Serve this process's real stdio as one v2 Agent connection with the
/// engine-level outbound channel handed to the Agent context factory, so
/// handlers running mid-execution can stream `session/update` notifications
/// and issue reverse requests (`session/request_permission`,
/// `elicitation/create`) through the real engine instead of a fail-fast
/// broker.  Without this composition a stdio v2 Agent could answer requests
/// but never exercise the reverse direction of the protocol; the factory
/// timing mirrors `experimental_v2_agent_runtime_run_with_outbound` (after
/// the connection-local queues exist, before the loop starts).  This is a
/// thin composition over `runtime_stdio_ports`: it validates the options
/// fail-fast before any I/O binding and creates no second loop, channel
/// state, or connection state of its own.  The loop ends when stdin reaches
/// EOF or the engine fails.  With `batch` the reader port is wrapped by
/// `experimental_v2_batch_expanding_ports`: inbound v2 batch frames are
/// expanded into single-object frames before the shared engine's object-only
/// decode; replies still go out per frame, which the v2 transport rules
/// allow.
pub async fn experimental_v2_agent_serve_stdio_with_outbound(
  endpoint~ : ExperimentalV2AgentEndpoint,
  context_factory~ : (
    @connection.RuntimeOutboundChannel[ExperimentalV2AgentCompletion],
  ) -> ExperimentalV2AgentContext,
  initial_state~ : ExperimentalV2AgentAdapterState,
  options? : @runtime.RuntimeOptions = @runtime.runtime_default_options(),
  trace? : (@runtime.RuntimeTraceEvent) -> Unit = @runtime.runtime_stderr_trace,
  batch? : Bool = false,
) -> Unit {
  @runtime.runtime_validate_options(options)
  experimental_v2_agent_runtime_run_with_outbound(
    endpoint~,
    context_factory~,
    initial_state~,
    ports=experimental_v2_agent_serve_stdio_ports(trace, batch, options),
    options~,
  )
}

///|
fn experimental_v2_agent_serve_stdio_ports(
  trace : (@runtime.RuntimeTraceEvent) -> Unit,
  batch : Bool,
  options : @runtime.RuntimeOptions,
) -> @runtime.RuntimePorts {
  let ports = @runtime.runtime_stdio_ports(trace~)
  if batch {
    experimental_v2_batch_expanding_ports(ports~, options~)
  } else {
    ports
  }
}

///|
/// Bind one v2 Client endpoint onto the single connection owner-loop engine.
/// The returned port captures only the immutable `endpoint` value; every
/// protocol transition stays inside the engine-owned
/// `ExperimentalV2ClientAdapterState`.  There is no second owner loop,
/// shadow pending map, `Ref`, `Mutex`, or builder surface here.
///
/// Residual `ExperimentalV2ClientAdapterError` values (`EndpointMismatch`,
/// `UnexpectedMessage`, `CompletionMismatch`) indicate composition or
/// protocol bugs, but the owner port closures are total by signature.  Each
/// residual is therefore answered with an explicit typed fallback instead of
/// being swallowed: requests get exactly one internal-error response plus one
/// trace effect, notifications get one trace effect and no response, and the
/// owner state is held unchanged.  The fallback is visible on the wire and in
/// the trace sink; it is never a silent success.
pub fn experimental_v2_client_runtime_owner_port(
  endpoint~ : ExperimentalV2ClientEndpoint,
  initial_state~ : ExperimentalV2ClientAdapterState,
) -> @connection.RuntimeOwnerPort[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientInvocation,
  ExperimentalV2ClientCompletion,
  ExperimentalV2ClientAdapterCommand,
] {
  {
    initial_state,
    admit_request: (state, _id, request) => {
      experimental_v2_client_runtime_request_admission(
        experimental_v2_client_adapter_admit(
          state,
          endpoint,
          @jsonrpc.JsonRpcMessage::request(request),
        ),
      ) catch {
        _ =>
          experimental_v2_client_runtime_request_admission_failure(
            state,
            request.method_name,
          )
      }
    },
    admit_notification: (state, notification) => {
      experimental_v2_client_runtime_notification_admission(
        experimental_v2_client_adapter_admit(
          state,
          endpoint,
          @jsonrpc.JsonRpcMessage::notification(notification),
        ),
      ) catch {
        _ =>
          RuntimeOwnerNotificationImmediate(
            completion=experimental_v2_client_runtime_trace_completion(
              state,
              notification.method_name,
            ),
          )
      }
    },
    execute: invocation => experimental_v2_client_execute(invocation, endpoint),
    execute_failure: (_state, invocation) => {
      experimental_v2_client_failure_completion(invocation)
    },
    execute_cancel: (_state, invocation) => {
      experimental_v2_client_cancel_completion(invocation)
    },
    complete_request: (state, _id, invocation, completion) => {
      experimental_v2_client_runtime_request_completion(
        experimental_v2_client_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          experimental_v2_client_runtime_complete_failure(
            state,
            experimental_v2_client_invocation_method_name(invocation),
          )
      }
    },
    complete_notification: (state, invocation, completion) => {
      experimental_v2_client_runtime_notification_completion(
        experimental_v2_client_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          experimental_v2_client_runtime_trace_completion(
            state,
            experimental_v2_client_invocation_method_name(invocation),
          )
      }
    },
    plan_local_effect: command => {
      match command {
        CancelRequest(request_id~) =>
          RuntimeOwnerCommands([
            RuntimeOwnerCancelInbound(
              request_id=experimental_v2_client_cancel_inbound_id(request_id),
            ),
          ])
        // The `JsonRpcError` payload intentionally does not cross this
        // boundary: the runtime trace seam carries the method name only.
        TraceError(method_name~, error=_) =>
          RuntimeOwnerCommands([RuntimeOwnerTrace(method_name~)])
      }
    },
    cancel_request: (state, _id, invocation) => {
      (state, experimental_v2_client_cancel_completion(invocation))
    },
    // Client adapter state carries no reservation: close keeps the last
    // committed protocol snapshot exactly as the owner recorded it.
    abort: (state, _task) => state,
  }
}

///|
fn experimental_v2_client_cancel_inbound_id(
  request_id : ExperimentalV2RequestId,
) -> @jsonrpc.RequestId {
  match request_id {
    RequestIdNull => Null
    RequestIdNumber(number) => Number(number)
    RequestIdStr(text) => String(text)
  }
}

///|
/// Run one v2 Client connection on the single native owner-loop engine.
/// This is a thin composition of `connection_runtime_run_owner` with
/// `experimental_v2_client_runtime_owner_port`: it validates the options
/// fail-fast and creates no connection state of its own.
pub async fn experimental_v2_client_runtime_run(
  endpoint~ : ExperimentalV2ClientEndpoint,
  initial_state~ : ExperimentalV2ClientAdapterState,
  ports~ : @runtime.RuntimePorts,
  options~ : @runtime.RuntimeOptions,
) -> Unit {
  @runtime.runtime_validate_options(options)
  @connection.connection_runtime_run_owner(
    ports,
    options,
    experimental_v2_client_runtime_owner_port(endpoint~, initial_state~),
  )
}

///|
/// Run one v2 Client connection on the single native owner-loop engine with
/// the engine-level outbound channel handed to the Client endpoint factory.
/// The factory runs after the connection-local queues and shutdown state
/// exist and before the loop starts, mirroring the Agent bridge's context
/// factory timing.  The factory typically builds
/// `experimental_v2_client_connection_over_channel` and closes over it so
/// service handlers can answer through the real engine; this file stays
/// independent of what the factory builds.
pub async fn experimental_v2_client_runtime_run_with_outbound(
  endpoint_factory~ : (
    @connection.RuntimeOutboundChannel[ExperimentalV2ClientCompletion],
  ) -> ExperimentalV2ClientEndpoint,
  initial_state~ : ExperimentalV2ClientAdapterState,
  ports~ : @runtime.RuntimePorts,
  options~ : @runtime.RuntimeOptions,
) -> Unit {
  @runtime.runtime_validate_options(options)
  @connection.connection_runtime_run_owner_with_outbound(ports, options, channel => {
    experimental_v2_client_runtime_owner_port(
      endpoint=endpoint_factory(channel),
      initial_state~,
    )
  })
}

///|
/// Drive one spawned v2 Agent subprocess as a Client connection over real
/// process stdio.  The child's stdin/stdout become the engine's writer/reader
/// ports (frames flushed per write), the child's stderr is redirected to this
/// process's stderr, and diagnostics go to the trace sink (stderr by
/// default).  This is a thin composition of
/// `experimental_v2_client_runtime_run_with_outbound` over
/// `runtime_process_ports`; it validates the options fail-fast before
/// spawning and reuses the same single reader/writer/reducer engine.
///
/// Connection scope equals child scope, mirroring the v1 process runner: the
/// composition opens one task group, spawns the child inside it with
/// `no_wait = true`, runs the engine, then closes the child's stdin — the ACP
/// stdio shutdown signal — before group teardown.  The optional `spawned`
/// callback receives the real `RuntimeProcessPorts` handle right after the
/// spawn succeeds and before the engine starts, so a composition root (or
/// test driver) can close the child's stdin, wait for the exit status, or
/// cancel the child at the moment its session logic decides to.  With
/// `batch` the child's stdout reader is wrapped by
/// `experimental_v2_batch_expanding_ports`, so a v2 agent that batches its
/// replies still settles one reply per request through the shared engine.
pub async fn experimental_v2_client_connect_process(
  endpoint_factory~ : (
    @connection.RuntimeOutboundChannel[ExperimentalV2ClientCompletion],
  ) -> ExperimentalV2ClientEndpoint,
  initial_state~ : ExperimentalV2ClientAdapterState,
  handlers~ : @runtime.RuntimeHandlerPort,
  command~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String],
  inherit_env? : Bool = true,
  spawned? : (@runtime.RuntimeProcessPorts) -> Unit = _ => (),
  options? : @runtime.RuntimeOptions = @runtime.runtime_default_options(),
  trace? : (@runtime.RuntimeTraceEvent) -> Unit = @runtime.runtime_stderr_trace,
  batch? : Bool = false,
) -> Unit {
  @runtime.runtime_validate_options(options)
  @async.with_task_group(group => {
    let spawned_ports = @runtime.runtime_process_ports(
      group,
      handlers~,
      command~,
      args~,
      extra_env?,
      inherit_env~,
      trace~,
    )
    spawned(spawned_ports)
    defer spawned_ports.child_stdin.close()
    experimental_v2_client_runtime_run_with_outbound(
      endpoint_factory~,
      initial_state~,
      ports=if batch {
        experimental_v2_batch_expanding_ports(
          ports=spawned_ports.ports,
          options~,
        )
      } else {
        spawned_ports.ports
      },
      options~,
    )
  })
}

///|
fn experimental_v2_client_runtime_request_admission(
  admission : ExperimentalV2ClientAdmission,
) -> @connection.RuntimeOwnerRequestAdmission[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientInvocation,
  ExperimentalV2ClientAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerRequestImmediate(
        completion=experimental_v2_client_runtime_request_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerRequestInvoke(state~, invocation~)
  }
}

///|
fn experimental_v2_client_runtime_notification_admission(
  admission : ExperimentalV2ClientAdmission,
) -> @connection.RuntimeOwnerNotificationAdmission[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientInvocation,
  ExperimentalV2ClientAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerNotificationImmediate(
        completion=experimental_v2_client_runtime_notification_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerNotificationInvoke(state~, invocation~)
  }
}

///|
/// Fold one adapter step into exactly one wire result plus ordered owner
/// effects.  A request step carrying zero or multiple responses is an
/// adapter bug and fails fast instead of guessing a wire result.  The v2
/// Client adapter has no wire-notification output, so every non-response
/// output is a local command effect.
fn experimental_v2_client_runtime_request_completion(
  step : ExperimentalV2ClientAdapterStep,
) -> @connection.RuntimeOwnerRequestCompletion[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientAdapterCommand,
] {
  let mut response : @runtime.RuntimeHandlerResult? = None
  let effects : Array[
    @connection.RuntimeOwnerEffect[ExperimentalV2ClientAdapterCommand],
  ] = []
  for output in step.outputs {
    match output {
      Response(value) =>
        if response is Some(_) {
          abort(
            "v2 client adapter request step must carry exactly one response",
          )
        } else {
          response = Some(
            match value {
              Success(success) => HandlerSuccess(success.result)
              Error(failure) => HandlerError(failure.error)
            },
          )
        }
      Command(command) => effects.push(Local(effect=command))
    }
  }
  match response {
    Some(response) => { state: step.state, response, effects, }
    None => abort("v2 client adapter request step must carry one response")
  }
}

///|
/// Notification steps never carry a response; a `Response` here is an adapter
/// bug and fails fast rather than synthesizing a wire reply.  As on the
/// request side, the v2 Client adapter produces local command effects only.
fn experimental_v2_client_runtime_notification_completion(
  step : ExperimentalV2ClientAdapterStep,
) -> @connection.RuntimeOwnerNotificationCompletion[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientAdapterCommand,
] {
  let effects : Array[
    @connection.RuntimeOwnerEffect[ExperimentalV2ClientAdapterCommand],
  ] = []
  for output in step.outputs {
    match output {
      Response(_) =>
        abort("v2 client adapter notification step must not carry a response")
      Command(command) => effects.push(Local(effect=command))
    }
  }
  { state: step.state, effects, }
}

///|
fn experimental_v2_client_runtime_trace_effects(
  method_name : String,
) -> Array[@connection.RuntimeOwnerEffect[ExperimentalV2ClientAdapterCommand]] {
  [
    Local(
      effect=TraceError(
        method_name~,
        error=@jsonrpc.JsonRpcError::internal_error(),
      ),
    ),
  ]
}

///|
/// Total typed fallback for a residual adapter failure on the notification
/// side: one trace effect, no response, state unchanged.
fn experimental_v2_client_runtime_trace_completion(
  state : ExperimentalV2ClientAdapterState,
  method_name : String,
) -> @connection.RuntimeOwnerNotificationCompletion[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientAdapterCommand,
] {
  { state, effects: experimental_v2_client_runtime_trace_effects(method_name), }
}

///|
/// Total typed fallback for a residual adapter failure during request
/// admission: exactly one internal-error response plus one trace effect,
/// state unchanged.
fn experimental_v2_client_runtime_request_admission_failure(
  state : ExperimentalV2ClientAdapterState,
  method_name : String,
) -> @connection.RuntimeOwnerRequestAdmission[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientInvocation,
  ExperimentalV2ClientAdapterCommand,
] {
  RuntimeOwnerRequestImmediate(completion={
    state,
    response: HandlerError(@jsonrpc.JsonRpcError::internal_error()),
    effects: experimental_v2_client_runtime_trace_effects(method_name),
  })
}

///|
/// Total typed fallback for a residual adapter failure during request
/// completion: exactly one internal-error response plus one trace effect,
/// state unchanged.  Same policy as the admission fallback.
fn experimental_v2_client_runtime_complete_failure(
  state : ExperimentalV2ClientAdapterState,
  method_name : String,
) -> @connection.RuntimeOwnerRequestCompletion[
  ExperimentalV2ClientAdapterState,
  ExperimentalV2ClientAdapterCommand,
] {
  {
    state,
    response: HandlerError(@jsonrpc.JsonRpcError::internal_error()),
    effects: experimental_v2_client_runtime_trace_effects(method_name),
  }
}
