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
/// connection owner. `RuntimeOwnerRequestInvoke` commits `state` before the
/// invocation is handed to an async task. The task never receives the owner.
pub(all) enum RuntimeOwnerRequestAdmission[S, I, C] {
  RuntimeOwnerRequestImmediate(state~ : S, result~ : C)
  RuntimeOwnerRequestInvoke(state~ : S, invocation~ : I)
}

///|
/// A synchronous admission result for a notification. Notifications never
/// carry a request id and never produce a response in the owner seam.
pub(all) enum RuntimeOwnerNotificationAdmission[S, I] {
  RuntimeOwnerNotificationImmediate(state~ : S)
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
    C,
  ]
  admit_notification : (S, JsonRpcNotification) -> RuntimeOwnerNotificationAdmission[
    S,
    I,
  ]
  execute : async (I) -> C
  /// Produces a redacted/static typed failure completion at the task boundary.
  execute_failure : (S, I) -> C
  /// Produces a typed cancellation completion at the task boundary.
  execute_cancel : (S, I) -> C
  complete_request : (S, RequestId, I, C) -> RuntimeOwnerRequestCompletion[S, E]
  complete_notification : (S, I, C) -> RuntimeOwnerNotificationCompletion[S, E]
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
pub(all) enum RuntimeOwnerRequestAction[I, C] {
  RuntimeOwnerImmediate(result~ : C)
  RuntimeOwnerInvoke(task~ : RuntimeOwnerTask[I])
}

///|
pub(all) enum RuntimeOwnerNotificationAction[I] {
  RuntimeOwnerNotificationImmediate
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
) -> (RuntimeOwner[S, I], RuntimeOwnerRequestAction[I, C]) raise RuntimeOwnerError {
  if owner.closed {
    raise Closed
  }
  match (port.admit_request)(owner.state, request.id, request) {
    RuntimeOwnerRequestImmediate(state~, result~) =>
      ({ ..owner, state, }, RuntimeOwnerImmediate(result~))
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
) -> (RuntimeOwner[S, I], RuntimeOwnerNotificationAction[I]) raise RuntimeOwnerError {
  if owner.closed {
    raise Closed
  }
  match (port.admit_notification)(owner.state, notification) {
    RuntimeOwnerNotificationImmediate(state~) =>
      ({ ..owner, state, }, RuntimeOwnerNotificationImmediate)
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
priv enum RuntimeEvent {
  RuntimeChunk(Bytes)
  RuntimeEof
  RuntimeReaderFailed(RuntimeError)
  RuntimeWriterFailed(RuntimeError)
  RuntimeHandlerCompleted(Int, RequestId, RuntimeHandlerResult)
  RuntimeHandlerFailed(Int, RequestId)
  RuntimeNotificationCompleted(Int)
  RuntimeNotificationFailed(Int)
  RuntimeNotificationCancelled(Int)
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
async fn runtime_reader_loop(
  port : RuntimeReaderPort,
  events : @aqueue.Queue[RuntimeEvent],
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
async fn runtime_writer_loop(
  port : RuntimeWriterPort,
  queue : @aqueue.Queue[RuntimeWriterItem],
  trace : (RuntimeTraceEvent) -> Unit,
  events : @aqueue.Queue[RuntimeEvent],
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
async fn runtime_request_task(
  task_token : Int,
  request : JsonRpcRequest,
  shutdown : Ref[Bool],
  handlers : RuntimeHandlerPort,
  events : @aqueue.Queue[RuntimeEvent],
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
              HandlerError(JsonRpcError::request_cancelled()),
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
      RuntimeHandlerCompleted(task_token, request.id, result),
      limit,
    )
  }
}

///|
async fn runtime_notification_task(
  task_token : Int,
  notification : JsonRpcNotification,
  shutdown : Ref[Bool],
  handlers : RuntimeHandlerPort,
  events : @aqueue.Queue[RuntimeEvent],
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
async fn runtime_emit_command(
  command : ConnectionCommand,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  queue_limit : Int,
  ports : RuntimePorts,
  tasks : Array[RuntimeTaskControl],
) -> Unit raise RuntimeError {
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
    CancelInboundTask(id~) => {
      runtime_cancel_task(tasks, id)
      (ports.trace)(
        runtime_trace_event(
          "inbound",
          "cancel_requested",
          runtime_request_id_text(id),
          "",
          "cancel",
        ),
      )
    }
    Trace(_) =>
      (ports.trace)(runtime_trace_event("runtime", "reducer_trace", "", "", ""))
  }
}

///|
async fn[G] runtime_apply_step(
  group : @async.TaskGroup[G],
  step : ConnectionStep,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEvent],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> (Array[RuntimeTaskControl], Int) raise RuntimeError {
  let next_tasks = Array::copy(tasks)
  let mut next_token = next_task_token
  for command in step.commands {
    match command {
      DispatchRequest(request) => {
        let task_token = next_token
        let task = group.spawn(() => {
          runtime_request_task(
            task_token,
            request,
            shutdown,
            ports.handlers,
            events,
            options.queue_capacity,
          )
        })
        next_tasks.push({
          task_token,
          request_id: Some(request.id),
          cancel: () => task.cancel(),
        })
        next_token = next_token + 1
      }
      DispatchNotification(notification) => {
        let task_token = next_token
        let task = group.spawn(() => {
          runtime_notification_task(
            task_token,
            notification,
            shutdown,
            ports.handlers,
            events,
            options.queue_capacity,
          )
        })
        next_tasks.push({
          task_token,
          request_id: None,
          cancel: () => task.cancel(),
        })
        next_token = next_token + 1
      }
      command =>
        runtime_emit_command(
          command,
          writer_queue,
          options.queue_capacity,
          ports,
          next_tasks,
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
  (next_tasks, next_token)
}

///|
async fn[G] runtime_apply_message(
  group : @async.TaskGroup[G],
  state : ConnectionState,
  frame : String,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEvent],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> (ConnectionState, Array[RuntimeTaskControl], Int) raise RuntimeError {
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
  let (next_tasks, next_token) = runtime_apply_step(
    group, step, writer_queue, options, ports, events, tasks, next_task_token, shutdown,
  )
  (step.state, next_tasks, next_token)
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
async fn[G] runtime_close_connection(
  _group : @async.TaskGroup[G],
  state : ConnectionState,
  reason : String,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  _events : @aqueue.Queue[RuntimeEvent],
  tasks : Array[RuntimeTaskControl],
  _next_task_token : Int,
  shutdown : Ref[Bool],
  force_close_writer : Bool,
) -> Unit raise RuntimeError {
  shutdown.val = true
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
}

///|
/// Close after a primary runtime failure. A cleanup failure is represented as
/// a category pair so neither the original failure nor cleanup failure is
/// silently discarded, and no arbitrary error payload crosses the boundary.
async fn[G, T] runtime_fail_and_close(
  group : @async.TaskGroup[G],
  state : ConnectionState,
  reason : String,
  primary : RuntimeError,
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEvent],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
  force_close_writer : Bool,
) -> T raise RuntimeError {
  runtime_close_connection(
    group, state, reason, writer_queue, options, ports, events, tasks, next_task_token,
    shutdown, force_close_writer,
  ) catch {
    cleanup => raise runtime_close_cleanup_error(primary, cleanup)
  }
  raise primary
}

///|
/// Read one owner-loop event and normalize queue closure to the runtime's
/// structured error. Keeping this seam separate makes queue shutdown
/// observable without duplicating close handling in the main loop.
async fn runtime_event_get(
  events : @aqueue.Queue[RuntimeEvent],
) -> RuntimeEvent raise RuntimeError {
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
/// The single owner-loop event seam. Every reader, writer, handler, and
/// notification event is admitted here; late task events are traced and
/// ignored, while primary failures close through one typed path.
async fn[G] runtime_apply_event(
  event : RuntimeEvent,
  state : ConnectionState,
  decoder : FramingState,
  group : @async.TaskGroup[G],
  writer_queue : @aqueue.Queue[RuntimeWriterItem],
  options : RuntimeOptions,
  ports : RuntimePorts,
  events : @aqueue.Queue[RuntimeEvent],
  tasks : Array[RuntimeTaskControl],
  next_task_token : Int,
  shutdown : Ref[Bool],
) -> RuntimeEventStep raise RuntimeError {
  match event {
    RuntimeChunk(chunk) => {
      let frame_step = framing_feed(decoder, chunk) catch {
        _ => {
          (ports.trace)(
            runtime_trace_event("inbound", "framing_failed", "", "", "framing"),
          )
          runtime_fail_and_close(
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
          )
        }
      }
      let mut next_state = state
      let mut next_tasks = tasks
      let mut next_token = next_task_token
      for frame in frame_step.frames {
        let next = runtime_apply_message(
          group, next_state, frame, writer_queue, options, ports, events, next_tasks,
          next_token, shutdown,
        ) catch {
          error =>
            runtime_fail_and_close(
              group, next_state, "protocol", error, writer_queue, options, ports,
              events, next_tasks, next_token, shutdown, false,
            )
        }
        let (updated_state, updated_tasks, updated_token) = next
        next_state = updated_state
        next_tasks = updated_tasks
        next_token = updated_token
      }
      {
        state: next_state,
        decoder: frame_step.state,
        tasks: next_tasks,
        next_task_token: next_token,
        stop: false,
      }
    }
    RuntimeReaderFailed(error) => {
      (ports.trace)(
        runtime_trace_event("inbound", "reader_failed", "", "", "reader"),
      )
      runtime_fail_and_close(
        group, state, "reader", error, writer_queue, options, ports, events, tasks,
        next_task_token, shutdown, false,
      )
    }
    RuntimeWriterFailed(error) => {
      (ports.trace)(
        runtime_trace_event("outbound", "writer_failed", "", "", "writer"),
      )
      runtime_fail_and_close(
        group, state, "writer", error, writer_queue, options, ports, events, tasks,
        next_task_token, shutdown, true,
      )
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
              "late_handler_completion_ignored",
              runtime_request_id_text(id),
              "",
              "late",
            ),
          )
          { state, decoder, tasks, next_task_token, stop: false }
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
              {
                state,
                decoder,
                tasks: remaining_tasks,
                next_task_token,
                stop: false,
              }
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
              }
              let (updated_tasks, updated_token) = runtime_apply_step(
                group, step, writer_queue, options, ports, events, remaining_tasks,
                next_task_token, shutdown,
              ) catch {
                error =>
                  runtime_fail_and_close(
                    group,
                    step.state,
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
              {
                state: step.state,
                decoder,
                tasks: updated_tasks,
                next_task_token: updated_token,
                stop: false,
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
          { state, decoder, tasks, next_task_token, stop: false }
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
              {
                state,
                decoder,
                tasks: remaining_tasks,
                next_task_token,
                stop: false,
              }
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
              let (updated_tasks, updated_token) = runtime_apply_step(
                group, step, writer_queue, options, ports, events, remaining_tasks,
                next_task_token, shutdown,
              ) catch {
                error =>
                  runtime_fail_and_close(
                    group,
                    step.state,
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
              {
                state: step.state,
                decoder,
                tasks: updated_tasks,
                next_task_token: updated_token,
                stop: false,
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
          { state, decoder, tasks, next_task_token, stop: false }
        }
        Some(_) => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "task_completed", "", "", "notification",
            ),
          )
          {
            state,
            decoder,
            tasks: remaining_tasks,
            next_task_token,
            stop: false,
          }
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
          { state, decoder, tasks, next_task_token, stop: false }
        }
        Some(_) => {
          (ports.trace)(
            runtime_trace_event(
              "runtime", "task_cancelled", "", "", "notification",
            ),
          )
          {
            state,
            decoder,
            tasks: remaining_tasks,
            next_task_token,
            stop: false,
          }
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
          { state, decoder, tasks, next_task_token, stop: false }
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
      { state, decoder, tasks: [], next_task_token, stop: true }
    }
  }
}

///|
/// Run one native connection. The input reader is unique, the reducer loop is
/// unique, and stdout is owned by one serial writer task. All other work is
/// represented by events in the bounded event queue.
async fn runtime_connection_engine(
  ports : RuntimePorts,
  options : RuntimeOptions,
) -> Unit {
  runtime_validate_options(options)
  @async.with_task_group(group => {
    let events : @aqueue.Queue[RuntimeEvent] = Queue(
      kind=Blocking(options.queue_capacity),
    )
    let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(
      kind=Blocking(options.queue_capacity),
    )
    let shutdown = Ref::Ref(false)
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
      let step = runtime_apply_event(
        event, state, decoder, group, writer_queue, options, ports, events, tasks,
        next_task_token, shutdown,
      )
      state = step.state
      decoder = step.decoder
      tasks = step.tasks
      next_task_token = step.next_task_token
      if step.stop {
        break
      }
    }
  })
}

///|
pub async fn connection_runtime_run(
  ports : RuntimePorts,
  options : RuntimeOptions,
) -> Unit {
  runtime_connection_engine(ports, options)
}
