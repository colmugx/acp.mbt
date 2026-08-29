///|
fn experimental_v2_agent_cancel_inbound_id(
  request_id : ExperimentalV2RequestId,
) -> @jsonrpc.RequestId {
  match request_id {
    RequestIdNull => Null
    RequestIdNumber(number) => Number(number)
    RequestIdStr(text) => String(text)
  }
}

///|
/// Bind one v2 Agent endpoint and its outbound context onto the single
/// shared connection owner-loop engine.  The returned port captures only the
/// immutable `endpoint` and `context` values; every protocol transition stays
/// inside the engine-owned `ExperimentalV2AgentAdapterState`.  There is no
/// second owner loop, shadow pending map, `Ref`, `Mutex`, or builder surface
/// here.
///
/// Residual `ExperimentalV2AgentAdapterError` values (`EndpointMismatch`,
/// `UnexpectedMessage`) indicate composition or protocol bugs, but the owner
/// port closures are total by signature.  Each residual is therefore answered
/// with an explicit typed fallback instead of being swallowed: requests get
/// exactly one internal-error response plus one trace effect, notifications
/// get one trace effect and no response, and the owner state is held
/// unchanged.  The fallback is visible on the wire and in the trace sink; it
/// is never a silent success.
pub fn experimental_v2_agent_runtime_owner_port(
  endpoint~ : ExperimentalV2AgentEndpoint,
  context~ : ExperimentalV2AgentContext,
  initial_state~ : ExperimentalV2AgentAdapterState,
) -> @connection.RuntimeOwnerPort[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentInvocation,
  ExperimentalV2AgentCompletion,
  ExperimentalV2AgentAdapterCommand,
] {
  {
    initial_state,
    admit_request: (state, _id, request) => {
      experimental_v2_agent_runtime_request_admission(
        experimental_v2_agent_adapter_admit(
          state,
          endpoint,
          @jsonrpc.JsonRpcMessage::request(request),
        ),
      ) catch {
        _ =>
          experimental_v2_agent_runtime_request_admission_failure(
            state,
            request.method_name,
          )
      }
    },
    admit_notification: (state, notification) => {
      experimental_v2_agent_runtime_notification_admission(
        experimental_v2_agent_adapter_admit(
          state,
          endpoint,
          @jsonrpc.JsonRpcMessage::notification(notification),
        ),
      ) catch {
        _ =>
          RuntimeOwnerNotificationImmediate(
            completion=experimental_v2_agent_runtime_trace_completion(
              state,
              notification.method_name,
            ),
          )
      }
    },
    execute: invocation => {
      experimental_v2_agent_execute(invocation, endpoint, context)
    },
    execute_failure: (_state, invocation) => {
      experimental_v2_agent_failure_completion(invocation)
    },
    execute_cancel: (_state, invocation) => {
      experimental_v2_agent_cancel_completion(invocation)
    },
    complete_request: (state, _id, invocation, completion) => {
      experimental_v2_agent_runtime_request_completion(
        experimental_v2_agent_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          experimental_v2_agent_runtime_complete_failure(
            state,
            experimental_v2_agent_invocation_method_name(invocation),
          )
      }
    },
    complete_notification: (state, invocation, completion) => {
      experimental_v2_agent_runtime_notification_completion(
        experimental_v2_agent_adapter_complete(state, invocation, completion),
      ) catch {
        _ =>
          experimental_v2_agent_runtime_trace_completion(
            state,
            experimental_v2_agent_invocation_method_name(invocation),
          )
      }
    },
    plan_local_effect: command => {
      match command {
        CancelRequest(request_id~) =>
          RuntimeOwnerCommands([
            RuntimeOwnerCancelInbound(
              request_id=experimental_v2_agent_cancel_inbound_id(request_id),
            ),
          ])
        // The `JsonRpcError` payload intentionally does not cross this
        // boundary: the runtime trace seam carries the method name only.
        TraceError(method_name~, error=_) =>
          RuntimeOwnerCommands([RuntimeOwnerTrace(method_name~)])
      }
    },
    cancel_request: (state, _id, invocation) => {
      (state, experimental_v2_agent_cancel_completion(invocation))
    },
    // Close makes a pending login/logout reservation meaningless: the engine
    // has already cancelled their tasks and settled their wire ids, so the
    // adapter drops the stale reservation instead of keeping it in a dead
    // state snapshot.
    abort: (state, _task) => { ..state, reservation: Idle, },
  }
}

///|
fn experimental_v2_agent_runtime_request_admission(
  admission : ExperimentalV2AgentAdmission,
) -> @connection.RuntimeOwnerRequestAdmission[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentInvocation,
  ExperimentalV2AgentAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerRequestImmediate(
        completion=experimental_v2_agent_runtime_request_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerRequestInvoke(state~, invocation~)
  }
}

///|
fn experimental_v2_agent_runtime_notification_admission(
  admission : ExperimentalV2AgentAdmission,
) -> @connection.RuntimeOwnerNotificationAdmission[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentInvocation,
  ExperimentalV2AgentAdapterCommand,
] {
  match admission {
    Immediate(step) =>
      RuntimeOwnerNotificationImmediate(
        completion=experimental_v2_agent_runtime_notification_completion(step),
      )
    Invoke(state~, invocation~) =>
      RuntimeOwnerNotificationInvoke(state~, invocation~)
  }
}

///|
/// Fold one adapter step into exactly one wire result plus ordered owner
/// effects.  A request step carrying zero or multiple responses is an
/// adapter bug and fails fast instead of guessing a wire result.
fn experimental_v2_agent_runtime_request_completion(
  step : ExperimentalV2AgentAdapterStep,
) -> @connection.RuntimeOwnerRequestCompletion[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentAdapterCommand,
] {
  let mut response : @runtime.RuntimeHandlerResult? = None
  let effects : Array[
    @connection.RuntimeOwnerEffect[ExperimentalV2AgentAdapterCommand],
  ] = []
  for output in step.outputs {
    match output {
      Response(value) =>
        if response is Some(_) {
          abort("v2 agent adapter request step must carry exactly one response")
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
    Some(response) => { state: step.state, response, effects, }
    None => abort("v2 agent adapter request step must carry one response")
  }
}

///|
/// Notification steps never carry a response; a `Response` here is an adapter
/// bug and fails fast rather than synthesizing a wire reply.
fn experimental_v2_agent_runtime_notification_completion(
  step : ExperimentalV2AgentAdapterStep,
) -> @connection.RuntimeOwnerNotificationCompletion[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentAdapterCommand,
] {
  let effects : Array[
    @connection.RuntimeOwnerEffect[ExperimentalV2AgentAdapterCommand],
  ] = []
  for output in step.outputs {
    match output {
      Response(_) =>
        abort("v2 agent adapter notification step must not carry a response")
      Notification(notification) =>
        effects.push(WireNotification(notification~))
      Command(command) => effects.push(Local(effect=command))
    }
  }
  { state: step.state, effects, }
}

///|
fn experimental_v2_agent_runtime_trace_effects(
  method_name : String,
) -> Array[@connection.RuntimeOwnerEffect[ExperimentalV2AgentAdapterCommand]] {
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
fn experimental_v2_agent_runtime_trace_completion(
  state : ExperimentalV2AgentAdapterState,
  method_name : String,
) -> @connection.RuntimeOwnerNotificationCompletion[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentAdapterCommand,
] {
  { state, effects: experimental_v2_agent_runtime_trace_effects(method_name), }
}

///|
/// Total typed fallback for a residual adapter failure during request
/// admission: exactly one internal-error response plus one trace effect,
/// state unchanged.
fn experimental_v2_agent_runtime_request_admission_failure(
  state : ExperimentalV2AgentAdapterState,
  method_name : String,
) -> @connection.RuntimeOwnerRequestAdmission[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentInvocation,
  ExperimentalV2AgentAdapterCommand,
] {
  RuntimeOwnerRequestImmediate(completion={
    state,
    response: HandlerError(@jsonrpc.JsonRpcError::internal_error()),
    effects: experimental_v2_agent_runtime_trace_effects(method_name),
  })
}

///|
/// Total typed fallback for a residual adapter failure during request
/// completion: exactly one internal-error response plus one trace effect,
/// state unchanged.  Same policy as the admission fallback.
fn experimental_v2_agent_runtime_complete_failure(
  state : ExperimentalV2AgentAdapterState,
  method_name : String,
) -> @connection.RuntimeOwnerRequestCompletion[
  ExperimentalV2AgentAdapterState,
  ExperimentalV2AgentAdapterCommand,
] {
  {
    state,
    response: HandlerError(@jsonrpc.JsonRpcError::internal_error()),
    effects: experimental_v2_agent_runtime_trace_effects(method_name),
  }
}
