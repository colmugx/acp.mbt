///|
using @connection {
  type RuntimeOutboundChannel,
  type RuntimeOwnerEffect,
  type RuntimeOwnerNotificationAdmission,
  type RuntimeOwnerNotificationCompletion,
  type RuntimeOwnerPort,
  type RuntimeOwnerRequestAdmission,
  type RuntimeOwnerRequestCompletion,
  connection_runtime_run_owner,
  connection_runtime_run_owner_with_outbound,
}

///|
using @runtime {
  type RuntimeHandlerPort,
  type RuntimeHandlerResult,
  type RuntimeOptions,
  type RuntimePorts,
  type RuntimeProcessPorts,
  type RuntimeTraceEvent,
  runtime_default_options,
  runtime_process_ports,
  runtime_stderr_trace,
  runtime_validate_options,
}

///|
/// Bind one Client endpoint onto the single connection owner-loop engine.
/// The returned port captures only the immutable `endpoint` value; every
/// protocol transition stays inside the engine-owned `ClientAdapterState`.
/// There is no second owner loop, shadow pending map, `Ref`, `Mutex`, or
/// builder surface here.
///
/// Residual `ClientAdapterError` values (`EndpointMismatch`,
/// `UnexpectedMessage`, `CompletionMismatch`) indicate composition or
/// protocol bugs, but the owner port closures are total by signature.  Each
/// residual is therefore answered with an explicit typed fallback instead of
/// being swallowed: requests get exactly one internal-error response plus one
/// trace effect, notifications get one trace effect and no response, and the
/// owner state is held unchanged.  The fallback is visible on the wire and in
/// the trace sink; it is never a silent success.
pub fn client_runtime_owner_port(
  endpoint~ : ClientEndpoint,
  initial_state~ : ClientAdapterState,
) -> RuntimeOwnerPort[
  ClientAdapterState,
  ClientAdapterInvocation,
  ClientAdapterCompletion,
  ClientAdapterCommand,
] {
  {
    initial_state,
    admit_request: (state, _id, request) => {
      client_runtime_request_admission(
        client_adapter_admit(state, endpoint, JsonRpcMessage::request(request)),
      ) catch {
        _ =>
          client_runtime_request_admission_failure(state, request.method_name)
      }
    },
    admit_notification: (state, notification) => {
      client_runtime_notification_admission(
        client_adapter_admit(
          state,
          endpoint,
          JsonRpcMessage::notification(notification),
        ),
      ) catch {
        _ =>
          RuntimeOwnerNotificationImmediate(
            completion=client_runtime_trace_completion(
              state,
              notification.method_name,
            ),
          )
      }
    },
    execute: invocation => client_adapter_execute(invocation, endpoint),
    execute_failure: (_state, invocation) => {
      client_adapter_failure_completion(invocation)
    },
    execute_cancel: (_state, invocation) => {
      client_adapter_cancel_completion(invocation)
    },
    complete_request: (state, _id, invocation, completion) => {
      client_runtime_request_completion(
        client_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          client_runtime_complete_failure(
            state,
            client_adapter_invocation_method_name(invocation),
          )
      }
    },
    complete_notification: (state, invocation, completion) => {
      client_runtime_notification_completion(
        client_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          client_runtime_trace_completion(
            state,
            client_adapter_invocation_method_name(invocation),
          )
      }
    },
    plan_local_effect: command => {
      match command {
        CancelRequest(request_id~) =>
          RuntimeOwnerCommands([RuntimeOwnerCancelInbound(request_id~)])
        // The `JsonRpcError` payload intentionally does not cross this
        // boundary: the runtime trace seam carries the method name only.
        TraceError(method_name~, error=_) =>
          RuntimeOwnerCommands([RuntimeOwnerTrace(method_name~)])
      }
    },
    cancel_request: (state, _id, invocation) => {
      (state, client_adapter_cancel_completion(invocation))
    },
    // Client adapter state carries no reservation: close keeps the last
    // committed protocol snapshot exactly as the owner recorded it.
    abort: (state, _task) => state,
  }
}

///|
/// Run one Client connection on the single native owner-loop engine.  This is
/// a thin composition of `connection_runtime_run_owner` with
/// `client_runtime_owner_port`: it validates the options fail-fast and creates
/// no connection state of its own.
pub async fn client_runtime_run(
  endpoint~ : ClientEndpoint,
  initial_state~ : ClientAdapterState,
  ports~ : RuntimePorts,
  options~ : RuntimeOptions,
) -> Unit {
  runtime_validate_options(options)
  connection_runtime_run_owner(
    ports,
    options,
    client_runtime_owner_port(endpoint~, initial_state~),
  )
}

///|
/// Run one Client connection on the single native owner-loop engine with the
/// engine-level outbound channel handed to the Client endpoint factory.  The
/// factory runs after the connection-local queues and shutdown state exist
/// and before the loop starts, mirroring the Agent bridge's context factory
/// timing.
///
/// Unlike the Agent side, Client execution takes no separate context: the
/// endpoint value itself is the only execution seam, and its immutable
/// service handlers receive parameters only.  The factory therefore builds
/// the endpoint the whole loop will use, letting the composition root
/// construct service handlers that already captured the channel — typically
/// by building `client_connection_over_channel` (in `connection/broker`) and
/// closing over it.  This package stays independent of the broker package;
/// the caller decides what the factory builds.
///
/// This runner adds no second loop or channel state of its own: it validates
/// the options fail-fast and reuses the same single reader/writer/reducer
/// engine as `client_runtime_run`, whose signature and behavior stay
/// unchanged.
pub async fn client_runtime_run_with_outbound(
  endpoint_factory~ : (RuntimeOutboundChannel[ClientAdapterCompletion]) -> ClientEndpoint,
  initial_state~ : ClientAdapterState,
  ports~ : RuntimePorts,
  options~ : RuntimeOptions,
) -> Unit {
  runtime_validate_options(options)
  connection_runtime_run_owner_with_outbound(ports, options, channel => {
    client_runtime_owner_port(
      endpoint=endpoint_factory(channel),
      initial_state~,
    )
  })
}

///|
/// Drive one spawned agent subprocess as a Client connection over real
/// process stdio.  The child's stdin/stdout become the engine's writer/reader
/// ports (frames flushed per write), the child's stderr is redirected to this
/// process's stderr, and diagnostics go to the trace sink (stderr by
/// default).  This is a thin composition of `client_runtime_run_with_outbound`
/// over `runtime_process_ports`; it validates the options fail-fast before
/// spawning and reuses the same single reader/writer/reducer engine.
///
/// Connection scope equals child scope: the composition opens one task group,
/// spawns the child inside it with `no_wait = true`, runs the engine, then
/// closes the child's stdin — the ACP stdio shutdown signal — before group
/// teardown.  A well-behaved agent exits on that EOF and is reaped with its
/// exit status; an agent that keeps running is gracefully terminated and then
/// forcefully killed by the async process layer's cancellation handler during
/// teardown, still inside this call.  No detached child and no background
/// reaper can outlive the returned call.
///
/// The client owns that shutdown signal, and closing the child's stdin is
/// what ends a live interactive session: the engine itself only ends on the
/// child's stdout EOF, which a well-behaved agent produces after observing
/// its own stdin EOF.  The built-in close therefore runs after the engine has
/// already ended and cannot serve as the client's proactive shutdown.  The
/// optional `spawned` callback closes exactly that gap: it receives the real
/// `RuntimeProcessPorts` handle right after the spawn succeeds and before
/// the engine starts, so a composition root (or test driver) can close the
/// child's stdin, wait for the exit status, or cancel the child at the
/// moment its session logic decides to.  The default is a no-op, so callers
/// that only consume a self-terminating child keep the previous behavior.
pub async fn client_connect_process(
  endpoint_factory~ : (RuntimeOutboundChannel[ClientAdapterCompletion]) -> ClientEndpoint,
  initial_state~ : ClientAdapterState,
  handlers~ : RuntimeHandlerPort,
  command~ : String,
  args? : Array[String] = [],
  extra_env? : Map[String, String],
  inherit_env? : Bool = true,
  spawned? : (RuntimeProcessPorts) -> Unit = _ => (),
  options? : RuntimeOptions = runtime_default_options(),
  trace? : (RuntimeTraceEvent) -> Unit = runtime_stderr_trace,
) -> Unit {
  runtime_validate_options(options)
  @async.with_task_group(group => {
    let spawned_ports = runtime_process_ports(
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
    client_runtime_run_with_outbound(
      endpoint_factory~,
      initial_state~,
      ports=spawned_ports.ports,
      options~,
    )
  })
}

///|
fn client_runtime_request_admission(
  admission : ClientAdapterAdmission,
) -> RuntimeOwnerRequestAdmission[
  ClientAdapterState,
  ClientAdapterInvocation,
  ClientAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerRequestImmediate(
        completion=client_runtime_request_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerRequestInvoke(state~, invocation~)
  }
}

///|
fn client_runtime_notification_admission(
  admission : ClientAdapterAdmission,
) -> RuntimeOwnerNotificationAdmission[
  ClientAdapterState,
  ClientAdapterInvocation,
  ClientAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerNotificationImmediate(
        completion=client_runtime_notification_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerNotificationInvoke(state~, invocation~)
  }
}

///|
/// Fold one adapter step into exactly one wire result plus ordered owner
/// effects.  A request step carries exactly one `Response`; violating that
/// invariant is an adapter bug and fails fast instead of guessing a wire
/// result.  The Client adapter has no wire-notification output, so every
/// other output is a local command effect.
fn client_runtime_request_completion(
  step : ClientAdapterStep,
) -> RuntimeOwnerRequestCompletion[ClientAdapterState, ClientAdapterCommand] {
  let mut response : RuntimeHandlerResult? = None
  let effects : Array[RuntimeOwnerEffect[ClientAdapterCommand]] = []
  for output in step.outputs {
    match output {
      Response(value) =>
        if response is Some(_) {
          abort("client adapter request step must carry exactly one response")
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
    Some(response) => { state: step.state, response, effects }
    None => abort("client adapter request step must carry one response")
  }
}

///|
/// Notification steps never carry a response; a `Response` here is an
/// adapter bug and fails fast rather than synthesizing a wire reply.  As on
/// the request side, the Client adapter produces local command effects only.
fn client_runtime_notification_completion(
  step : ClientAdapterStep,
) -> RuntimeOwnerNotificationCompletion[
  ClientAdapterState,
  ClientAdapterCommand,
] {
  let effects : Array[RuntimeOwnerEffect[ClientAdapterCommand]] = []
  for output in step.outputs {
    match output {
      Response(_) =>
        abort("client adapter notification step must not carry a response")
      Command(command) => effects.push(Local(effect=command))
    }
  }
  { state: step.state, effects }
}

///|
fn client_runtime_trace_effects(
  method_name : String,
) -> Array[RuntimeOwnerEffect[ClientAdapterCommand]] {
  [Local(effect=TraceError(method_name~, error=JsonRpcError::internal_error()))]
}

///|
/// Total typed fallback for a residual adapter failure on the notification
/// side: one trace effect, no response, state unchanged.
fn client_runtime_trace_completion(
  state : ClientAdapterState,
  method_name : String,
) -> RuntimeOwnerNotificationCompletion[
  ClientAdapterState,
  ClientAdapterCommand,
] {
  { state, effects: client_runtime_trace_effects(method_name) }
}

///|
/// Total typed fallback for a residual adapter failure during request
/// admission: exactly one internal-error response plus one trace effect,
/// state unchanged.
fn client_runtime_request_admission_failure(
  state : ClientAdapterState,
  method_name : String,
) -> RuntimeOwnerRequestAdmission[
  ClientAdapterState,
  ClientAdapterInvocation,
  ClientAdapterCommand,
] {
  RuntimeOwnerRequestImmediate(completion={
    state,
    response: HandlerError(JsonRpcError::internal_error()),
    effects: client_runtime_trace_effects(method_name),
  })
}

///|
/// Total typed fallback for a residual adapter failure during request
/// completion: exactly one internal-error response plus one trace effect,
/// state unchanged.  Same policy as the admission fallback.
fn client_runtime_complete_failure(
  state : ClientAdapterState,
  method_name : String,
) -> RuntimeOwnerRequestCompletion[ClientAdapterState, ClientAdapterCommand] {
  {
    state,
    response: HandlerError(JsonRpcError::internal_error()),
    effects: client_runtime_trace_effects(method_name),
  }
}
