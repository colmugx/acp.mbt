///|
using @jsonrpc {jsonrpc_encode, jsonrpc_decode}

///|
using @runtime {
  type RuntimeError,
  type RuntimeTraceEvent,
  type RuntimeReaderPort,
  type RuntimeWriterPort,
  type RuntimeHandlerResult,
  type RuntimeHandlerPort,
  type RuntimePorts,
  type RuntimeOptions,
  type RuntimeOutboundFailureKind,
  runtime_trace_event,
  runtime_request_id_text,
  runtime_validate_options,
}

///|
using @transport {
  type FramingState,
  framing_state,
  framing_feed,
  framing_finish,
}

///|
/// A synchronous admission result for a request handled by a generic
/// connection owner. An immediate result commits the complete owner step
/// synchronously; an invoke commits `state` before the invocation is handed
/// to an async task. The task never receives the owner.
pub(all) enum RuntimeOwnerRequestAdmission[S, I, E] {
  RuntimeOwnerRequestImmediate(
    completion~ : RuntimeOwnerRequestCompletion[S, E]
  )
  RuntimeOwnerRequestInvoke(state~ : S, invocation~ : I)
}

///|
/// A synchronous admission result for a notification. Notifications never
/// carry a request id or response; immediate notifications still commit their
/// state and effects synchronously.
pub(all) enum RuntimeOwnerNotificationAdmission[S, I, E] {
  RuntimeOwnerNotificationImmediate(
    completion~ : RuntimeOwnerNotificationCompletion[S, E]
  )
  RuntimeOwnerNotificationInvoke(state~ : S, invocation~ : I)
}

///|
/// A completion event produced by an immutable async invocation. The event
/// contains only its owner token, correlation id (for requests), and typed
/// completion. It cannot carry or mutate connection state.
pub(all) enum RuntimeOwnerEvent[C] {
  RuntimeOwnerRequestCompleted(token~ : Int, id~ : RequestId, completion~ : C)
  RuntimeOwnerNotificationCompleted(token~ : Int, completion~ : C)
}

///|
/// The immutable task record owned by one connection owner loop. Its
/// invocation is caller-defined typed data; no queue, task group, or mutable
/// state is stored here.
pub struct RuntimeOwnerTask[I] {
  task_token : Int
  request_id : RequestId?
  invocation : I
  notification : Bool
  cancel_requested : Bool
}

///|
/// A connection-owned effect produced by a pure completion. Wire notifications
/// are transport values; local effects are caller-defined data for the owner
/// to interpret. Neither variant executes an effect here.
pub(all) enum RuntimeOwnerEffect[E] {
  WireNotification(notification~ : JsonRpcNotification)
  Local(effect~ : E)
} derive(Eq, Debug)

///|
/// Connection-owned pure commands compiled from owner effects. These values
/// are intents only; the runtime does not execute or interpret them here.
/// The `RuntimeOwner` prefix keeps their constructors distinct from the
/// connection reducer's event and command constructors. The eventual owner
/// interpreter supplies fixed trace fields from the method name; no arbitrary
/// payload or trace text crosses this boundary.
pub(all) enum RuntimeOwnerCommand {
  RuntimeOwnerWriteNotification(notification~ : JsonRpcNotification)
  RuntimeOwnerCancelInbound(request_id~ : RequestId)
  RuntimeOwnerTrace(method_name~ : String)
  RuntimeOwnerClose(reason~ : String)
} derive(Eq, Debug)

///|
priv enum RuntimeOwnerCommandResult {
  RuntimeOwnerCommandsComplete
  RuntimeOwnerCloseRequested(reason~ : String)
}

///|
/// Explicit result of local-effect planning. `RuntimeOwnerNoCommands` is an
/// intentional no-command plan; `RuntimeOwnerCommands` preserves every
/// planned command in order. An empty commands array is still explicit, but
/// callers should use `RuntimeOwnerNoCommands` when no command is intended.
pub(all) enum RuntimeOwnerLocalPlan {
  RuntimeOwnerNoCommands
  RuntimeOwnerCommands(Array[RuntimeOwnerCommand])
} derive(Eq, Debug)

///|
/// Compile every owner effect in order without changing owner state. A local
/// effect is expanded by the caller-owned total planner and its commands are
/// appended in place; no effect is dropped or interpreted in this function.
/// This is a pure plan compiler only: it performs no I/O, task cancellation,
/// tracing, or connection close. The real owner runner/interpreter is not
/// wired here yet.
pub fn[E] runtime_owner_plan_effects(
  effects : Array[RuntimeOwnerEffect[E]],
  plan_local_effect : (E) -> RuntimeOwnerLocalPlan,
) -> Array[RuntimeOwnerCommand] {
  let commands : Array[RuntimeOwnerCommand] = []
  for effect in effects {
    match effect {
      WireNotification(notification~) =>
        commands.push(RuntimeOwnerWriteNotification(notification~))
      Local(effect~) =>
        match plan_local_effect(effect) {
          RuntimeOwnerNoCommands => ()
          RuntimeOwnerCommands(local_commands) =>
            for command in local_commands {
              commands.push(command)
            }
        }
    }
  }
  commands
}

///|
/// A request completion commits domain state together with exactly one wire
/// result and zero or more owner effects. Requests cannot represent multiple
/// responses through this type.
pub(all) struct RuntimeOwnerRequestCompletion[S, E] {
  state : S
  response : RuntimeHandlerResult
  effects : Array[RuntimeOwnerEffect[E]]
}

///|
/// A notification completion commits domain state and effects but has no
/// response field, so the owner cannot accidentally reply to a notification.
pub(all) struct RuntimeOwnerNotificationCompletion[S, E] {
  state : S
  effects : Array[RuntimeOwnerEffect[E]]
}

///|
/// The one-shot generic owner hooks. The connection runtime or another
/// connection-local owner loop invokes these callbacks synchronously while it
/// owns `S`; only `execute` crosses the async boundary.
pub(all) struct RuntimeOwnerPort[S, I, C, E] {
  initial_state : S
  admit_request : (S, RequestId, JsonRpcRequest) -> RuntimeOwnerRequestAdmission[
    S,
    I,
    E,
  ]
  admit_notification : (S, JsonRpcNotification) -> RuntimeOwnerNotificationAdmission[
    S,
    I,
    E,
  ]
  execute : async (I) -> C
  /// Produces a redacted/static typed failure completion at the task boundary.
  execute_failure : (S, I) -> C
  /// Produces a typed cancellation completion at the task boundary.
  execute_cancel : (S, I) -> C
  complete_request : (S, RequestId, I, C) -> RuntimeOwnerRequestCompletion[S, E]
  complete_notification : (S, I, C) -> RuntimeOwnerNotificationCompletion[S, E]
  /// Plans local effects as explicit pure data. No I/O is performed here; the
  /// real RuntimeOwner runner/interpreter is not wired yet.
  plan_local_effect : (E) -> RuntimeOwnerLocalPlan
  cancel_request : (S, RequestId, I) -> (S, C)
  abort : (S, RuntimeOwnerTask[I]) -> S
}

///|
/// Immutable owner state. A single runtime owner must serialize all calls to
/// admission, cancellation, completion, and close. No Ref, lock, or second
/// reader/writer/reducer loop is needed.
pub struct RuntimeOwner[S, I] {
  state : S
  tasks : Array[RuntimeOwnerTask[I]]
  next_task_token : Int
  closed : Bool
}

///|
pub(all) enum RuntimeOwnerIgnore {
  Closed
  UnknownTask(token~ : Int)
  UnknownRequest(id~ : RequestId)
  AlreadyCancelled(id~ : RequestId)
  RequestIdMismatch(expected~ : RequestId, actual~ : RequestId)
  TaskKindMismatch(token~ : Int)
} derive(Eq, Debug)

///|
pub(all) enum RuntimeOwnerRequestAction[S, I, E] {
  RuntimeOwnerImmediate(completion~ : RuntimeOwnerRequestCompletion[S, E])
  RuntimeOwnerInvoke(task~ : RuntimeOwnerTask[I])
}

///|
pub(all) enum RuntimeOwnerNotificationAction[S, I, E] {
  RuntimeOwnerNotificationImmediate(
    completion~ : RuntimeOwnerNotificationCompletion[S, E]
  )
  RuntimeOwnerNotificationInvoke(task~ : RuntimeOwnerTask[I])
}

///|
pub(all) enum RuntimeOwnerCompletionResult[S, I, O] {
  RuntimeOwnerCompletionApplied(owner~ : RuntimeOwner[S, I], completion~ : O)
  RuntimeOwnerCompletionIgnored(reason~ : RuntimeOwnerIgnore)
}

///|
/// Cancellation marks the task and returns the typed cancellation completion
/// as an event. The owner applies that event through the same completion path,
/// which releases the reservation exactly once; a late handler event is then
/// ignored by token.
pub(all) enum RuntimeOwnerCancelResult[S, I, C] {
  RuntimeOwnerCancelRequested(
    owner~ : RuntimeOwner[S, I],
    task~ : RuntimeOwnerTask[I],
    event~ : RuntimeOwnerEvent[C]
  )
  RuntimeOwnerCancelIgnored(reason~ : RuntimeOwnerIgnore)
}

///|
pub(all) enum RuntimeOwnerCloseResult[S, I] {
  RuntimeOwnerClosed(
    owner~ : RuntimeOwner[S, I],
    aborted~ : Array[RuntimeOwnerTask[I]]
  )
  RuntimeOwnerAlreadyClosed(owner~ : RuntimeOwner[S, I])
}

///|
pub(all) suberror RuntimeOwnerError {
  Closed
} derive(Eq, Debug)

///|
pub fn[S, I, C, E] runtime_owner_new(
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwner[S, I] {
  { state: port.initial_state, tasks: [], next_task_token: 0, closed: false }
}

///|
pub fn[S, I] RuntimeOwner::state(self : RuntimeOwner[S, I]) -> S {
  self.state
}

///|
pub fn[S, I] RuntimeOwner::task_count(self : RuntimeOwner[S, I]) -> Int {
  self.tasks.length()
}

///|
pub fn[S, I] RuntimeOwner::is_closed(self : RuntimeOwner[S, I]) -> Bool {
  self.closed
}

///|
pub fn[I] RuntimeOwnerTask::task_token(self : RuntimeOwnerTask[I]) -> Int {
  self.task_token
}

///|
pub fn[I] RuntimeOwnerTask::request_id(
  self : RuntimeOwnerTask[I],
) -> RequestId? {
  self.request_id
}

///|
pub fn[I] RuntimeOwnerTask::invocation(self : RuntimeOwnerTask[I]) -> I {
  self.invocation
}

///|
pub fn[I] RuntimeOwnerTask::is_notification(self : RuntimeOwnerTask[I]) -> Bool {
  self.notification
}

///|
pub fn[I] RuntimeOwnerTask::cancel_requested(
  self : RuntimeOwnerTask[I],
) -> Bool {
  self.cancel_requested
}

///|
fn[I] runtime_owner_cancelled_task(
  task : RuntimeOwnerTask[I],
) -> RuntimeOwnerTask[I] {
  { ..task, cancel_requested: true }
}

///|
fn[S, I] runtime_owner_find_task(
  owner : RuntimeOwner[S, I],
  token : Int,
) -> RuntimeOwnerTask[I]? {
  for task in owner.tasks {
    if task.task_token == token {
      return Some(task)
    }
  }
  None
}

///|
fn[S, I] runtime_owner_replace_task(
  owner : RuntimeOwner[S, I],
  replacement : RuntimeOwnerTask[I],
) -> RuntimeOwner[S, I] {
  let tasks : Array[RuntimeOwnerTask[I]] = []
  for task in owner.tasks {
    if task.task_token == replacement.task_token {
      tasks.push(replacement)
    } else {
      tasks.push(task)
    }
  }
  { ..owner, tasks, }
}

///|
fn[S, I] runtime_owner_remove_task(
  owner : RuntimeOwner[S, I],
  token : Int,
) -> RuntimeOwner[S, I] {
  let tasks : Array[RuntimeOwnerTask[I]] = []
  for task in owner.tasks {
    if task.task_token != token {
      tasks.push(task)
    }
  }
  { ..owner, tasks, }
}

///|
pub fn[S, I, C, E] runtime_owner_admit_request(
  owner : RuntimeOwner[S, I],
  request : JsonRpcRequest,
  port : RuntimeOwnerPort[S, I, C, E],
) -> (RuntimeOwner[S, I], RuntimeOwnerRequestAction[S, I, E]) raise RuntimeOwnerError {
  if owner.closed {
    raise Closed
  }
  match (port.admit_request)(owner.state, request.id, request) {
    RuntimeOwnerRequestImmediate(completion~) =>
      ({ ..owner, state: completion.state }, RuntimeOwnerImmediate(completion~))
    RuntimeOwnerRequestInvoke(state~, invocation~) => {
      let task : RuntimeOwnerTask[I] = {
        task_token: owner.next_task_token,
        request_id: Some(request.id),
        invocation,
        notification: false,
        cancel_requested: false,
      }
      let tasks = Array::copy(owner.tasks)
      tasks.push(task)
      (
        {
          state,
          tasks,
          next_task_token: owner.next_task_token + 1,
          closed: false,
        },
        RuntimeOwnerInvoke(task~),
      )
    }
  }
}

///|
pub fn[S, I, C, E] runtime_owner_admit_notification(
  owner : RuntimeOwner[S, I],
  notification : JsonRpcNotification,
  port : RuntimeOwnerPort[S, I, C, E],
) -> (RuntimeOwner[S, I], RuntimeOwnerNotificationAction[S, I, E]) raise RuntimeOwnerError {
  if owner.closed {
    raise Closed
  }
  match (port.admit_notification)(owner.state, notification) {
    RuntimeOwnerNotificationImmediate(completion~) =>
      (
        { ..owner, state: completion.state },
        RuntimeOwnerNotificationImmediate(completion~),
      )
    RuntimeOwnerNotificationInvoke(state~, invocation~) => {
      let task : RuntimeOwnerTask[I] = {
        task_token: owner.next_task_token,
        request_id: None,
        invocation,
        notification: true,
        cancel_requested: false,
      }
      let tasks = Array::copy(owner.tasks)
      tasks.push(task)
      (
        {
          state,
          tasks,
          next_task_token: owner.next_task_token + 1,
          closed: false,
        },
        RuntimeOwnerNotificationInvoke(task~),
      )
    }
  }
}

///|
/// Execute only the immutable invocation and return a typed event. This is
/// the only async operation in the generic owner seam.
pub async fn[S, I, C, E] runtime_owner_execute(
  task : RuntimeOwnerTask[I],
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwnerEvent[C] {
  let completion = (port.execute)(task.invocation)
  if task.notification {
    RuntimeOwnerNotificationCompleted(token=task.task_token, completion~)
  } else {
    match task.request_id {
      Some(id) =>
        RuntimeOwnerRequestCompleted(token=task.task_token, id~, completion~)
      None => abort("runtime owner request has no request id")
    }
  }
}

///|
/// Start one immutable invocation in the caller's existing task group. The
/// returned task is the only runtime cancellation handle; owner state remains
/// with the caller, which must apply the resulting event serially.
pub fn[G, S, I, C, E] runtime_owner_spawn(
  group : @async.TaskGroup[G],
  task : RuntimeOwnerTask[I],
  port : RuntimeOwnerPort[S, I, C, E],
) -> @async.Task[RuntimeOwnerEvent[C]] {
  group.spawn(() => runtime_owner_execute(task, port))
}

///|
/// Run one owner invocation and publish exactly one typed task event. The
/// worker carries immutable invocation data only; failure conversion remains
/// on the owner loop because `execute_failure` requires the current owner
/// state.
async fn[S, I, C, E] runtime_owner_execute_task(
  task : RuntimeOwnerTask[I],
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwnerTaskEventOf[C] {
  let completion = (port.execute)(task.invocation) catch {
    error => {
      if @async.is_cancellation_error(error) {
        raise error
      }
      return RuntimeOwnerTaskFailed(
        token=task.task_token,
        request_id=task.request_id,
        notification=task.notification,
      )
    }
  }
  RuntimeOwnerTaskCompleted(
    event=if task.notification {
      RuntimeOwnerNotificationCompleted(token=task.task_token, completion~)
    } else {
      match task.request_id {
        Some(id) =>
          RuntimeOwnerRequestCompleted(token=task.task_token, id~, completion~)
        None => abort("runtime owner request has no request id")
      }
    },
  )
}

///|
/// Publish a task result into the connection's one event queue. Queue
/// backpressure and closure remain runtime errors; neither is hidden inside a
/// detached task.
async fn[S, I, C, E] runtime_owner_task_loop(
  task : RuntimeOwnerTask[I],
  port : RuntimeOwnerPort[S, I, C, E],
  events : @aqueue.Queue[RuntimeEventOf[C]],
  shutdown : Ref[Bool],
  limit : Int,
) -> Unit {
  let event = runtime_owner_execute_task(task, port)
  // Async tasks are cooperatively scheduled.  There is no yield between the
  // execute result and this check, so a completion produced before shutdown
  // is always offered to the queue.  Results observed after shutdown are
  // intentionally dropped as close-time cancellation; they are not a runtime
  // completion and must not manufacture a second response.
  if !shutdown.val {
    runtime_event_put(events, RuntimeOwnerTaskEvent(event), limit)
  }
}

///|
pub fn[S, I, C, E] runtime_owner_complete_request(
  owner : RuntimeOwner[S, I],
  event : RuntimeOwnerEvent[C],
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwnerCompletionResult[S, I, RuntimeOwnerRequestCompletion[S, E]] {
  if owner.closed {
    return RuntimeOwnerCompletionIgnored(reason=Closed)
  }
  match event {
    RuntimeOwnerNotificationCompleted(token~, completion=_) =>
      RuntimeOwnerCompletionIgnored(reason=TaskKindMismatch(token~))
    RuntimeOwnerRequestCompleted(token~, id=actual, completion~) =>
      match runtime_owner_find_task(owner, token) {
        None => RuntimeOwnerCompletionIgnored(reason=UnknownTask(token~))
        Some(task) if task.notification =>
          RuntimeOwnerCompletionIgnored(reason=TaskKindMismatch(token~))
        Some(task) =>
          match task.request_id {
            Some(expected) if expected == actual => {
              let completion = (port.complete_request)(
                owner.state,
                actual,
                task.invocation,
                completion,
              )
              let next = runtime_owner_remove_task(owner, token)
              RuntimeOwnerCompletionApplied(
                owner={ ..next, state: completion.state },
                completion~,
              )
            }
            Some(expected) =>
              RuntimeOwnerCompletionIgnored(
                reason=RequestIdMismatch(expected~, actual~),
              )
            None =>
              RuntimeOwnerCompletionIgnored(reason=TaskKindMismatch(token~))
          }
      }
  }
}

///|
pub fn[S, I, C, E] runtime_owner_complete_notification(
  owner : RuntimeOwner[S, I],
  event : RuntimeOwnerEvent[C],
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwnerCompletionResult[
  S,
  I,
  RuntimeOwnerNotificationCompletion[S, E],
] {
  if owner.closed {
    return RuntimeOwnerCompletionIgnored(reason=Closed)
  }
  match event {
    RuntimeOwnerRequestCompleted(token~, id=_, completion=_) =>
      RuntimeOwnerCompletionIgnored(reason=TaskKindMismatch(token~))
    RuntimeOwnerNotificationCompleted(token~, completion~) =>
      match runtime_owner_find_task(owner, token) {
        None => RuntimeOwnerCompletionIgnored(reason=UnknownTask(token~))
        Some(task) if !task.notification =>
          RuntimeOwnerCompletionIgnored(reason=TaskKindMismatch(token~))
        Some(task) => {
          let completion = (port.complete_notification)(
            owner.state,
            task.invocation,
            completion,
          )
          let next = runtime_owner_remove_task(owner, token)
          RuntimeOwnerCompletionApplied(
            owner={ ..next, state: completion.state },
            completion~,
          )
        }
      }
  }
}

///|
/// Mark the exact request as cancelled and synchronously create its typed
/// cancellation completion. The caller may cancel the task after this
/// admission; applying `event` through `runtime_owner_complete_request`
/// releases the owner reservation. A late task completion is ignored.
pub fn[S, I, C, E] runtime_owner_cancel_request(
  owner : RuntimeOwner[S, I],
  id : RequestId,
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwnerCancelResult[S, I, C] {
  if owner.closed {
    return RuntimeOwnerCancelIgnored(reason=Closed)
  }
  let mut found : RuntimeOwnerTask[I]? = None
  for task in owner.tasks {
    match task.request_id {
      Some(task_id) if task_id == id && !task.notification => {
        found = Some(task)
        break
      }
      _ => ()
    }
  }
  match found {
    None => RuntimeOwnerCancelIgnored(reason=UnknownRequest(id~))
    Some(task) if task.cancel_requested =>
      RuntimeOwnerCancelIgnored(reason=AlreadyCancelled(id~))
    Some(task) => {
      let cancelled_task = runtime_owner_cancelled_task(task)
      let next = runtime_owner_replace_task(owner, cancelled_task)
      let (cancelled_state, completion) = (port.cancel_request)(
        next.state,
        id,
        task.invocation,
      )
      RuntimeOwnerCancelRequested(
        owner={ ..next, state: cancelled_state },
        task=cancelled_task,
        event=RuntimeOwnerRequestCompleted(
          token=task.task_token,
          id~,
          completion~,
        ),
      )
    }
  }
}

///|
/// Close the owner exactly once. Abort callbacks update only the domain state;
/// no wire response is generated here. Any completion carrying an old token
/// is ignored by the closed-owner check.
pub fn[S, I, C, E] runtime_owner_close(
  owner : RuntimeOwner[S, I],
  port : RuntimeOwnerPort[S, I, C, E],
) -> RuntimeOwnerCloseResult[S, I] {
  if owner.closed {
    return RuntimeOwnerAlreadyClosed(owner~)
  }
  let mut state = owner.state
  for task in owner.tasks {
    state = (port.abort)(state, task)
  }
  RuntimeOwnerClosed(
    owner={
      state,
      tasks: [],
      next_task_token: owner.next_task_token,
      closed: true,
    },
    aborted=Array::copy(owner.tasks),
  )
}

///|
/// Items owned by the one stdout writer task.
priv enum RuntimeWriterItem {
  RuntimeFrame(Bytes)
  RuntimeStop
}

///|
/// Events delivered to the one reducer/dispatch loop.
priv enum RuntimeEventOf[C] {
  RuntimeChunk(Bytes)
  RuntimeEof
  RuntimeReaderFailed(RuntimeError)
  RuntimeWriterFailed(RuntimeError)
  RuntimeOwnerTaskEvent(RuntimeOwnerTaskEventOf[C])
  RuntimeHandlerCompleted(Int, RequestId, C)
  RuntimeHandlerFailed(Int, RequestId)
  RuntimeNotificationCompleted(Int)
  RuntimeNotificationFailed(Int)
  RuntimeNotificationCancelled(Int)
}

///|
/// The only event a generic owner task may publish to the connection queue.
/// A task can publish either its typed completion or a redacted failure marker;
/// the owner loop supplies `execute_failure` while it owns the current state.
priv enum RuntimeOwnerTaskEventOf[C] {
  RuntimeOwnerTaskCompleted(event~ : RuntimeOwnerEvent[C])
  RuntimeOwnerTaskFailed(
    token~ : Int,
    request_id~ : RequestId?,
    notification~ : Bool
  )
}

///|
type RuntimeEvent = RuntimeEventOf[RuntimeHandlerResult]

///|
fn runtime_identity_handler_result(
  result : RuntimeHandlerResult,
) -> RuntimeHandlerResult {
  result
}

///|
/// A cancellation handle for a task associated with one inbound request or
/// notification. The closure captures only the task returned by the current
/// task group; no task is stored globally.
priv struct RuntimeTaskControl {
  task_token : Int
  request_id : RequestId?
  cancel : () -> Unit
}

///|
priv struct RuntimeLegacySpawnContext[C] {
  shutdown : Ref[Bool]
  handlers : RuntimeHandlerPort
  events : @aqueue.Queue[RuntimeEventOf[C]]
  result_to_event : (RuntimeHandlerResult) -> C
  limit : Int
}

///|
priv enum RuntimeApplyControl {
  RuntimeApplyContinue
  RuntimeApplyOwnerClose(reason~ : String)
}

///|
priv enum RuntimeDispatchAction[D] {
  RuntimeDispatchSpawned(
    context~ : D,
    task~ : RuntimeTaskControl,
    next_task_token~ : Int
  )
  RuntimeDispatchRequestImmediate(
    context~ : D,
    event~ : ConnectionEvent,
    commands~ : Array[RuntimeOwnerCommand]
  )
  RuntimeDispatchNotificationImmediate(
    context~ : D,
    commands~ : Array[RuntimeOwnerCommand]
  )
}

///|
priv enum RuntimeDispatchCancelResult[D] {
  RuntimeDispatchCancelApplied(context~ : D)
  RuntimeDispatchCancelIgnored(context~ : D, reason~ : RuntimeOwnerIgnore)
}

///|
priv struct RuntimeDispatchPort[G, D] {
  request : (@async.TaskGroup[G], Int, JsonRpcRequest, D) -> RuntimeDispatchAction[
    D,
  ] raise RuntimeError
  notification : (@async.TaskGroup[G], Int, JsonRpcNotification, D) -> RuntimeDispatchAction[
    D,
  ] raise RuntimeError
  cancel_inbound : (D, RequestId, Array[RuntimeTaskControl]) -> RuntimeDispatchCancelResult[
    D,
  ] raise RuntimeError
  close_owner : (D, Array[RuntimeTaskControl]) -> D raise RuntimeError
}

///|
priv struct RuntimeOwnerDispatchContext[S, I, C, E] {
  owner : RuntimeOwner[S, I]
  port : RuntimeOwnerPort[S, I, C, E]
  events : @aqueue.Queue[RuntimeEventOf[C]]
  shutdown : Ref[Bool]
  limit : Int
}

///|
priv enum RuntimeOwnerTaskApply[D] {
  RuntimeOwnerRequestCompletion(
    context~ : D,
    task_token~ : Int,
    id~ : RequestId,
    result~ : RuntimeHandlerResult,
    commands~ : Array[RuntimeOwnerCommand]
  )
  RuntimeOwnerNotificationCompletion(
    context~ : D,
    task_token~ : Int,
    commands~ : Array[RuntimeOwnerCommand]
  )
  RuntimeOwnerEventIgnored(
    context~ : D,
    task_token~ : Int,
    request_id~ : RequestId?,
    reason~ : RuntimeOwnerIgnore
  )
}

///|
fn[G, S, I, C, E] runtime_owner_dispatch_port() -> RuntimeDispatchPort[
  G,
  RuntimeOwnerDispatchContext[S, I, C, E],
] {
  {
    request: (group, token, request, context) => {
      let (owner, action) = runtime_owner_admit_request(
        context.owner,
        request,
        context.port,
      ) catch {
        Closed => raise ReducerFailed
      }
      match action {
        RuntimeOwnerImmediate(completion~) => {
          let event = match completion.response {
            HandlerSuccess(result) => IncomingCompleted(id=request.id, result~)
            HandlerError(error) => IncomingFailed(id=request.id, error~)
          }
          RuntimeDispatchRequestImmediate(
            context={ ..context, owner, },
            event~,
            commands=runtime_owner_plan_effects(
              completion.effects,
              context.port.plan_local_effect,
            ),
          )
        }
        RuntimeOwnerInvoke(task~) => {
          if task.task_token != token {
            raise TaskRequestMismatch
          }
          let spawned = group.spawn(() => {
            runtime_owner_task_loop(
              task,
              context.port,
              context.events,
              context.shutdown,
              context.limit,
            )
          })
          RuntimeDispatchSpawned(
            context={ ..context, owner, },
            task={
              task_token: task.task_token,
              request_id: Some(request.id),
              cancel: () => spawned.cancel(),
            },
            next_task_token=token + 1,
          )
        }
      }
    },
    notification: (group, token, notification, context) => {
      let (owner, action) = runtime_owner_admit_notification(
        context.owner,
        notification,
        context.port,
      ) catch {
        Closed => raise ReducerFailed
      }
      match action {
        RuntimeOwnerNotificationImmediate(completion~) =>
          RuntimeDispatchNotificationImmediate(
            context={ ..context, owner, },
            commands=runtime_owner_plan_effects(
              completion.effects,
              context.port.plan_local_effect,
            ),
          )
        RuntimeOwnerNotificationInvoke(task~) => {
          if task.task_token != token {
            raise TaskRequestMismatch
          }
          let spawned = group.spawn(() => {
            runtime_owner_task_loop(
              task,
              context.port,
              context.events,
              context.shutdown,
              context.limit,
            )
          })
          RuntimeDispatchSpawned(
            context={ ..context, owner, },
            task={
              task_token: task.task_token,
              request_id: None,
              cancel: () => spawned.cancel(),
            },
            next_task_token=token + 1,
          )
        }
      }
    },
    cancel_inbound: (context, id, tasks) => {
      let native_task = match runtime_find_task_by_request_id(tasks, id) {
        None => raise TaskControlMissing
        Some(task) => task
      }
      match runtime_owner_cancel_request(context.owner, id, context.port) {
        RuntimeOwnerCancelIgnored(reason~) =>
          RuntimeDispatchCancelIgnored(context~, reason~)
        RuntimeOwnerCancelRequested(owner~, task~, event~) => {
          if native_task.task_token != task.task_token {
            raise TaskRequestMismatch
          }
          runtime_event_put(
            context.events,
            RuntimeOwnerTaskEvent(RuntimeOwnerTaskCompleted(event~)),
            context.limit,
          )
          runtime_cancel_task(tasks, id)
          RuntimeDispatchCancelApplied(context={ ..context, owner, })
        }
      }
    },
    close_owner: (context, _) => {
      match runtime_owner_close(context.owner, context.port) {
        RuntimeOwnerClosed(owner~, aborted=_) => { ..context, owner, }
        RuntimeOwnerAlreadyClosed(owner~) => { ..context, owner, }
      }
    },
  }
}

///|
fn[S, I, C, E] runtime_owner_task_ignored(
  context : RuntimeOwnerDispatchContext[S, I, C, E],
  token : Int,
  request_id : RequestId?,
  reason : RuntimeOwnerIgnore,
) -> RuntimeOwnerTaskApply[RuntimeOwnerDispatchContext[S, I, C, E]] raise RuntimeError {
  match reason {
    RequestIdMismatch(..) | TaskKindMismatch(_) => raise TaskRequestMismatch
    _ =>
      RuntimeOwnerEventIgnored(context~, task_token=token, request_id~, reason~)
  }
}

///|
/// Validate and apply one typed owner task event while the connection loop owns
/// both reducer state and owner state. The runtime task control and the owner
/// task are checked independently so a token, id, or request/notification kind
/// mismatch fails before either reservation is consumed.
fn[S, I, C, E] runtime_owner_apply_task_event(
  event : RuntimeOwnerTaskEventOf[C],
  state : ConnectionState,
  context : RuntimeOwnerDispatchContext[S, I, C, E],
  tasks : Array[RuntimeTaskControl],
) -> RuntimeOwnerTaskApply[RuntimeOwnerDispatchContext[S, I, C, E]] raise RuntimeError {
  let (token, request_id, notification, completion_event) = match event {
    RuntimeOwnerTaskCompleted(event~) =>
      match event {
        RuntimeOwnerRequestCompleted(token~, id=actual, completion~) =>
          (
            token,
            Some(actual),
            false,
            Some(RuntimeOwnerRequestCompleted(token~, id=actual, completion~)),
          )
        RuntimeOwnerNotificationCompleted(token~, completion~) =>
          (
            token,
            None,
            true,
            Some(RuntimeOwnerNotificationCompleted(token~, completion~)),
          )
      }
    RuntimeOwnerTaskFailed(token~, request_id~, notification~) =>
      (token, request_id, notification, None)
  }
  let control = match runtime_find_task(tasks, token) {
    None =>
      return RuntimeOwnerEventIgnored(
        context~,
        task_token=token,
        request_id~,
        reason=UnknownTask(token~),
      )
    Some(control) => control
  }
  if control.request_id != request_id {
    raise TaskRequestMismatch
  }
  let owner_task = match runtime_owner_find_task(context.owner, token) {
    None =>
      return RuntimeOwnerEventIgnored(
        context~,
        task_token=token,
        request_id~,
        reason=UnknownTask(token~),
      )
    Some(task) => task
  }
  if owner_task.notification != notification {
    raise TaskRequestMismatch
  }
  match (owner_task.request_id, request_id) {
    (Some(expected), Some(actual)) if expected == actual => ()
    (None, None) if notification => ()
    (Some(_), Some(_)) => raise TaskRequestMismatch
    _ => raise TaskRequestMismatch
  }
  match request_id {
    Some(id) =>
      match connection_inbound_index(state.inbound, id) {
        None =>
          return RuntimeOwnerEventIgnored(
            context~,
            task_token=token,
            request_id~,
            reason=UnknownRequest(id~),
          )
        Some(_) => ()
      }
    None => ()
  }
  let completion_event = match completion_event {
    Some(event) => event
    None => {
      let completion = (context.port.execute_failure)(
        context.owner.state,
        owner_task.invocation,
      )
      if notification {
        RuntimeOwnerNotificationCompleted(token~, completion~)
      } else {
        match request_id {
          Some(id) => RuntimeOwnerRequestCompleted(token~, id~, completion~)
          None => raise TaskRequestMismatch
        }
      }
    }
  }
  match completion_event {
    RuntimeOwnerRequestCompleted(token~, id=actual, completion~) =>
      match
        runtime_owner_complete_request(
          context.owner,
          RuntimeOwnerRequestCompleted(token~, id=actual, completion~),
          context.port,
        ) {
        RuntimeOwnerCompletionApplied(owner~, completion~) =>
          RuntimeOwnerRequestCompletion(
            context={ ..context, owner, },
            task_token=token,
            id=actual,
            result=completion.response,
            commands=runtime_owner_plan_effects(
              completion.effects,
              context.port.plan_local_effect,
            ),
          )
        RuntimeOwnerCompletionIgnored(reason~) =>
          runtime_owner_task_ignored(context, token, request_id, reason)
      }
    RuntimeOwnerNotificationCompleted(token~, completion~) =>
      match
        runtime_owner_complete_notification(
          context.owner,
          RuntimeOwnerNotificationCompleted(token~, completion~),
          context.port,
        ) {
        RuntimeOwnerCompletionApplied(owner~, completion~) =>
          RuntimeOwnerNotificationCompletion(
            context={ ..context, owner, },
            task_token=token,
            commands=runtime_owner_plan_effects(
              completion.effects,
              context.port.plan_local_effect,
            ),
          )
        RuntimeOwnerCompletionIgnored(reason~) =>
          runtime_owner_task_ignored(context, token, request_id, reason)
      }
  }
}

///|
fn[C, D] runtime_owner_event_unavailable(
  _event : RuntimeOwnerTaskEventOf[C],
  _state : ConnectionState,
  _context : D,
  _tasks : Array[RuntimeTaskControl],
) -> RuntimeOwnerTaskApply[D] raise RuntimeError {
  raise ReducerFailed
}

///|
fn[C] runtime_owner_handler_result_unavailable(
  _completion : C,
) -> RuntimeHandlerResult {
  abort("runtime owner queue received a legacy handler event")
}

///|
fn runtime_remove_task(
  tasks : Array[RuntimeTaskControl],
  task_token : Int,
) -> Array[RuntimeTaskControl] raise RuntimeError {
  if !tasks.any(task => task.task_token == task_token) {
    raise TaskControlMissing
  }
  let result : Array[RuntimeTaskControl] = []
  for task in tasks {
    if task.task_token != task_token {
      result.push(task)
    }
  }
  result
}

///|
/// Take one task control without turning a late completion into a runtime
/// failure. The second result is `None` for a duplicate/late event.
fn runtime_take_task(
  tasks : Array[RuntimeTaskControl],
  task_token : Int,
) -> (Array[RuntimeTaskControl], RuntimeTaskControl?) raise RuntimeError {
  let result : Array[RuntimeTaskControl] = []
  let mut taken : RuntimeTaskControl? = None
  for task in tasks {
    if task.task_token == task_token {
      taken = Some(task)
    } else {
      result.push(task)
    }
  }
  match taken {
    None => (result, None)
    Some(task) => (runtime_remove_task(tasks, task_token), Some(task))
  }
}

///|
/// Look up a task control without consuming it. Handler events must validate
/// their request correlation before the task can be removed; otherwise a
/// malformed completion could settle a different pending request.
fn runtime_find_task(
  tasks : Array[RuntimeTaskControl],
  task_token : Int,
) -> RuntimeTaskControl? {
  for task in tasks {
    if task.task_token == task_token {
      return Some(task)
    }
  }
  None
}

///|
fn runtime_find_task_by_request_id(
  tasks : Array[RuntimeTaskControl],
  request_id : RequestId,
) -> RuntimeTaskControl? {
  for task in tasks {
    if task.request_id == Some(request_id) {
      return Some(task)
    }
  }
  None
}

///|
fn runtime_owner_ignore_kind(reason : RuntimeOwnerIgnore) -> String {
  match reason {
    Closed => "closed"
    UnknownTask(_) => "unknown_task"
    UnknownRequest(_) => "unknown_request"
    AlreadyCancelled(_) => "already_cancelled"
    RequestIdMismatch(..) => "request_id_mismatch"
    TaskKindMismatch(_) => "task_kind_mismatch"
  }
}

///|
fn[D] runtime_apply_inbound_cancel(
  request_id : RequestId,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
  dispatch_context : D,
  cancel_inbound : (D, RequestId, Array[RuntimeTaskControl]) -> RuntimeDispatchCancelResult[
    D,
  ] raise RuntimeError,
) -> D raise RuntimeError {
  match cancel_inbound(dispatch_context, request_id, tasks) {
    RuntimeDispatchCancelApplied(context~) => {
      (ports.trace)(
        runtime_trace_event(
          "inbound",
          "cancel_requested",
          runtime_request_id_text(request_id),
          "",
          "cancel",
        ),
      )
      context
    }
    RuntimeDispatchCancelIgnored(context~, reason~) => {
      (ports.trace)(
        runtime_trace_event(
          "inbound",
          "owner_cancel_ignored",
          runtime_request_id_text(request_id),
          "",
          runtime_owner_ignore_kind(reason),
        ),
      )
      // An ignored owner cancellation is not a successful command. Preserve
      // the existing fail-fast runtime error so an unknown or duplicate
      // effect cannot accidentally cancel another task or continue silently.
      ignore(context)
      raise TaskControlMissing
    }
  }
}

///|
fn runtime_error_kind(error : RuntimeError) -> String {
  match error {
    InvalidOptions => "invalid_options"
    ReaderFailed => "reader_failed"
    ReaderEmptyChunk => "reader_empty_chunk"
    EventQueueClosed => "event_queue_closed"
    EventQueueBackpressure(_) => "event_queue_backpressure"
    WriterQueueClosed => "writer_queue_closed"
    WriterQueueBackpressure(_) => "writer_queue_backpressure"
    WriterFailed => "writer_failed"
    FramingFailed => "framing_failed"
    JsonRpcDecodeFailed => "jsonrpc_decode_failed"
    JsonRpcEncodeFailed => "jsonrpc_encode_failed"
    ReducerFailed => "reducer_failed"
    TaskControlMissing => "task_control_missing"
    TaskRequestMismatch => "task_request_mismatch"
    HandlerFailed => "handler_failed"
    NotificationFailed => "notification_failed"
    ResponseHandlerFailed => "response_handler_failed"
    OutboundCancelUnavailable => "outbound_cancel_unavailable"
    OutboundCancelFailed => "outbound_cancel_failed"
    OutboundCompletionFailed => "outbound_completion_failed"
    CloseCleanupFailed(_) => "close_cleanup_failed"
  }
}

///|
fn runtime_outbound_failure_kind(reason : String) -> RuntimeOutboundFailureKind {
  match reason {
    "protocol" => Protocol
    "framing" => Framing
    "reader" => Reader
    "writer" => Writer
    "handler" => Handler
    "notification" => Notification
    "eof" => EndOfInput
    "event_queue" => EventQueue
    "owner" => Runtime
    _ => Runtime
  }
}

///|
fn runtime_close_cleanup_error(
  primary : RuntimeError,
  cleanup : RuntimeError,
) -> RuntimeError {
  CloseCleanupFailed(
    primary_kind=runtime_error_kind(primary),
    cleanup_phase=runtime_error_kind(cleanup),
  )
}

///|
fn[E] runtime_event_put(
  queue : @aqueue.Queue[E],
  event : E,
  limit : Int,
) -> Unit raise RuntimeError {
  let accepted = queue.try_put(event) catch { _ => raise EventQueueClosed }
  if !accepted {
    raise EventQueueBackpressure(limit~)
  }
}

///|
async fn[C] runtime_reader_loop(
  port : RuntimeReaderPort,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  limit : Int,
  read_chunk_bytes : Int,
) -> Unit {
  for ;; {
    let chunk = (port.read)(read_chunk_bytes) catch {
      error => {
        if @async.is_cancellation_error(error) {
          return
        }
        runtime_event_put(events, RuntimeReaderFailed(ReaderFailed), limit)
        break
      }
    }
    match chunk {
      None => {
        runtime_event_put(events, RuntimeEof, limit)
        break
      }
      Some(chunk) => {
        if chunk.is_empty() {
          runtime_event_put(
            events,
            RuntimeReaderFailed(ReaderEmptyChunk),
            limit,
          )
          break
        }
        runtime_event_put(events, RuntimeChunk(chunk), limit)
      }
    }
  }
}

///|
async fn[C] runtime_writer_loop(
  port : RuntimeWriterPort,
  queue : @aqueue.Queue[RuntimeWriterItem],
  trace : (RuntimeTraceEvent) -> Unit,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  limit : Int,
  shutdown : Ref[Bool],
) -> Unit {
  for ;; {
    let item = queue.get() catch {
      _ => {
        if shutdown.val || @async.is_being_cancelled() {
          return
        }
        runtime_event_put(events, RuntimeWriterFailed(WriterQueueClosed), limit)
        break
      }
    }
    match item {
      RuntimeStop => break
      RuntimeFrame(frame) => {
        trace(runtime_trace_event("outbound", "writer_dequeue", "", "", ""))
        (port.write)(frame) catch {
          error => {
            if @async.is_cancellation_error(error) {
              return
            }
            trace(
              runtime_trace_event("outbound", "writer_failed", "", "", "writer"),
            )
            runtime_event_put(events, RuntimeWriterFailed(WriterFailed), limit)
            break
          }
        }
        trace(runtime_trace_event("outbound", "writer_written", "", "", ""))
      }
    }
  }
}

///|
async fn[C] runtime_request_task(
  task_token : Int,
  request : JsonRpcRequest,
  shutdown : Ref[Bool],
  handlers : RuntimeHandlerPort,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  result_to_event : (RuntimeHandlerResult) -> C,
  limit : Int,
) -> Unit {
  let result = (handlers.request)(request) catch {
    error => {
      if @async.is_cancellation_error(error) {
        if !shutdown.val {
          runtime_event_put(
            events,
            RuntimeHandlerCompleted(
              task_token,
              request.id,
              result_to_event(HandlerError(JsonRpcError::request_cancelled())),
            ),
            limit,
          )
        }
        return
      }
      if !shutdown.val {
        runtime_event_put(
          events,
          RuntimeHandlerFailed(task_token, request.id),
          limit,
        )
      }
      return
    }
  }
  if !shutdown.val {
    runtime_event_put(
      events,
      RuntimeHandlerCompleted(task_token, request.id, result_to_event(result)),
      limit,
    )
  }
}

///|
async fn[C] runtime_notification_task(
  task_token : Int,
  notification : JsonRpcNotification,
  shutdown : Ref[Bool],
  handlers : RuntimeHandlerPort,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  limit : Int,
) -> Unit {
  (handlers.notification)(notification) catch {
    error => {
      if @async.is_cancellation_error(error) {
        if !shutdown.val {
          runtime_event_put(
            events,
            RuntimeNotificationCancelled(task_token),
            limit,
          )
        }
        return
      }
      if !shutdown.val {
        runtime_event_put(events, RuntimeNotificationFailed(task_token), limit)
      }
      return
    }
  }
  if !shutdown.val {
    runtime_event_put(events, RuntimeNotificationCompleted(task_token), limit)
  }
}

///|
fn[G, C] runtime_spawn_legacy_request(
  group : @async.TaskGroup[G],
  next_task_token : Int,
  request : JsonRpcRequest,
  context : RuntimeLegacySpawnContext[C],
) -> RuntimeDispatchAction[RuntimeLegacySpawnContext[C]] {
  let task = group.spawn(() => {
    runtime_request_task(
      next_task_token,
      request,
      context.shutdown,
      context.handlers,
      context.events,
      context.result_to_event,
      context.limit,
    )
  })
  RuntimeDispatchSpawned(
    context~,
    task={
      task_token: next_task_token,
      request_id: Some(request.id),
      cancel: () => task.cancel(),
    },
    next_task_token=next_task_token + 1,
  )
}

///|
fn[G, C] runtime_spawn_legacy_notification(
  group : @async.TaskGroup[G],
  next_task_token : Int,
  notification : JsonRpcNotification,
  context : RuntimeLegacySpawnContext[C],
) -> RuntimeDispatchAction[RuntimeLegacySpawnContext[C]] {
  let task = group.spawn(() => {
    runtime_notification_task(
      next_task_token,
      notification,
      context.shutdown,
      context.handlers,
      context.events,
      context.limit,
    )
  })
  RuntimeDispatchSpawned(
    context~,
    task={
      task_token: next_task_token,
      request_id: None,
      cancel: () => task.cancel(),
    },
    next_task_token=next_task_token + 1,
  )
}

///|
fn[G, C] runtime_legacy_dispatch_port() -> RuntimeDispatchPort[
  G,
  RuntimeLegacySpawnContext[C],
] {
  {
    request: (group, token, request, context) => {
      runtime_spawn_legacy_request(group, token, request, context)
    },
    notification: (group, token, notification, context) => {
      runtime_spawn_legacy_notification(group, token, notification, context)
    },
    cancel_inbound: (context, id, tasks) => {
      runtime_cancel_task(tasks, id)
      RuntimeDispatchCancelApplied(context~)
    },
    close_owner: (context, _) => context,
  }
}

///|
fn runtime_writer_offer(
  queue : @aqueue.Queue[RuntimeWriterItem],
  limit : Int,
  message : JsonRpcMessage,
) -> Unit raise RuntimeError {
  let text = jsonrpc_encode(message) catch { _ => raise JsonRpcEncodeFailed }
  let frame = @utf8.encode(text + "\n")
  let accepted = queue.try_put(RuntimeFrame(frame)) catch {
    @aqueue.QueueAlreadyClosed => raise WriterQueueClosed
    _ => raise WriterQueueClosed
  }
  if !accepted {
    raise WriterQueueBackpressure(limit~)
  }
}

///|
async fn runtime_writer_stop(
  queue : @aqueue.Queue[RuntimeWriterItem],
  force_close : Bool,
) -> Unit raise RuntimeError {
  if force_close {
    queue.close(clear=true)
  } else {
    queue.put(RuntimeStop) catch {
      _ => {
        queue.close(clear=true)
        raise WriterQueueClosed
      }
    }
  }
}

///|
fn runtime_cancel_task(
  tasks : Array[RuntimeTaskControl],
  request_id : RequestId,
) -> Unit raise RuntimeError {
  if !tasks.any(task => task.request_id == Some(request_id)) {
    raise TaskControlMissing
  }
  for task in tasks {
    if task.request_id == Some(request_id) {
      (task.cancel)()
    }
  }
}

///|
fn[D] runtime_apply_owner_commands_of(
  commands : Array[RuntimeOwnerCommand],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
  dispatch_context : D,
  cancel_inbound : (D, RequestId, Array[RuntimeTaskControl]) -> RuntimeDispatchCancelResult[
    D,
  ] raise RuntimeError,
) -> (D, RuntimeOwnerCommandResult) raise RuntimeError {
  let mut next_context = dispatch_context
  for command in commands {
    match command {
      RuntimeOwnerWriteNotification(notification~) =>
        runtime_writer_offer(
          writer_queue,
          options.queue_capacity,
          JsonRpcMessage::notification(notification),
        )
      RuntimeOwnerCancelInbound(request_id~) =>
        next_context = runtime_apply_inbound_cancel(
          request_id, ports, tasks, next_context, cancel_inbound,
        )
      RuntimeOwnerTrace(method_name~) =>
        (ports.trace)(
          runtime_trace_event(
            "runtime", "owner_trace", "", method_name, "owner",
          ),
        )
      RuntimeOwnerClose(reason~) =>
        return (next_context, RuntimeOwnerCloseRequested(reason~))
    }
  }
  (next_context, RuntimeOwnerCommandsComplete)
}

///|
fn runtime_apply_owner_commands(
  commands : Array[RuntimeOwnerCommand],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
) -> RuntimeOwnerCommandResult raise RuntimeError {
  let (_, result) = runtime_apply_owner_commands_of(
    commands,
    writer_queue,
    options,
    ports,
    tasks,
    (),
    (context, id, controls) => {
      runtime_cancel_task(controls, id)
      RuntimeDispatchCancelApplied(context~)
    },
  )
  result
}

///|
fn runtime_cancel_active_tasks(
  tasks : Array[RuntimeTaskControl],
  trace : (RuntimeTraceEvent) -> Unit,
) -> Unit {
  for task in tasks {
    trace(
      runtime_trace_event("runtime", "task_cancelled_on_close", "", "", "task"),
    )
    (task.cancel)()
  }
}

///|
async fn[D] runtime_emit_command_of(
  command : ConnectionCommand,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  queue_limit : Int,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
  dispatch_context : D,
  cancel_inbound : (D, RequestId, Array[RuntimeTaskControl]) -> RuntimeDispatchCancelResult[
    D,
  ] raise RuntimeError,
) -> D raise RuntimeError {
  match command {
    WriteMessage(message) =>
      runtime_writer_offer(writer_queue, queue_limit, message)
    CompleteOutbound(id~, response~) =>
      (ports.handlers.response)(response) catch {
        _ => {
          (ports.trace)(
            runtime_trace_event(
              "inbound",
              "response_handler_failed",
              runtime_request_id_text(id),
              "",
              "response",
            ),
          )
          raise ResponseHandlerFailed
        }
      }
    DispatchRequest(_) | DispatchNotification(_) => ()
    FailOutbound(id~, reason~) => {
      match ports.handlers.outbound_failure {
        None => raise OutboundCompletionFailed
        Some(callback) =>
          callback(id, { reason: runtime_outbound_failure_kind(reason) }) catch {
            _ => {
              (ports.trace)(
                runtime_trace_event(
                  "outbound",
                  "outbound_failure_completion_failed",
                  runtime_request_id_text(id),
                  "",
                  "peer",
                ),
              )
              raise OutboundCompletionFailed
            }
          }
      }
      (ports.trace)(
        runtime_trace_event(
          "outbound",
          "outbound_failed",
          runtime_request_id_text(id),
          "",
          "peer",
        ),
      )
    }
    FailInbound(id~, reason=_, cancelled~) => {
      let error = if cancelled {
        JsonRpcError::request_cancelled()
      } else {
        JsonRpcError::internal_error()
      }
      runtime_writer_offer(
        writer_queue,
        queue_limit,
        JsonRpcMessage::response(
          JsonRpcResponse::error(id=connection_response_id_json(id), error~),
        ),
      )
      (ports.trace)(
        runtime_trace_event(
          "inbound",
          "inbound_failed",
          runtime_request_id_text(id),
          "",
          if cancelled {
            "cancel"
          } else {
            "close"
          },
        ),
      )
    }
    CancelOutboundTask(id~) => {
      match ports.cancel_outbound {
        None => raise OutboundCancelUnavailable
        Some(cancel) => cancel(id) catch { _ => raise OutboundCancelFailed }
      }
      (ports.trace)(
        runtime_trace_event(
          "outbound",
          "cancel_requested",
          runtime_request_id_text(id),
          "",
          "cancel",
        ),
      )
    }
    CancelInboundTask(id~) =>
      return runtime_apply_inbound_cancel(
        id, ports, tasks, dispatch_context, cancel_inbound,
      )
    Trace(_) =>
      (ports.trace)(runtime_trace_event("runtime", "reducer_trace", "", "", ""))
  }
  dispatch_context
}

///|
async fn runtime_emit_command(
  command : ConnectionCommand,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  queue_limit : Int,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
) -> Unit raise RuntimeError {
  let _ = runtime_emit_command_of(
    command,
    writer_queue,
    queue_limit,
    ports,
    tasks,
    (),
    (context, id, controls) => {
      runtime_cancel_task(controls, id)
      RuntimeDispatchCancelApplied(context~)
    },
  )
}

///|
async fn[G, D] runtime_apply_step(
  group : @async.TaskGroup[G],
  step : ConnectionStep,
  state_ref : Ref[ConnectionState],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  dispatch : RuntimeDispatchPort[G, D],
  dispatch_context : D,
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
) -> (Array[RuntimeTaskControl], Int, D, RuntimeApplyControl) raise RuntimeError {
  let mut next_tasks = Array::copy(tasks)
  let mut next_token = next_task_token
  let mut next_context = dispatch_context
  for command in step.commands {
    match command {
      DispatchRequest(request) => {
        let action = (dispatch.request)(
          group, next_token, request, next_context,
        ) catch {
          error => {
            (ports.trace)(
              runtime_trace_event(
                "runtime",
                "dispatch_failed",
                "",
                "",
                runtime_error_kind(error),
              ),
            )
            raise error
          }
        }
        match action {
          RuntimeDispatchSpawned(context~, task~, next_task_token~) => {
            next_tasks.push(task)
            next_token = next_task_token
            next_context = context
          }
          RuntimeDispatchRequestImmediate(context~, event~, commands~) => {
            let completion_step = connection_reduce(state_ref.val, event) catch {
              _ => raise ReducerFailed
            }
            state_ref.val = completion_step.state
            let (updated_tasks, updated_token, updated_context, control) = runtime_apply_step(
              group, completion_step, state_ref, writer_queue, options, ports, dispatch,
              context, next_tasks, next_token,
            )
            match control {
              RuntimeApplyContinue => {
                let (owner_context, command_result) = runtime_apply_owner_commands_of(
                  commands,
                  writer_queue,
                  options,
                  ports,
                  updated_tasks,
                  updated_context,
                  dispatch.cancel_inbound,
                )
                next_context = owner_context
                next_token = updated_token
                let next_control = match command_result {
                  RuntimeOwnerCommandsComplete => RuntimeApplyContinue
                  RuntimeOwnerCloseRequested(reason~) =>
                    RuntimeApplyOwnerClose(reason~)
                }
                match next_control {
                  RuntimeApplyContinue => next_tasks = updated_tasks
                  RuntimeApplyOwnerClose(reason~) =>
                    return (
                      updated_tasks,
                      updated_token,
                      owner_context,
                      RuntimeApplyOwnerClose(reason~),
                    )
                }
              }
              RuntimeApplyOwnerClose(reason~) =>
                return (
                  updated_tasks,
                  updated_token,
                  updated_context,
                  RuntimeApplyOwnerClose(reason~),
                )
            }
          }
          RuntimeDispatchNotificationImmediate(..) => raise ReducerFailed
        }
      }
      DispatchNotification(notification) => {
        let action = (dispatch.notification)(
          group, next_token, notification, next_context,
        ) catch {
          error => {
            (ports.trace)(
              runtime_trace_event(
                "runtime",
                "dispatch_failed",
                "",
                "",
                runtime_error_kind(error),
              ),
            )
            raise error
          }
        }
        match action {
          RuntimeDispatchSpawned(context~, task~, next_task_token~) => {
            next_tasks.push(task)
            next_token = next_task_token
            next_context = context
          }
          RuntimeDispatchRequestImmediate(..) => raise ReducerFailed
          RuntimeDispatchNotificationImmediate(context~, commands~) => {
            let (owner_context, command_result) = runtime_apply_owner_commands_of(
              commands,
              writer_queue,
              options,
              ports,
              next_tasks,
              context,
              dispatch.cancel_inbound,
            )
            next_context = owner_context
            match command_result {
              RuntimeOwnerCommandsComplete => ()
              RuntimeOwnerCloseRequested(reason~) =>
                return (
                  next_tasks,
                  next_token,
                  next_context,
                  RuntimeApplyOwnerClose(reason~),
                )
            }
          }
        }
      }
      command =>
        next_context = runtime_emit_command_of(
          command,
          writer_queue,
          options.queue_capacity,
          ports,
          next_tasks,
          next_context,
          dispatch.cancel_inbound,
        ) catch {
          error => {
            (ports.trace)(
              runtime_trace_event(
                "runtime",
                "command_failed",
                "",
                "",
                runtime_error_kind(error),
              ),
            )
            raise error
          }
        }
    }
  }
  (next_tasks, next_token, next_context, RuntimeApplyContinue)
}

///|
async fn[G, D] runtime_apply_message(
  group : @async.TaskGroup[G],
  state : ConnectionState,
  frame : String,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  dispatch : RuntimeDispatchPort[G, D],
  dispatch_context : D,
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> (ConnectionState, Array[RuntimeTaskControl], Int, D, RuntimeApplyControl) raise RuntimeError {
  let message = jsonrpc_decode(frame) catch {
    _ => {
      shutdown.val = true
      (ports.trace)(
        runtime_trace_event("inbound", "decode_failed", "", "", "jsonrpc"),
      )
      raise JsonRpcDecodeFailed
    }
  }
  let event = match message {
    Request(request) => IncomingRequest(request)
    Notification(notification) => IncomingNotification(notification)
    Response(response) => IncomingResponse(response)
  }
  let step = connection_reduce(state, event) catch {
    _ => {
      shutdown.val = true
      (ports.trace)(
        runtime_trace_event("inbound", "reducer_failed", "", "", "reducer"),
      )
      raise ReducerFailed
    }
  }
  let state_ref = Ref::Ref(step.state)
  let (next_tasks, next_token, next_context, control) = runtime_apply_step(
    group, step, state_ref, writer_queue, options, ports, dispatch, dispatch_context,
    tasks, next_task_token,
  )
  (state_ref.val, next_tasks, next_token, next_context, control)
}

///|
/// Interpret a reducer close step one command at a time.  A failed command
/// stops interpretation immediately, so successful outbound failure
/// callbacks are never replayed during cleanup.  The current and remaining
/// inbound failure commands are the only ones that can be reported as
/// unwritten.
async fn runtime_apply_close_step(
  step : ConnectionStep,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
) -> Unit raise RuntimeError {
  for index, command in step.commands.iter2() {
    runtime_emit_command(
      command,
      writer_queue,
      options.queue_capacity,
      ports,
      tasks,
    ) catch {
      error => {
        (ports.trace)(
          runtime_trace_event(
            "runtime",
            "command_failed",
            "",
            "",
            runtime_error_kind(error),
          ),
        )
        for remaining_index, remaining in step.commands.iter2() {
          if remaining_index >= index {
            match remaining {
              FailInbound(id~, cancelled~, ..) =>
                (ports.trace)(
                  runtime_trace_event(
                    "inbound",
                    "inbound_failure_unwritten",
                    runtime_request_id_text(id),
                    "",
                    if cancelled {
                      "cancel"
                    } else {
                      "writer"
                    },
                  ),
                )
              _ => ()
            }
          }
        }
        raise error
      }
    }
  }
}

///|
/// Run the reducer's close transition before stopping native tasks. The
/// reducer remains the sole owner of pending protocol state; this function
/// only interprets the resulting commands and then cancels runtime work.
fn[D] runtime_close_owner_noop(
  context : D,
  _tasks : Array[RuntimeTaskControl],
) -> D raise RuntimeError {
  context
}

///|
async fn[G, C, D] runtime_close_connection_of(
  _group : @async.TaskGroup[G],
  state : ConnectionState,
  reason : String,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  _events : @aqueue.Queue[RuntimeEventOf[C]],
  tasks : Array[RuntimeTaskControl],
  _next_task_token : Int,
  shutdown : Ref[Bool],
  force_close_writer : Bool,
  dispatch_context : D,
  close_owner : (D, Array[RuntimeTaskControl]) -> D raise RuntimeError,
) -> D raise RuntimeError {
  shutdown.val = true
  let closed_context = close_owner(dispatch_context, tasks)
  let step = connection_reduce(state, Close(reason~)) catch {
    _ => raise ReducerFailed
  }
  runtime_apply_close_step(step, writer_queue, options, ports, tasks) catch {
    error => {
      runtime_cancel_active_tasks(tasks, ports.trace)
      runtime_writer_stop(writer_queue, true) catch {
        cleanup => raise runtime_close_cleanup_error(error, cleanup)
      }
      raise error
    }
  }
  runtime_cancel_active_tasks(tasks, ports.trace)
  runtime_writer_stop(writer_queue, force_close_writer)
  closed_context
}

///|
async fn[G, C] runtime_close_connection(
  group : @async.TaskGroup[G],
  state : ConnectionState,
  reason : String,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
  force_close_writer : Bool,
) -> Unit raise RuntimeError {
  let _ = runtime_close_connection_of(
    group,
    state,
    reason,
    writer_queue,
    options,
    ports,
    events,
    tasks,
    next_task_token,
    shutdown,
    force_close_writer,
    (),
    runtime_close_owner_noop,
  )
}

///|
/// Close after a primary runtime failure. A cleanup failure is represented as
/// a category pair so neither the original failure nor cleanup failure is
/// silently discarded, and no arbitrary error payload crosses the boundary.
async fn[G, C, D, T] runtime_fail_and_close_of(
  group : @async.TaskGroup[G],
  state : ConnectionState,
  reason : String,
  primary : RuntimeError,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
  force_close_writer : Bool,
  dispatch_context : D,
  close_owner : (D, Array[RuntimeTaskControl]) -> D raise RuntimeError,
) -> T raise RuntimeError {
  let _ = runtime_close_connection_of(
    group, state, reason, writer_queue, options, ports, events, tasks, next_task_token,
    shutdown, force_close_writer, dispatch_context, close_owner,
  ) catch {
    cleanup => raise runtime_close_cleanup_error(primary, cleanup)
  }
  raise primary
}

///|
async fn[G, C, T] runtime_fail_and_close(
  group : @async.TaskGroup[G],
  state : ConnectionState,
  reason : String,
  primary : RuntimeError,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
  force_close_writer : Bool,
) -> T raise RuntimeError {
  runtime_fail_and_close_of(
    group,
    state,
    reason,
    primary,
    writer_queue,
    options,
    ports,
    events,
    tasks,
    next_task_token,
    shutdown,
    force_close_writer,
    (),
    runtime_close_owner_noop,
  )
}

///|
/// Read one owner-loop event and normalize queue closure to the runtime's
/// structured error. Keeping this seam separate makes queue shutdown
/// observable without duplicating close handling in the main loop.
async fn[C] runtime_event_get(
  events : @aqueue.Queue[RuntimeEventOf[C]],
) -> RuntimeEventOf[C] raise RuntimeError {
  events.get() catch {
    _ => raise EventQueueClosed
  }
}

///|
priv struct RuntimeEventStep {
  state : ConnectionState
  decoder : FramingState
  tasks : Array[RuntimeTaskControl]
  next_task_token : Int
  stop : Bool
}

///|
fn[D] runtime_event_step(
  step : RuntimeEventStep,
  dispatch_context : D,
) -> (RuntimeEventStep, D) {
  (step, dispatch_context)
}

///|
/// Apply one request completion after its runtime task control has been
/// removed. `owner_commands` are deliberately interpreted only after the
/// reducer's response command, preserving response-before-effects order.
async fn[G, C, D] runtime_apply_request_completion(
  id : RequestId,
  result : RuntimeHandlerResult,
  owner_commands : Array[RuntimeOwnerCommand],
  late_phase : String,
  state : ConnectionState,
  decoder : FramingState,
  group : @async.TaskGroup[G],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  dispatch : RuntimeDispatchPort[G, D],
  dispatch_context : D,
  remaining_tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> (RuntimeEventStep, D) raise RuntimeError {
  match connection_inbound_index(state.inbound, id) {
    None => {
      (ports.trace)(
        runtime_trace_event(
          "inbound",
          late_phase,
          runtime_request_id_text(id),
          "",
          "late",
        ),
      )
      runtime_event_step(
        { state, decoder, tasks: remaining_tasks, next_task_token, stop: false },
        dispatch_context,
      )
    }
    Some(_) => {
      let incoming = match result {
        HandlerSuccess(result) => IncomingCompleted(id~, result~)
        HandlerError(error) => IncomingFailed(id~, error~)
      }
      let step = connection_reduce(state, incoming) catch {
        _ => {
          (ports.trace)(
            runtime_trace_event(
              "inbound",
              "handler_reducer_failed",
              runtime_request_id_text(id),
              "",
              "reducer",
            ),
          )
          runtime_fail_and_close_of(
            group,
            state,
            "completion",
            ReducerFailed,
            writer_queue,
            options,
            ports,
            events,
            remaining_tasks,
            next_task_token,
            shutdown,
            false,
            dispatch_context,
            dispatch.close_owner,
          )
        }
      }
      let state_ref = Ref::Ref(step.state)
      let (updated_tasks, updated_token, updated_context, control) = runtime_apply_step(
        group, step, state_ref, writer_queue, options, ports, dispatch, dispatch_context,
        remaining_tasks, next_task_token,
      ) catch {
        error =>
          runtime_fail_and_close_of(
            group,
            state_ref.val,
            "completion",
            error,
            writer_queue,
            options,
            ports,
            events,
            remaining_tasks,
            next_task_token,
            shutdown,
            false,
            dispatch_context,
            dispatch.close_owner,
          )
      }
      match control {
        RuntimeApplyContinue => {
          let (owner_context, command_result) = runtime_apply_owner_commands_of(
            owner_commands,
            writer_queue,
            options,
            ports,
            updated_tasks,
            updated_context,
            dispatch.cancel_inbound,
          ) catch {
            error =>
              runtime_fail_and_close_of(
                group,
                state_ref.val,
                "completion",
                error,
                writer_queue,
                options,
                ports,
                events,
                updated_tasks,
                updated_token,
                shutdown,
                false,
                updated_context,
                dispatch.close_owner,
              )
          }
          match command_result {
            RuntimeOwnerCommandsComplete =>
              runtime_event_step(
                {
                  state: state_ref.val,
                  decoder,
                  tasks: updated_tasks,
                  next_task_token: updated_token,
                  stop: false,
                },
                owner_context,
              )
            RuntimeOwnerCloseRequested(_) => {
              let closed_context = runtime_close_connection_of(
                group,
                state_ref.val,
                "owner",
                writer_queue,
                options,
                ports,
                events,
                updated_tasks,
                updated_token,
                shutdown,
                false,
                owner_context,
                dispatch.close_owner,
              )
              runtime_event_step(
                {
                  state: state_ref.val,
                  decoder,
                  tasks: [],
                  next_task_token: updated_token,
                  stop: true,
                },
                closed_context,
              )
            }
          }
        }
        RuntimeApplyOwnerClose(_) => {
          let closed_context = runtime_close_connection_of(
            group,
            state_ref.val,
            "owner",
            writer_queue,
            options,
            ports,
            events,
            updated_tasks,
            updated_token,
            shutdown,
            false,
            updated_context,
            dispatch.close_owner,
          )
          runtime_event_step(
            {
              state: state_ref.val,
              decoder,
              tasks: [],
              next_task_token: updated_token,
              stop: true,
            },
            closed_context,
          )
        }
      }
    }
  }
}

///|
/// Apply a notification completion and its effects through the same owner
/// command interpreter. There is intentionally no reducer response step.
async fn[G, C, D] runtime_apply_notification_completion(
  owner_commands : Array[RuntimeOwnerCommand],
  state : ConnectionState,
  decoder : FramingState,
  group : @async.TaskGroup[G],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  dispatch : RuntimeDispatchPort[G, D],
  dispatch_context : D,
  remaining_tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> (RuntimeEventStep, D) raise RuntimeError {
  let (owner_context, command_result) = runtime_apply_owner_commands_of(
    owner_commands,
    writer_queue,
    options,
    ports,
    remaining_tasks,
    dispatch_context,
    dispatch.cancel_inbound,
  ) catch {
    error =>
      runtime_fail_and_close_of(
        group,
        state,
        "completion",
        error,
        writer_queue,
        options,
        ports,
        events,
        remaining_tasks,
        next_task_token,
        shutdown,
        false,
        dispatch_context,
        dispatch.close_owner,
      )
  }
  match command_result {
    RuntimeOwnerCommandsComplete => {
      (ports.trace)(
        runtime_trace_event("runtime", "task_completed", "", "", "notification"),
      )
      runtime_event_step(
        { state, decoder, tasks: remaining_tasks, next_task_token, stop: false },
        owner_context,
      )
    }
    RuntimeOwnerCloseRequested(_) => {
      let closed_context = runtime_close_connection_of(
        group,
        state,
        "owner",
        writer_queue,
        options,
        ports,
        events,
        remaining_tasks,
        next_task_token,
        shutdown,
        false,
        owner_context,
        dispatch.close_owner,
      )
      runtime_event_step(
        { state, decoder, tasks: [], next_task_token, stop: true },
        closed_context,
      )
    }
  }
}

///|
/// The single owner-loop event seam. Every reader, writer, handler, and
/// notification event is admitted here; late task events are traced and
/// ignored, while primary failures close through one typed path.
async fn[G, C, D] runtime_apply_event_of(
  event : RuntimeEventOf[C],
  state : ConnectionState,
  decoder : FramingState,
  group : @async.TaskGroup[G],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEventOf[C]],
  event_to_result : (C) -> RuntimeHandlerResult,
  dispatch : RuntimeDispatchPort[G, D],
  owner_event : (
    RuntimeOwnerTaskEventOf[C],
    ConnectionState,
    D,
    Array[RuntimeTaskControl],
  ) -> RuntimeOwnerTaskApply[D] raise RuntimeError,
  dispatch_context : D,
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> (RuntimeEventStep, D) raise RuntimeError {
  let mut next_context = dispatch_context
  match event {
    RuntimeChunk(chunk) => {
      let frame_step = framing_feed(decoder, chunk) catch {
        _ => {
          (ports.trace)(
            runtime_trace_event("inbound", "framing_failed", "", "", "framing"),
          )
          runtime_fail_and_close_of(
            group,
            state,
            "framing",
            FramingFailed,
            writer_queue,
            options,
            ports,
            events,
            tasks,
            next_task_token,
            shutdown,
            false,
            next_context,
            dispatch.close_owner,
          )
        }
      }
      let mut next_state = state
      let mut next_tasks = tasks
      let mut next_token = next_task_token
      for frame in frame_step.frames {
        let next = runtime_apply_message(
          group, next_state, frame, writer_queue, options, ports, dispatch, next_context,
          next_tasks, next_token, shutdown,
        ) catch {
          error =>
            runtime_fail_and_close_of(
              group,
              next_state,
              "protocol",
              error,
              writer_queue,
              options,
              ports,
              events,
              next_tasks,
              next_token,
              shutdown,
              false,
              next_context,
              dispatch.close_owner,
            )
        }
        let (
          updated_state,
          updated_tasks,
          updated_token,
          updated_context,
          control,
        ) = next
        next_state = updated_state
        next_tasks = updated_tasks
        next_token = updated_token
        next_context = updated_context
        match control {
          RuntimeApplyContinue => ()
          RuntimeApplyOwnerClose(_) => {
            let closed_context = runtime_close_connection_of(
              group,
              next_state,
              "owner",
              writer_queue,
              options,
              ports,
              events,
              next_tasks,
              next_token,
              shutdown,
              false,
              next_context,
              dispatch.close_owner,
            )
            return runtime_event_step(
              {
                state: next_state,
                decoder: frame_step.state,
                tasks: [],
                next_task_token: next_token,
                stop: true,
              },
              closed_context,
            )
          }
        }
      }
      runtime_event_step(
        {
          state: next_state,
          decoder: frame_step.state,
          tasks: next_tasks,
          next_task_token: next_token,
          stop: false,
        },
        next_context,
      )
    }
    RuntimeReaderFailed(error) => {
      (ports.trace)(
        runtime_trace_event("inbound", "reader_failed", "", "", "reader"),
      )
      runtime_fail_and_close_of(
        group,
        state,
        "reader",
        error,
        writer_queue,
        options,
        ports,
        events,
        tasks,
        next_task_token,
        shutdown,
        false,
        next_context,
        dispatch.close_owner,
      )
    }
    RuntimeWriterFailed(error) => {
      (ports.trace)(
        runtime_trace_event("outbound", "writer_failed", "", "", "writer"),
      )
      runtime_fail_and_close_of(
        group,
        state,
        "writer",
        error,
        writer_queue,
        options,
        ports,
        events,
        tasks,
        next_task_token,
        shutdown,
        true,
        next_context,
        dispatch.close_owner,
      )
    }
    RuntimeOwnerTaskEvent(task_event) => {
      let applied = owner_event(task_event, state, next_context, tasks) catch {
        error => {
          (ports.trace)(
            runtime_trace_event(
              "runtime",
              "owner_task_failed",
              "",
              "",
              runtime_error_kind(error),
            ),
          )
          runtime_fail_and_close_of(
            group,
            state,
            "owner",
            error,
            writer_queue,
            options,
            ports,
            events,
            tasks,
            next_task_token,
            shutdown,
            false,
            next_context,
            dispatch.close_owner,
          )
        }
      }
      match applied {
        RuntimeOwnerEventIgnored(context~, task_token~, request_id~, reason~) => {
          let (remaining_tasks, _) = runtime_take_task(tasks, task_token)
          let phase = match reason {
            Closed | UnknownTask(_) | UnknownRequest(_) | AlreadyCancelled(_) =>
              "late_owner_completion_ignored"
            RequestIdMismatch(..) | TaskKindMismatch(_) => "owner_task_mismatch"
          }
          (ports.trace)(
            runtime_trace_event(
              "inbound",
              phase,
              match request_id {
                Some(id) => runtime_request_id_text(id)
                None => ""
              },
              "",
              "late",
            ),
          )
          runtime_event_step(
            {
              state,
              decoder,
              tasks: remaining_tasks,
              next_task_token,
              stop: false,
            },
            context,
          )
        }
        RuntimeOwnerRequestCompletion(
          context~,
          task_token~,
          id~,
          result~,
          commands~
        ) => {
          let (remaining_tasks, taken) = runtime_take_task(tasks, task_token)
          match taken {
            None => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "late_owner_completion_ignored",
                  runtime_request_id_text(id),
                  "",
                  "late",
                ),
              )
              runtime_event_step(
                { state, decoder, tasks, next_task_token, stop: false },
                next_context,
              )
            }
            Some(_) =>
              runtime_apply_request_completion(
                id, result, commands, "late_owner_completion_ignored", state, decoder,
                group, writer_queue, options, ports, events, dispatch, context, remaining_tasks,
                next_task_token, shutdown,
              )
          }
        }
        RuntimeOwnerNotificationCompletion(context~, task_token~, commands~) => {
          let (remaining_tasks, taken) = runtime_take_task(tasks, task_token)
          match taken {
            None => {
              (ports.trace)(
                runtime_trace_event(
                  "runtime", "late_owner_notification_ignored", "", "", "late",
                ),
              )
              runtime_event_step(
                { state, decoder, tasks, next_task_token, stop: false },
                next_context,
              )
            }
            Some(_) =>
              runtime_apply_notification_completion(
                commands, state, decoder, group, writer_queue, options, ports, events,
                dispatch, context, remaining_tasks, next_task_token, shutdown,
              )
          }
        }
      }
    }
    RuntimeHandlerCompleted(task_token, id, result) => {
      match runtime_find_task(tasks, task_token) {
        None => ()
        Some(task) =>
          match task.request_id {
            Some(expected) if expected == id => ()
            _ => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "task_request_mismatch",
                  runtime_request_id_text(id),
                  "",
                  "task_control",
                ),
              )
              runtime_fail_and_close_of(
                group,
                state,
                "task_mismatch",
                TaskRequestMismatch,
                writer_queue,
                options,
                ports,
                events,
                tasks,
                next_task_token,
                shutdown,
                false,
                next_context,
                dispatch.close_owner,
              )
            }
          }
      }
      let (remaining_tasks, token) = runtime_take_task(tasks, task_token)
      match token {
        None => {
          (ports.trace)(
            runtime_trace_event(
              "inbound",
              "late_handler_completion_ignored",
              runtime_request_id_text(id),
              "",
              "late",
            ),
          )
          runtime_event_step(
            { state, decoder, tasks, next_task_token, stop: false },
            next_context,
          )
        }
        Some(_) =>
          match connection_inbound_index(state.inbound, id) {
            None => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "late_handler_completion_ignored",
                  runtime_request_id_text(id),
                  "",
                  "late",
                ),
              )
              runtime_event_step(
                {
                  state,
                  decoder,
                  tasks: remaining_tasks,
                  next_task_token,
                  stop: false,
                },
                next_context,
              )
            }
            Some(_) => {
              let incoming = match event_to_result(result) {
                HandlerSuccess(result) => IncomingCompleted(id~, result~)
                HandlerError(error) => IncomingFailed(id~, error~)
              }
              let step = connection_reduce(state, incoming) catch {
                _ => {
                  (ports.trace)(
                    runtime_trace_event(
                      "inbound",
                      "handler_reducer_failed",
                      runtime_request_id_text(id),
                      "",
                      "reducer",
                    ),
                  )
                  runtime_fail_and_close_of(
                    group,
                    state,
                    "completion",
                    ReducerFailed,
                    writer_queue,
                    options,
                    ports,
                    events,
                    remaining_tasks,
                    next_task_token,
                    shutdown,
                    false,
                    next_context,
                    dispatch.close_owner,
                  )
                }
              }
              let state_ref = Ref::Ref(step.state)
              let (updated_tasks, updated_token, updated_context, control) = runtime_apply_step(
                group, step, state_ref, writer_queue, options, ports, dispatch, next_context,
                remaining_tasks, next_task_token,
              ) catch {
                error =>
                  runtime_fail_and_close_of(
                    group,
                    state_ref.val,
                    "completion",
                    error,
                    writer_queue,
                    options,
                    ports,
                    events,
                    remaining_tasks,
                    next_task_token,
                    shutdown,
                    false,
                    next_context,
                    dispatch.close_owner,
                  )
              }
              match control {
                RuntimeApplyContinue => {
                  next_context = updated_context
                  runtime_event_step(
                    {
                      state: state_ref.val,
                      decoder,
                      tasks: updated_tasks,
                      next_task_token: updated_token,
                      stop: false,
                    },
                    next_context,
                  )
                }
                RuntimeApplyOwnerClose(_) => {
                  let closed_context = runtime_close_connection_of(
                    group,
                    state_ref.val,
                    "owner",
                    writer_queue,
                    options,
                    ports,
                    events,
                    updated_tasks,
                    updated_token,
                    shutdown,
                    false,
                    updated_context,
                    dispatch.close_owner,
                  )
                  runtime_event_step(
                    {
                      state: state_ref.val,
                      decoder,
                      tasks: [],
                      next_task_token: updated_token,
                      stop: true,
                    },
                    closed_context,
                  )
                }
              }
            }
          }
      }
    }
    RuntimeHandlerFailed(task_token, id) => {
      match runtime_find_task(tasks, task_token) {
        None => ()
        Some(task) =>
          match task.request_id {
            Some(expected) if expected == id => ()
            _ => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "task_request_mismatch",
                  runtime_request_id_text(id),
                  "",
                  "task_control",
                ),
              )
              runtime_fail_and_close(
                group,
                state,
                "task_mismatch",
                TaskRequestMismatch,
                writer_queue,
                options,
                ports,
                events,
                tasks,
                next_task_token,
                shutdown,
                false,
              )
            }
          }
      }
      let (remaining_tasks, token) = runtime_take_task(tasks, task_token)
      match token {
        None => {
          (ports.trace)(
            runtime_trace_event(
              "inbound",
              "late_handler_failure_ignored",
              runtime_request_id_text(id),
              "",
              "late",
            ),
          )
          runtime_event_step(
            { state, decoder, tasks, next_task_token, stop: false },
            next_context,
          )
        }
        Some(_) =>
          match connection_inbound_index(state.inbound, id) {
            None => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "late_handler_failure_ignored",
                  runtime_request_id_text(id),
                  "",
                  "late",
                ),
              )
              runtime_event_step(
                {
                  state,
                  decoder,
                  tasks: remaining_tasks,
                  next_task_token,
                  stop: false,
                },
                next_context,
              )
            }
            Some(index) if state.inbound[index].cancel_requested => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "handler_failed_after_cancel",
                  runtime_request_id_text(id),
                  "",
                  "handler",
                ),
              )
              let step = connection_reduce(
                state,
                IncomingFailed(id~, error=JsonRpcError::internal_error()),
              ) catch {
                _ =>
                  runtime_fail_and_close(
                    group,
                    state,
                    "completion",
                    ReducerFailed,
                    writer_queue,
                    options,
                    ports,
                    events,
                    remaining_tasks,
                    next_task_token,
                    shutdown,
                    false,
                  )
              }
              let state_ref = Ref::Ref(step.state)
              let (updated_tasks, updated_token, updated_context, control) = runtime_apply_step(
                group, step, state_ref, writer_queue, options, ports, dispatch, next_context,
                remaining_tasks, next_task_token,
              ) catch {
                error =>
                  runtime_fail_and_close(
                    group,
                    state_ref.val,
                    "completion",
                    error,
                    writer_queue,
                    options,
                    ports,
                    events,
                    remaining_tasks,
                    next_task_token,
                    shutdown,
                    false,
                  )
              }
              match control {
                RuntimeApplyContinue => {
                  next_context = updated_context
                  runtime_event_step(
                    {
                      state: state_ref.val,
                      decoder,
                      tasks: updated_tasks,
                      next_task_token: updated_token,
                      stop: false,
                    },
                    next_context,
                  )
                }
                RuntimeApplyOwnerClose(_) => {
                  let closed_context = runtime_close_connection_of(
                    group,
                    state_ref.val,
                    "owner",
                    writer_queue,
                    options,
                    ports,
                    events,
                    updated_tasks,
                    updated_token,
                    shutdown,
                    false,
                    updated_context,
                    dispatch.close_owner,
                  )
                  runtime_event_step(
                    {
                      state: state_ref.val,
                      decoder,
                      tasks: [],
                      next_task_token: updated_token,
                      stop: true,
                    },
                    closed_context,
                  )
                }
              }
            }
            Some(_) => {
              (ports.trace)(
                runtime_trace_event(
                  "inbound",
                  "handler_failed",
                  runtime_request_id_text(id),
                  "",
                  "handler",
                ),
              )
              runtime_fail_and_close(
                group,
                state,
                "handler",
                HandlerFailed,
                writer_queue,
                options,
                ports,
                events,
                remaining_tasks,
                next_task_token,
                shutdown,
                false,
              )
            }
          }
      }
    }
    RuntimeNotificationCompleted(task_token) => {
      let (remaining_tasks, token) = runtime_take_task(tasks, task_token)
      match token {
        None => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "late_notification_ignored", "", "", "late",
            ),
          )
          runtime_event_step(
            { state, decoder, tasks, next_task_token, stop: false },
            next_context,
          )
        }
        Some(_) => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "task_completed", "", "", "notification",
            ),
          )
          runtime_event_step(
            {
              state,
              decoder,
              tasks: remaining_tasks,
              next_task_token,
              stop: false,
            },
            next_context,
          )
        }
      }
    }
    RuntimeNotificationCancelled(task_token) => {
      let (remaining_tasks, token) = runtime_take_task(tasks, task_token)
      match token {
        None => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "late_notification_ignored", "", "", "late",
            ),
          )
          runtime_event_step(
            { state, decoder, tasks, next_task_token, stop: false },
            next_context,
          )
        }
        Some(_) => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "task_cancelled", "", "", "notification",
            ),
          )
          runtime_event_step(
            {
              state,
              decoder,
              tasks: remaining_tasks,
              next_task_token,
              stop: false,
            },
            next_context,
          )
        }
      }
    }
    RuntimeNotificationFailed(task_token) => {
      let (remaining_tasks, token) = runtime_take_task(tasks, task_token)
      match token {
        None => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "late_notification_ignored", "", "", "late",
            ),
          )
          runtime_event_step(
            { state, decoder, tasks, next_task_token, stop: false },
            next_context,
          )
        }
        Some(_) => {
          (ports.trace)(
            runtime_trace_event(
              "inbound", "notification_failed", "", "", "handler",
            ),
          )
          runtime_fail_and_close(
            group,
            state,
            "notification",
            NotificationFailed,
            writer_queue,
            options,
            ports,
            events,
            remaining_tasks,
            next_task_token,
            shutdown,
            false,
          )
        }
      }
    }
    RuntimeEof => {
      let _ = framing_finish(decoder) catch {
        _ => {
          (ports.trace)(
            runtime_trace_event(
              "inbound", "eof_partial_frame", "", "", "framing",
            ),
          )
          runtime_fail_and_close(
            group,
            state,
            "eof",
            FramingFailed,
            writer_queue,
            options,
            ports,
            events,
            tasks,
            next_task_token,
            shutdown,
            false,
          )
        }
      }
      runtime_close_connection(
        group, state, "eof", writer_queue, options, ports, events, tasks, next_task_token,
        shutdown, false,
      )
      runtime_event_step(
        { state, decoder, tasks: [], next_task_token, stop: true },
        next_context,
      )
    }
  }
}

///|
/// Run the one native connection loop with a caller-selected dispatch state.
/// The factory runs only after all connection-local queues and shutdown state
/// exist, so every dispatch closure is scoped to this connection and the
/// task-group type is the same one used by the owner loop.
async fn[G, C, D] runtime_connection_engine_with_dispatch_of(
  group : @async.TaskGroup[G],
  ports : RuntimePorts,
  options : RuntimeOptions,
  dispatch_factory : (@aqueue.Queue[RuntimeEventOf[C]], Ref[Bool]) -> (
    RuntimeDispatchPort[G, D],
    D,
  ),
  event_to_result : (C) -> RuntimeHandlerResult,
  owner_event : (
    RuntimeOwnerTaskEventOf[C],
    ConnectionState,
    D,
    Array[RuntimeTaskControl],
  ) -> RuntimeOwnerTaskApply[D] raise RuntimeError,
) -> D {
  let events : @aqueue.Queue[RuntimeEventOf[C]] = Queue(
    kind=Blocking(options.queue_capacity),
  )
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(
    kind=Blocking(options.queue_capacity),
  )
  let shutdown = Ref::Ref(false)
  let (dispatch, initial_context) = dispatch_factory(events, shutdown)
  let mut dispatch_context = initial_context
  group.spawn_bg(() => {
    runtime_reader_loop(
      ports.reader,
      events,
      options.queue_capacity,
      options.read_chunk_bytes,
    )
  })
  group.spawn_bg(() => {
    runtime_writer_loop(
      ports.writer,
      writer_queue,
      ports.trace,
      events,
      options.queue_capacity,
      shutdown,
    )
  })
  let mut state = connection_state()
  let mut decoder = framing_state(max_frame_bytes=options.max_frame_bytes)
  let mut tasks : Array[RuntimeTaskControl] = []
  let mut next_task_token = 0
  for ;; {
    let event = runtime_event_get(events) catch {
      _ =>
        runtime_fail_and_close(
          group,
          state,
          "event_queue",
          EventQueueClosed,
          writer_queue,
          options,
          ports,
          events,
          tasks,
          next_task_token,
          shutdown,
          false,
        )
    }
    let (step, next_context) = runtime_apply_event_of(
      event, state, decoder, group, writer_queue, options, ports, events, event_to_result,
      dispatch, owner_event, dispatch_context, tasks, next_task_token, shutdown,
    )
    state = step.state
    decoder = step.decoder
    tasks = step.tasks
    next_task_token = step.next_task_token
    dispatch_context = next_context
    if step.stop {
      break
    }
  }
  dispatch_context
}

///|
/// Compatibility wrapper for the legacy handler result queue. It keeps the
/// existing test seam and legacy runner on the same single generic engine.
async fn[G, D] runtime_connection_engine_with_dispatch(
  group : @async.TaskGroup[G],
  ports : RuntimePorts,
  options : RuntimeOptions,
  dispatch_factory : (@aqueue.Queue[RuntimeEvent], Ref[Bool]) -> (
    RuntimeDispatchPort[G, D],
    D,
  ),
) -> D {
  runtime_connection_engine_with_dispatch_of(
    group, ports, options, dispatch_factory, runtime_identity_handler_result, runtime_owner_event_unavailable,
  )
}

///|
/// Run one native connection with the legacy handler dispatch adapter. The
/// generic owner loop above remains the only reducer/event loop.
async fn runtime_connection_engine(
  ports : RuntimePorts,
  options : RuntimeOptions,
) -> Unit {
  runtime_validate_options(options)
  let _ = @async.with_task_group(group => {
    runtime_connection_engine_with_dispatch(group, ports, options, (
      events,
      shutdown,
    ) => {
      let context : RuntimeLegacySpawnContext[RuntimeHandlerResult] = {
        shutdown,
        handlers: ports.handlers,
        events,
        result_to_event: runtime_identity_handler_result,
        limit: options.queue_capacity,
      }
      (runtime_legacy_dispatch_port(), context)
    })
  })
}

///|
pub async fn[S, I, C, E] connection_runtime_run_owner(
  ports : RuntimePorts,
  options : RuntimeOptions,
  owner_port : RuntimeOwnerPort[S, I, C, E],
) -> Unit {
  runtime_validate_options(options)
  let _ = @async.with_task_group(group => {
    let _ = runtime_connection_engine_with_dispatch_of(
      group,
      ports,
      options,
      (events, shutdown) => {
        let context : RuntimeOwnerDispatchContext[S, I, C, E] = {
          owner: runtime_owner_new(owner_port),
          port: owner_port,
          events,
          shutdown,
          limit: options.queue_capacity,
        }
        (runtime_owner_dispatch_port(), context)
      },
      runtime_owner_handler_result_unavailable,
      runtime_owner_apply_task_event,
    )
  })
}

///|
pub async fn connection_runtime_run(
  ports : RuntimePorts,
  options : RuntimeOptions,
) -> Unit {
  runtime_connection_engine(ports, options)
}
