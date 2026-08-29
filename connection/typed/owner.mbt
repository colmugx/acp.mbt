///|
using @jsonrpc {type RequestId}

///|
/// A state transition returned by a synchronous request admission hook.
///
/// `Immediate` has no task crossing the async boundary. `Invoke` commits the
/// returned state before the immutable invocation is handed to a task.
pub(all) enum TypedRequestAdmission[S, I, R] {
  Immediate(state~ : S, result~ : R)
  Invoke(state~ : S, invocation~ : I)
}

///|
/// A state transition returned by a synchronous notification admission hook.
pub(all) enum TypedNotificationAdmission[S, I] {
  Immediate(state~ : S)
  Invoke(state~ : S, invocation~ : I)
}

///|
/// A task owned by one typed owner. The task is created only by admission, so
/// a request id of `Null` remains distinct from a notification's omitted id.
/// The task carries no mutable state or connection queue.
pub struct TypedOwnerTask[I] {
  token : Int
  request_id : RequestId?
  invocation : I
  is_notification : Bool
  cancel_requested : Bool
}

///|
/// The event produced by an immutable async execution task. It contains no
/// owner state; only the owner loop may apply it.
pub(all) enum TypedOwnerEvent[C] {
  RequestCompleted(token~ : Int, id~ : RequestId, completion~ : C)
  NotificationCompleted(token~ : Int, completion~ : C)
}

///|
/// A typed owner is immutable from the caller's perspective. All transitions
/// return a new value; one runtime owner must serialize calls to these
/// functions.
pub struct TypedOwner[S, I] {
  state : S
  tasks : Array[TypedOwnerTask[I]]
  next_token : Int
  closed : Bool
}

///|
pub(all) enum TypedOwnerIgnore {
  Closed
  UnknownTask(token~ : Int)
  UnknownRequest(id~ : RequestId)
  AlreadyCancelled(id~ : RequestId)
  RequestIdMismatch(expected~ : RequestId, actual~ : RequestId)
  TaskKindMismatch(token~ : Int)
} derive(Eq, Debug)

///|
pub(all) enum TypedRequestAction[I, R] {
  ImmediateResult(result~ : R)
  InvokeTask(task~ : TypedOwnerTask[I])
}

///|
pub(all) enum TypedNotificationAction[I] {
  ImmediateNotification
  InvokeTask(task~ : TypedOwnerTask[I])
}

///|
pub(all) struct TypedRequestCompletion[S, R] {
  state : S
  result : R
}

///|
pub(all) struct TypedNotificationCompletion[S] {
  state : S
}

///|
pub(all) enum TypedRequestCompletionResult[S, I, R] {
  Applied(owner~ : TypedOwner[S, I], result~ : R)
  Ignored(reason~ : TypedOwnerIgnore)
}

///|
pub(all) enum TypedNotificationCompletionResult[S, I] {
  Applied(owner~ : TypedOwner[S, I])
  Ignored(reason~ : TypedOwnerIgnore)
}

///|
pub(all) enum TypedCancelResult[S, I] {
  Requested(owner~ : TypedOwner[S, I], task~ : TypedOwnerTask[I])
  Ignored(reason~ : TypedOwnerIgnore)
}

///|
pub(all) enum TypedCloseResult[S, I] {
  Closed(owner~ : TypedOwner[S, I], aborted~ : Array[TypedOwnerTask[I]])
  AlreadyClosed(owner~ : TypedOwner[S, I])
}

///|
pub fn[S, I] typed_owner_new(state : S) -> TypedOwner[S, I] {
  { state, tasks: [], next_token: 0, closed: false, }
}

///|
pub fn[S, I] TypedOwner::state(self : TypedOwner[S, I]) -> S {
  self.state
}

///|
pub fn[S, I] TypedOwner::task_count(self : TypedOwner[S, I]) -> Int {
  self.tasks.length()
}

///|
pub fn[S, I] TypedOwner::is_closed(self : TypedOwner[S, I]) -> Bool {
  self.closed
}

///|
pub fn[I] TypedOwnerTask::token(self : TypedOwnerTask[I]) -> Int {
  self.token
}

///|
pub fn[I] TypedOwnerTask::request_id(self : TypedOwnerTask[I]) -> RequestId? {
  self.request_id
}

///|
pub fn[I] TypedOwnerTask::invocation(self : TypedOwnerTask[I]) -> I {
  self.invocation
}

///|
pub fn[I] TypedOwnerTask::is_notification(self : TypedOwnerTask[I]) -> Bool {
  self.is_notification
}

///|
pub fn[I] TypedOwnerTask::cancel_requested(self : TypedOwnerTask[I]) -> Bool {
  self.cancel_requested
}

///|
fn[I] typed_owner_task_cancelled(task : TypedOwnerTask[I]) -> TypedOwnerTask[I] {
  { ..task, cancel_requested: true, }
}

///|
fn[S, I] typed_owner_find_task(
  owner : TypedOwner[S, I],
  token : Int,
) -> TypedOwnerTask[I]? {
  for task in owner.tasks {
    if task.token == token {
      return Some(task)
    }
  }
  None
}

///|
fn[S, I] typed_owner_replace_task(
  owner : TypedOwner[S, I],
  replacement : TypedOwnerTask[I],
) -> TypedOwner[S, I] {
  let tasks : Array[TypedOwnerTask[I]] = []
  for task in owner.tasks {
    if task.token == replacement.token {
      tasks.push(replacement)
    } else {
      tasks.push(task)
    }
  }
  { ..owner, tasks, }
}

///|
fn[S, I] typed_owner_remove_task(
  owner : TypedOwner[S, I],
  token : Int,
) -> TypedOwner[S, I] {
  let tasks : Array[TypedOwnerTask[I]] = []
  for task in owner.tasks {
    if task.token != token {
      tasks.push(task)
    }
  }
  { ..owner, tasks, }
}

///|
/// Admit one request and synchronously commit the admission state. The task
/// returned by `InvokeTask` is the only value that may cross the async seam.
pub fn[S, I, Q, R] typed_owner_admit_request(
  owner : TypedOwner[S, I],
  id : RequestId,
  request : Q,
  admit : (S, RequestId, Q) -> TypedRequestAdmission[S, I, R],
) -> (TypedOwner[S, I], TypedRequestAction[I, R]) raise TypedOwnerError {
  if owner.closed {
    raise Closed
  }
  match admit(owner.state, id, request) {
    Immediate(state~, result~) =>
      ({ ..owner, state, }, ImmediateResult(result~))
    Invoke(state~, invocation~) => {
      let task : TypedOwnerTask[I] = {
        token: owner.next_token,
        request_id: Some(id),
        invocation,
        is_notification: false,
        cancel_requested: false,
      }
      let tasks = Array::copy(owner.tasks)
      tasks.push(task)
      (
        { state, tasks, next_token: owner.next_token + 1, closed: false, },
        InvokeTask(task~),
      )
    }
  }
}

///|
/// Admit one notification and synchronously commit its state. Notifications
/// never acquire a request id and never synthesize a response.
pub fn[S, I, N] typed_owner_admit_notification(
  owner : TypedOwner[S, I],
  notification : N,
  admit : (S, N) -> TypedNotificationAdmission[S, I],
) -> (TypedOwner[S, I], TypedNotificationAction[I]) raise TypedOwnerError {
  if owner.closed {
    raise Closed
  }
  match admit(owner.state, notification) {
    Immediate(state~) => ({ ..owner, state, }, ImmediateNotification)
    Invoke(state~, invocation~) => {
      let task : TypedOwnerTask[I] = {
        token: owner.next_token,
        request_id: None,
        invocation,
        is_notification: true,
        cancel_requested: false,
      }
      let tasks = Array::copy(owner.tasks)
      tasks.push(task)
      (
        { state, tasks, next_token: owner.next_token + 1, closed: false, },
        InvokeTask(task~),
      )
    }
  }
}

///|
/// Execute only immutable task data. This function never reads or updates an
/// owner and is suitable for spawning in a native task group.
pub async fn[I, C] typed_owner_execute(
  task : TypedOwnerTask[I],
  execute : async (I) -> C,
) -> TypedOwnerEvent[C] {
  let completion = execute(task.invocation)
  if task.is_notification {
    NotificationCompleted(token=task.token, completion~)
  } else {
    match task.request_id {
      Some(id) => RequestCompleted(token=task.token, id~, completion~)
      None => abort("typed owner request task has no request id")
    }
  }
}

///|
/// Apply a request completion on the owner loop. Token and id are checked
/// before the task is removed, so a malformed completion cannot consume a
/// different pending request.
pub fn[S, I, C, R] typed_owner_complete_request(
  owner : TypedOwner[S, I],
  event : TypedOwnerEvent[C],
  complete : (S, RequestId, I, C) -> TypedRequestCompletion[S, R],
) -> TypedRequestCompletionResult[S, I, R] {
  if owner.closed {
    return Ignored(reason=Closed)
  }
  match event {
    NotificationCompleted(token~, completion=_) =>
      Ignored(reason=TaskKindMismatch(token~))
    RequestCompleted(token~, id=actual, completion~) =>
      match typed_owner_find_task(owner, token) {
        None => Ignored(reason=UnknownTask(token~))
        Some(task) if task.is_notification =>
          Ignored(reason=TaskKindMismatch(token~))
        Some(task) =>
          match task.request_id {
            Some(expected) if expected == actual => {
              let next = typed_owner_remove_task(owner, token)
              let completed = complete(
                next.state,
                actual,
                task.invocation,
                completion,
              )
              Applied(
                owner={ ..next, state: completed.state, },
                result=completed.result,
              )
            }
            Some(expected) =>
              Ignored(reason=RequestIdMismatch(expected~, actual~))
            None => Ignored(reason=TaskKindMismatch(token~))
          }
      }
  }
}

///|
/// Apply a notification completion. No response value exists in this path.
pub fn[S, I, C] typed_owner_complete_notification(
  owner : TypedOwner[S, I],
  event : TypedOwnerEvent[C],
  complete : (S, I, C) -> TypedNotificationCompletion[S],
) -> TypedNotificationCompletionResult[S, I] {
  if owner.closed {
    return Ignored(reason=Closed)
  }
  match event {
    RequestCompleted(token~, id=_, completion=_) =>
      Ignored(reason=TaskKindMismatch(token~))
    NotificationCompleted(token~, completion~) =>
      match typed_owner_find_task(owner, token) {
        None => Ignored(reason=UnknownTask(token~))
        Some(task) if !task.is_notification =>
          Ignored(reason=TaskKindMismatch(token~))
        Some(task) => {
          let next = typed_owner_remove_task(owner, token)
          let completed = complete(next.state, task.invocation, completion)
          Applied(owner={ ..next, state: completed.state, })
        }
      }
  }
}

///|
/// Mark one request cancellation in the owner state and return the exact task
/// to the runtime for cancellation. The task remains pending until its typed
/// cancellation completion is applied through `typed_owner_complete_request`.
pub fn[S, I] typed_owner_cancel_request(
  owner : TypedOwner[S, I],
  id : RequestId,
  cancel : (S, RequestId, I) -> S,
) -> TypedCancelResult[S, I] {
  if owner.closed {
    return Ignored(reason=Closed)
  }
  let found : TypedOwnerTask[I]? = search~: {
    for task in owner.tasks {
      match task.request_id {
        Some(task_id) if task_id == id && !task.is_notification =>
          break search~ Some(task)
        _ => ()
      }
    }
    None
  }
  match found {
    None => Ignored(reason=UnknownRequest(id~))
    Some(task) if task.cancel_requested => Ignored(reason=AlreadyCancelled(id~))
    Some(task) => {
      let next_state = cancel(owner.state, id, task.invocation)
      let next = typed_owner_replace_task(
        owner,
        typed_owner_task_cancelled(task),
      )
      Requested(
        owner={ ..next, state: next_state, },
        task=typed_owner_task_cancelled(task),
      )
    }
  }
}

///|
/// Close the typed owner exactly once. Every pending task is passed to
/// `abort`; the returned owner has no tasks, so late events are ignored.
pub fn[S, I] typed_owner_close(
  owner : TypedOwner[S, I],
  abort : (S, TypedOwnerTask[I]) -> S,
) -> TypedCloseResult[S, I] {
  if owner.closed {
    return AlreadyClosed(owner~)
  }
  let mut next_state = owner.state
  for task in owner.tasks {
    next_state = abort(next_state, task)
  }
  let aborted = Array::copy(owner.tasks)
  Closed(
    owner={
      state: next_state,
      tasks: [],
      next_token: owner.next_token,
      closed: true,
    },
    aborted~,
  )
}

///|
/// Errors raised when an owner operation cannot admit new work.
pub(all) suberror TypedOwnerError {
  Closed
} derive(Eq, Debug)
