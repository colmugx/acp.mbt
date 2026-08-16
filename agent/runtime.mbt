///|
/// Bind one Agent endpoint and its outbound context onto the single
/// connection owner-loop engine.  The returned port captures only the
/// immutable `endpoint` and `context` values; every protocol transition stays
/// inside the engine-owned `AgentAdapterState`.  There is no second owner
/// loop, shadow pending map, `Ref`, `Mutex`, or builder surface here.
///
/// Residual `AgentAdapterError` values (`EndpointMismatch`,
/// `UnexpectedMessage`) indicate composition or protocol bugs, but the owner
/// port closures are total by signature.  Each residual is therefore answered
/// with an explicit typed fallback instead of being swallowed: requests get
/// exactly one internal-error response plus one trace effect, notifications
/// get one trace effect and no response, and the owner state is held
/// unchanged.  The fallback is visible on the wire and in the trace sink; it
/// is never a silent success.
pub fn agent_runtime_owner_port(
  endpoint~ : AgentEndpoint,
  context~ : AgentContext,
  initial_state~ : AgentAdapterState,
) -> RuntimeOwnerPort[
  AgentAdapterState,
  AgentAdapterInvocation,
  AgentAdapterCompletion,
  AgentAdapterCommand,
] {
  {
    initial_state,
    admit_request: (state, _id, request) => {
      agent_runtime_request_admission(
        agent_adapter_admit(state, endpoint, JsonRpcMessage::request(request)),
      ) catch {
        _ => agent_runtime_request_admission_failure(state, request.method_name)
      }
    },
    admit_notification: (state, notification) => {
      agent_runtime_notification_admission(
        agent_adapter_admit(
          state,
          endpoint,
          JsonRpcMessage::notification(notification),
        ),
      ) catch {
        _ =>
          RuntimeOwnerNotificationImmediate(
            completion=agent_runtime_trace_completion(
              state,
              notification.method_name,
            ),
          )
      }
    },
    execute: invocation => agent_adapter_execute(invocation, endpoint, context),
    execute_failure: (_state, invocation) => {
      agent_adapter_failure_completion(invocation)
    },
    execute_cancel: (_state, invocation) => {
      agent_adapter_cancel_completion(invocation)
    },
    complete_request: (state, _id, invocation, completion) => {
      agent_runtime_request_completion(
        agent_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          agent_runtime_complete_failure(
            state,
            agent_adapter_invocation_method_name(invocation),
          )
      }
    },
    complete_notification: (state, invocation, completion) => {
      agent_runtime_notification_completion(
        agent_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          agent_runtime_trace_completion(
            state,
            agent_adapter_invocation_method_name(invocation),
          )
      }
    },
    plan_local_effect: command => {
      match command {
        CancelRequest(request_id~) =>
          RuntimeOwnerCommands([RuntimeOwnerCancelInbound(request_id~)])
        CloseConnection(reason~) =>
          RuntimeOwnerCommands([RuntimeOwnerClose(reason~)])
        // The `JsonRpcError` payload intentionally does not cross this
        // boundary: the runtime trace seam carries the method name only.
        TraceError(method_name~, error=_) =>
          RuntimeOwnerCommands([RuntimeOwnerTrace(method_name~)])
      }
    },
    cancel_request: (state, _id, invocation) => {
      (state, agent_adapter_cancel_completion(invocation))
    },
    // Close makes pending authenticate/logout reservations meaningless: the
    // engine has already cancelled their tasks and settled their wire ids,
    // so the adapter drops the stale reservation instead of keeping it in a
    // dead state snapshot.
    abort: (state, _task) => { ..state, reservation: Idle },
  }
}

///|
/// Run one Agent connection on the single native owner-loop engine.  This is
/// a thin composition of `connection_runtime_run_owner` with
/// `agent_runtime_owner_port`: it validates the options fail-fast and creates
/// no connection state of its own.
pub async fn agent_runtime_run(
  endpoint~ : AgentEndpoint,
  context~ : AgentContext,
  initial_state~ : AgentAdapterState,
  ports~ : RuntimePorts,
  options~ : RuntimeOptions,
) -> Unit {
  runtime_validate_options(options)
  connection_runtime_run_owner(
    ports,
    options,
    agent_runtime_owner_port(endpoint~, context~, initial_state~),
  )
}

///|
/// Run one Agent connection on the single native owner-loop engine with the
/// engine-level outbound channel handed to the Agent context factory.  The
/// factory runs after the connection-local queues and shutdown state exist
/// and before the loop starts; it typically builds
/// `agent_context_over_channel` (in `connection/broker`) so handlers running
/// mid-execution can issue reverse requests and stream notifications through
/// the real engine.  This runner adds no second loop or channel state of its
/// own: it validates the options fail-fast and reuses the same single
/// reader/writer/reducer engine as `agent_runtime_run`, whose signature and
/// behavior stay unchanged.
pub async fn agent_runtime_run_with_outbound(
  endpoint~ : AgentEndpoint,
  context_factory~ : (RuntimeOutboundChannel[AgentAdapterCompletion]) -> AgentContext,
  initial_state~ : AgentAdapterState,
  ports~ : RuntimePorts,
  options~ : RuntimeOptions,
) -> Unit {
  runtime_validate_options(options)
  connection_runtime_run_owner_with_outbound(ports, options, channel => {
    agent_runtime_owner_port(
      endpoint~,
      context=context_factory(channel),
      initial_state~,
    )
  })
}

///|
/// Serve this process's real stdio as one Agent connection: inbound ACP
/// frames arrive on stdin, outbound frames (including one final response per
/// request) go to stdout, and every diagnostic goes to the trace sink
/// (stderr by default).  This is a thin composition of `agent_runtime_run`
/// over `runtime_stdio_ports`: it validates the options fail-fast before any
/// I/O binding and creates no connection state of its own.  The loop ends
/// when stdin reaches EOF or the engine fails; both outcomes surface through
/// the same single reader/writer/reducer engine as every other runner.
pub async fn agent_serve_stdio(
  endpoint~ : AgentEndpoint,
  context~ : AgentContext,
  initial_state~ : AgentAdapterState,
  options? : RuntimeOptions = runtime_default_options(),
  trace? : (RuntimeTraceEvent) -> Unit = runtime_stderr_trace,
) -> Unit {
  runtime_validate_options(options)
  agent_runtime_run(
    endpoint~,
    context~,
    initial_state~,
    ports=runtime_stdio_ports(trace~),
    options~,
  )
}

///|
/// Serve this process's real stdio as one Agent connection with the
/// engine-level outbound channel handed to the Agent context factory, so
/// handlers running mid-execution can stream `session/update` notifications
/// and issue reverse requests (`session/request_permission`, elicitation,
/// filesystem, terminal) through the real engine instead of a fail-fast
/// broker.  Without this composition a stdio Agent could answer requests but
/// never exercise the reverse direction of the protocol; the factory timing
/// mirrors `agent_runtime_run_with_outbound` (after the connection-local
/// queues exist, before the loop starts).  This is a thin composition over
/// `runtime_stdio_ports`: it validates the options fail-fast before any I/O
/// binding and creates no second loop, channel state, or connection state of
/// its own.  The loop ends when stdin reaches EOF or the engine fails.
pub async fn agent_serve_stdio_with_outbound(
  endpoint~ : AgentEndpoint,
  context_factory~ : (RuntimeOutboundChannel[AgentAdapterCompletion]) -> AgentContext,
  initial_state~ : AgentAdapterState,
  options? : RuntimeOptions = runtime_default_options(),
  trace? : (RuntimeTraceEvent) -> Unit = runtime_stderr_trace,
) -> Unit {
  runtime_validate_options(options)
  agent_runtime_run_with_outbound(
    endpoint~,
    context_factory~,
    initial_state~,
    ports=runtime_stdio_ports(trace~),
    options~,
  )
}

///|
fn agent_runtime_request_admission(
  admission : AgentAdapterAdmission,
) -> RuntimeOwnerRequestAdmission[
  AgentAdapterState,
  AgentAdapterInvocation,
  AgentAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerRequestImmediate(
        completion=agent_runtime_request_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerRequestInvoke(state~, invocation~)
  }
}

///|
fn agent_runtime_notification_admission(
  admission : AgentAdapterAdmission,
) -> RuntimeOwnerNotificationAdmission[
  AgentAdapterState,
  AgentAdapterInvocation,
  AgentAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerNotificationImmediate(
        completion=agent_runtime_notification_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerNotificationInvoke(state~, invocation~)
  }
}

///|
/// Fold one adapter step into exactly one wire result plus ordered owner
/// effects.  A request step carries exactly one `Response`; violating that
/// invariant is an adapter bug and fails fast instead of guessing a wire
/// result.
fn agent_runtime_request_completion(
  step : AgentAdapterStep,
) -> RuntimeOwnerRequestCompletion[AgentAdapterState, AgentAdapterCommand] {
  let mut response : RuntimeHandlerResult? = None
  let effects : Array[RuntimeOwnerEffect[AgentAdapterCommand]] = []
  for output in step.outputs {
    match output {
      Response(value) =>
        if response is Some(_) {
          abort("agent adapter request step must carry exactly one response")
        } else {
          response = Some(
            match value {
              Success(success) => HandlerSuccess(success.result)
              Error(failure) => HandlerError(failure.error)
            },
          )
        }
      Notification(notification) =>
        effects.push(WireNotification(notification~))
      Command(command) => effects.push(Local(effect=command))
    }
  }
  match response {
    Some(response) => { state: step.state, response, effects }
    None => abort("agent adapter request step must carry one response")
  }
}

///|
/// Notification steps never carry a response; a `Response` here is an
/// adapter bug and fails fast rather than synthesizing a wire reply.
fn agent_runtime_notification_completion(
  step : AgentAdapterStep,
) -> RuntimeOwnerNotificationCompletion[AgentAdapterState, AgentAdapterCommand] {
  let effects : Array[RuntimeOwnerEffect[AgentAdapterCommand]] = []
  for output in step.outputs {
    match output {
      Response(_) =>
        abort("agent adapter notification step must not carry a response")
      Notification(notification) =>
        effects.push(WireNotification(notification~))
      Command(command) => effects.push(Local(effect=command))
    }
  }
  { state: step.state, effects }
}

///|
fn agent_runtime_trace_effects(
  method_name : String,
) -> Array[RuntimeOwnerEffect[AgentAdapterCommand]] {
  [Local(effect=TraceError(method_name~, error=JsonRpcError::internal_error()))]
}

///|
/// Total typed fallback for a residual adapter failure on the notification
/// side: one trace effect, no response, state unchanged.
fn agent_runtime_trace_completion(
  state : AgentAdapterState,
  method_name : String,
) -> RuntimeOwnerNotificationCompletion[AgentAdapterState, AgentAdapterCommand] {
  { state, effects: agent_runtime_trace_effects(method_name) }
}

///|
/// Total typed fallback for a residual adapter failure during request
/// admission: exactly one internal-error response plus one trace effect,
/// state unchanged.
fn agent_runtime_request_admission_failure(
  state : AgentAdapterState,
  method_name : String,
) -> RuntimeOwnerRequestAdmission[
  AgentAdapterState,
  AgentAdapterInvocation,
  AgentAdapterCommand,
] {
  RuntimeOwnerRequestImmediate(completion={
    state,
    response: HandlerError(JsonRpcError::internal_error()),
    effects: agent_runtime_trace_effects(method_name),
  })
}

///|
/// Total typed fallback for a residual adapter failure during request
/// completion: exactly one internal-error response plus one trace effect,
/// state unchanged.  Same policy as the admission fallback.
fn agent_runtime_complete_failure(
  state : AgentAdapterState,
  method_name : String,
) -> RuntimeOwnerRequestCompletion[AgentAdapterState, AgentAdapterCommand] {
  {
    state,
    response: HandlerError(JsonRpcError::internal_error()),
    effects: agent_runtime_trace_effects(method_name),
  }
}
