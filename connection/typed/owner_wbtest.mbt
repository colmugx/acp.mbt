///|
struct TypedOwnerTestState {
  phase : String
  completed : Array[Int]
  completed_ids : Array[RequestId]
  completed_invocations : Array[Int]
  failed : Array[String]
  cancelled : Array[Int]
  cancelled_completions : Int
  aborted : Array[Int]
  notification_completed : Int
  notification_failed : Array[String]
  notification_cancelled : Int
} derive(Eq, Debug)

///|
enum TypedOwnerTestOutcome {
  TestSucceeded(Int)
  TestFailed(String)
  TestCancelled
} derive(Eq, Debug)

///|
fn typed_owner_test_initial() -> TypedOwnerTestState {
  {
    phase: "open",
    completed: [],
    completed_ids: [],
    completed_invocations: [],
    failed: [],
    cancelled: [],
    cancelled_completions: 0,
    aborted: [],
    notification_completed: 0,
    notification_failed: [],
    notification_cancelled: 0,
  }
}

///|
fn typed_owner_test_admit(
  state : TypedOwnerTestState,
  _id : RequestId,
  value : Int,
) -> TypedRequestAdmission[TypedOwnerTestState, Int, Int] {
  Invoke(
    state={ ..state, phase: "admitted-" + value.to_string(), },
    invocation=value,
  )
}

///|
fn typed_owner_test_notification(
  state : TypedOwnerTestState,
  value : Int,
) -> TypedNotificationAdmission[TypedOwnerTestState, Int] {
  Invoke(state={ ..state, phase: "notification-admitted", }, invocation=value)
}

///|
fn typed_owner_test_complete(
  state : TypedOwnerTestState,
  id : RequestId,
  invocation : Int,
  completion : Int,
) -> TypedRequestCompletion[TypedOwnerTestState, Int] {
  let completed = Array::copy(state.completed)
  completed.push(completion)
  let completed_ids = Array::copy(state.completed_ids)
  completed_ids.push(id)
  let completed_invocations = Array::copy(state.completed_invocations)
  completed_invocations.push(invocation)
  {
    state: { ..state, completed, completed_ids, completed_invocations, },
    result: completion,
  }
}

///|
fn typed_owner_test_complete_notification(
  state : TypedOwnerTestState,
  _invocation : Int,
  _completion : Int,
) -> TypedNotificationCompletion[TypedOwnerTestState] {
  {
    state: {
      ..state,
      notification_completed: state.notification_completed + 1,
    },
  }
}

///|
fn typed_owner_test_complete_outcome(
  state : TypedOwnerTestState,
  id : RequestId,
  invocation : Int,
  completion : TypedOwnerTestOutcome,
) -> TypedRequestCompletion[TypedOwnerTestState, TypedOwnerTestOutcome] {
  let next = match completion {
    TestSucceeded(value) => {
      let completed = Array::copy(state.completed)
      completed.push(value)
      let completed_ids = Array::copy(state.completed_ids)
      completed_ids.push(id)
      let completed_invocations = Array::copy(state.completed_invocations)
      completed_invocations.push(invocation)
      { ..state, completed, completed_ids, completed_invocations, }
    }
    TestFailed(message) => {
      let failed = Array::copy(state.failed)
      failed.push(message)
      { ..state, failed, }
    }
    TestCancelled =>
      { ..state, cancelled_completions: state.cancelled_completions + 1, }
  }
  { state: next, result: completion, }
}

///|
fn typed_owner_test_complete_notification_outcome(
  state : TypedOwnerTestState,
  _invocation : Int,
  completion : TypedOwnerTestOutcome,
) -> TypedNotificationCompletion[TypedOwnerTestState] {
  let next = match completion {
    TestSucceeded(_) =>
      { ..state, notification_completed: state.notification_completed + 1, }
    TestFailed(message) => {
      let failed = Array::copy(state.notification_failed)
      failed.push(message)
      { ..state, notification_failed: failed, }
    }
    TestCancelled =>
      { ..state, notification_cancelled: state.notification_cancelled + 1, }
  }
  { state: next, }
}

///|
fn typed_owner_test_cancel(
  state : TypedOwnerTestState,
  _id : RequestId,
  invocation : Int,
) -> TypedOwnerTestState {
  let cancelled = Array::copy(state.cancelled)
  cancelled.push(invocation)
  { ..state, cancelled, }
}

///|
fn typed_owner_test_abort(
  state : TypedOwnerTestState,
  task : TypedOwnerTask[Int],
) -> TypedOwnerTestState {
  let aborted = Array::copy(state.aborted)
  aborted.push(task.invocation())
  { ..state, aborted, }
}

///|
fn typed_owner_test_admit_request(
  owner : TypedOwner[TypedOwnerTestState, Int],
  id : RequestId,
  value : Int,
) -> (TypedOwner[TypedOwnerTestState, Int], TypedRequestAction[Int, Int]) {
  typed_owner_admit_request(owner, id, value, typed_owner_test_admit) catch {
    _ => abort("typed owner fixture request admission must not fail")
  }
}

///|
test "typed owner admits two requests before either completion" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, first_action) = typed_owner_test_admit_request(
    initial,
    Number(1),
    10,
  )
  let (second, second_action) = typed_owner_test_admit_request(
    first,
    String("two"),
    20,
  )
  assert_eq(second.task_count(), 2)
  match first_action {
    InvokeTask(task~) => {
      assert_eq(task.token(), 0)
      assert_eq(task.request_id(), Some(Number(1)))
      assert_eq(task.invocation(), 10)
    }
    ImmediateResult(_) => fail("first request must invoke")
  }
  match second_action {
    InvokeTask(task~) => {
      assert_eq(task.token(), 1)
      assert_eq(task.request_id(), Some(String("two")))
      assert_eq(task.invocation(), 20)
    }
    ImmediateResult(_) => fail("second request must invoke")
  }
}

///|
test "typed owner applies reverse completion without lost state" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, first_action) = typed_owner_test_admit_request(
    initial,
    Number(1),
    10,
  )
  let (owner, second_action) = typed_owner_test_admit_request(
    first,
    Number(2),
    20,
  )
  let first_task = match first_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => fail("first request must invoke")
  }
  let second_task = match second_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => fail("second request must invoke")
  }
  assert_eq(first_task.request_id(), Some(Number(1)))
  assert_eq(first_task.invocation(), 10)
  assert_eq(second_task.request_id(), Some(Number(2)))
  assert_eq(second_task.invocation(), 20)
  let second_event = RequestCompleted(token=1, id=Number(2), completion=200)
  let after_second = typed_owner_complete_request(
    owner, second_event, typed_owner_test_complete,
  )
  let owner_after_second = match after_second {
    Applied(owner~, result~) if result == 200 => {
      assert_eq(owner.task_count(), 1)
      assert_eq(owner.state().completed_ids, [Number(2)])
      assert_eq(owner.state().completed_invocations, [20])
      owner
    }
    Applied(..) => fail("second completion returned the wrong result")
    Ignored(reason=_) => fail("second completion must apply")
  }
  let first_event = RequestCompleted(token=0, id=Number(1), completion=100)
  match
    typed_owner_complete_request(
      owner_after_second, first_event, typed_owner_test_complete,
    ) {
    Applied(owner~, result~) if result == 100 => {
      assert_eq(owner.state().completed, [200, 100])
      assert_eq(owner.state().completed_ids, [Number(2), Number(1)])
      assert_eq(owner.state().completed_invocations, [20, 10])
      assert_eq(owner.task_count(), 0)
    }
    Applied(..) => fail("first completion returned the wrong result")
    Ignored(reason=_) => fail("first completion must apply")
  }
}

///|
test "typed owner rejects mismatched request id without consuming task" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (owner, _) = typed_owner_test_admit_request(initial, Number(7), 70)
  let mismatch = typed_owner_complete_request(
    owner,
    RequestCompleted(token=0, id=String("wrong"), completion=700),
    typed_owner_test_complete,
  )
  match mismatch {
    Ignored(
      reason=RequestIdMismatch(expected=Number(7), actual=String("wrong"))
    ) => ()
    _ => fail("mismatched id must be ignored")
  }
  assert_eq(owner.task_count(), 1)
}

///|
test "typed owner preserves both tasks on a cross token id mismatch" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, _) = typed_owner_test_admit_request(initial, Number(1), 10)
  let (owner, _) = typed_owner_test_admit_request(first, String("two"), 20)
  let mismatch = typed_owner_complete_request(
    owner,
    RequestCompleted(token=0, id=String("two"), completion=999),
    typed_owner_test_complete,
  )
  match mismatch {
    Ignored(reason=RequestIdMismatch(expected=Number(1), actual=String("two"))) =>
      ()
    _ => fail("a task A token with task B id must be rejected")
  }
  assert_eq(owner.task_count(), 2)
  let after_second = typed_owner_complete_request(
    owner,
    RequestCompleted(token=1, id=String("two"), completion=200),
    typed_owner_test_complete,
  )
  let owner_after_second = match after_second {
    Applied(owner~, result~) if result == 200 => owner
    _ => fail("task B completion must still apply")
  }
  match
    typed_owner_complete_request(
      owner_after_second,
      RequestCompleted(token=0, id=Number(1), completion=100),
      typed_owner_test_complete,
    ) {
    Applied(owner~, result~) if result == 100 => {
      assert_eq(owner.task_count(), 0)
      assert_eq(owner.state().completed_ids, [String("two"), Number(1)])
      assert_eq(owner.state().completed_invocations, [20, 10])
    }
    _ => fail("task A completion must still apply after the mismatch")
  }
}

///|
test "typed owner rejects an unknown token with a legal request id" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (owner, _) = typed_owner_test_admit_request(initial, Number(7), 70)
  match
    typed_owner_complete_request(
      owner,
      RequestCompleted(token=99, id=Number(7), completion=700),
      typed_owner_test_complete,
    ) {
    Ignored(reason=UnknownTask(token=99)) => ()
    _ => fail("an unknown token must not consume a legal request")
  }
  assert_eq(owner.task_count(), 1)
  match
    typed_owner_complete_request(
      owner,
      RequestCompleted(token=0, id=Number(7), completion=70),
      typed_owner_test_complete,
    ) {
    Applied(owner~, result~) if result == 70 => {
      assert_eq(owner.task_count(), 0)
      assert_eq(owner.state().completed_ids, [Number(7)])
      assert_eq(owner.state().completed_invocations, [70])
    }
    _ => fail("the legal token must remain completable")
  }
}

///|
test "typed owner preserves explicit handler failure as a completion" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (owner, _) = typed_owner_test_admit_request(initial, Number(9), 90)
  let failure = typed_owner_complete_request(
    owner,
    RequestCompleted(
      token=0,
      id=Number(9),
      completion=TestFailed("handler failed"),
    ),
    typed_owner_test_complete_outcome,
  )
  match failure {
    Applied(owner~, result~) => {
      match result {
        TestFailed(message) => assert_eq(message, "handler failed")
        _ => fail("handler failure must remain an explicit outcome")
      }
      assert_eq(owner.state().completed, [])
      assert_eq(owner.state().failed, ["handler failed"])
      assert_eq(owner.task_count(), 0)
    }
    Ignored(reason=_) => fail("handler failure completion must be applied")
  }
}

///|
test "typed owner records an explicit typed failure outcome" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (owner, _) = typed_owner_test_admit_request(initial, Number(9), 90)
  let failure = typed_owner_complete_request(
    owner,
    RequestCompleted(
      token=0,
      id=Number(9),
      completion=TestFailed("backend unavailable"),
    ),
    typed_owner_test_complete_outcome,
  )
  match failure {
    Applied(owner~, result~) => {
      match result {
        TestFailed(message) => assert_eq(message, "backend unavailable")
        _ => fail("the explicit failure outcome must be preserved")
      }
      assert_eq(owner.task_count(), 0)
      assert_eq(owner.state().completed, [])
      assert_eq(owner.state().failed, ["backend unavailable"])
    }
    Ignored(reason=_) => fail("a typed failure completion must apply")
  }
}

///|
test "typed owner ignores late completion after task removal" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (owner, _) = typed_owner_test_admit_request(initial, Number(1), 10)
  let event = RequestCompleted(token=0, id=Number(1), completion=100)
  let applied = typed_owner_complete_request(
    owner, event, typed_owner_test_complete,
  )
  let next = match applied {
    Applied(owner~, result~) if result == 100 => owner
    Applied(..) => fail("completion returned the wrong result")
    Ignored(reason=_) => fail("completion must apply")
  }
  match typed_owner_complete_request(next, event, typed_owner_test_complete) {
    Ignored(reason=UnknownTask(token=0)) => ()
    _ => fail("late completion must be ignored")
  }
  assert_eq(next.task_count(), 0)
}

///|
test "typed owner cancellation marks exact task and releases through completion" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (owner, _) = typed_owner_test_admit_request(initial, Number(4), 40)
  let cancellation = typed_owner_cancel_request(
    owner,
    Number(4),
    typed_owner_test_cancel,
  )
  let (cancelled_owner, task) = match cancellation {
    Requested(owner~, task~) => (owner, task)
    Ignored(reason=_) => fail("pending request must be cancellable")
  }
  assert_true(task.cancel_requested())
  assert_eq(cancelled_owner.state().cancelled, [40])
  match
    typed_owner_cancel_request(
      cancelled_owner,
      Number(4),
      typed_owner_test_cancel,
    ) {
    Ignored(reason=AlreadyCancelled(id=Number(4))) => ()
    _ => fail("duplicate cancellation must be ignored")
  }
  let completion = RequestCompleted(token=0, id=Number(4), completion=0)
  match
    typed_owner_complete_request(
      cancelled_owner, completion, typed_owner_test_complete,
    ) {
    Applied(owner~, result~) if result == 0 => assert_eq(owner.task_count(), 0)
    Applied(..) => fail("cancellation completion returned the wrong result")
    Ignored(reason=_) => fail("cancelled task completion must apply once")
  }
}

///|
test "typed owner cancels one task and applies its typed cancelled outcome" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, _) = typed_owner_test_admit_request(initial, Number(4), 40)
  let (owner, second_action) = typed_owner_test_admit_request(
    first,
    Number(5),
    50,
  )
  let second_task = match second_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => fail("second request must invoke")
  }
  let cancellation = typed_owner_cancel_request(
    owner,
    Number(5),
    typed_owner_test_cancel,
  )
  let (cancelled_owner, cancelled_task) = match cancellation {
    Requested(owner~, task~) => (owner, task)
    Ignored(reason=_) => fail("the second task must be cancellable")
  }
  assert_eq(cancelled_task.token(), second_task.token())
  assert_eq(cancelled_task.request_id(), Some(Number(5)))
  assert_eq(cancelled_task.invocation(), 50)
  assert_eq(cancelled_owner.state().cancelled, [50])
  assert_eq(cancelled_owner.task_count(), 2)
  match
    typed_owner_complete_request(
      cancelled_owner,
      RequestCompleted(
        token=cancelled_task.token(),
        id=Number(5),
        completion=TestCancelled,
      ),
      typed_owner_test_complete_outcome,
    ) {
    Applied(owner~, result~) => {
      assert_true(result is TestCancelled)
      assert_eq(owner.state().cancelled_completions, 1)
      assert_eq(owner.task_count(), 1)
    }
    Ignored(reason=_) => fail("cancelled task completion must apply")
  }
}

///|
test "typed owner closes and aborts each task once" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, _) = typed_owner_test_admit_request(initial, Number(1), 10)
  let (owner, _) = typed_owner_test_admit_request(first, Number(2), 20)
  let closed = typed_owner_close(owner, typed_owner_test_abort)
  let (closed_owner, aborted) = match closed {
    Closed(owner~, aborted~) => (owner, aborted)
    AlreadyClosed(_) => fail("owner must close once")
  }
  assert_eq(aborted.length(), 2)
  assert_eq(closed_owner.task_count(), 0)
  assert_true(closed_owner.is_closed())
  match typed_owner_close(closed_owner, typed_owner_test_abort) {
    AlreadyClosed(_) => ()
    Closed(..) => fail("duplicate close must not abort again")
  }
}

///|
test "typed owner close records exact aborts and ignores late outcomes" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, first_action) = typed_owner_test_admit_request(
    initial,
    Number(1),
    10,
  )
  let (owner, second_action) = typed_owner_test_admit_request(
    first,
    String("two"),
    20,
  )
  let first_task = match first_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => fail("first request must invoke")
  }
  let second_task = match second_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => fail("second request must invoke")
  }
  let closed = typed_owner_close(owner, typed_owner_test_abort)
  let (closed_owner, aborted) = match closed {
    Closed(owner~, aborted~) => (owner, aborted)
    AlreadyClosed(_) => fail("owner must close once")
  }
  assert_eq(closed_owner.state().aborted, [10, 20])
  assert_eq(aborted.length(), 2)
  assert_eq(aborted[0].token(), first_task.token())
  assert_eq(aborted[0].request_id(), Some(Number(1)))
  assert_eq(aborted[0].invocation(), 10)
  assert_eq(aborted[1].token(), second_task.token())
  assert_eq(aborted[1].request_id(), Some(String("two")))
  assert_eq(aborted[1].invocation(), 20)
  match
    typed_owner_complete_request(
      closed_owner,
      RequestCompleted(token=0, id=Number(1), completion=100),
      typed_owner_test_complete,
    ) {
    Ignored(reason=Closed) => ()
    _ => fail("late success after close must be ignored")
  }
  match
    typed_owner_complete_request(
      closed_owner,
      RequestCompleted(
        token=1,
        id=String("two"),
        completion=TestFailed("late failure"),
      ),
      typed_owner_test_complete_outcome,
    ) {
    Ignored(reason=Closed) => ()
    _ => fail("late failure after close must be ignored")
  }
  match
    typed_owner_complete_request(
      closed_owner,
      RequestCompleted(token=0, id=Number(1), completion=TestCancelled),
      typed_owner_test_complete_outcome,
    ) {
    Ignored(reason=Closed) => ()
    _ => fail("late cancellation after close must be ignored")
  }
}

///|
test "typed owner closes with no pending task without changing state" {
  let owner = typed_owner_new(typed_owner_test_initial())
  let initial_state = owner.state()
  match typed_owner_close(owner, typed_owner_test_abort) {
    Closed(owner~, aborted~) => {
      assert_eq(aborted.length(), 0)
      assert_eq(owner.state(), initial_state)
      assert_true(owner.is_closed())
    }
    AlreadyClosed(_) => fail("initial owner must be open")
  }
}

///|
test "typed owner overlaps notifications and never creates request ids" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, first_action) = typed_owner_admit_notification(
    initial, 1, typed_owner_test_notification,
  ) catch {
    _ => abort("notification admission must not fail")
  }
  let (owner, second_action) = typed_owner_admit_notification(
    first, 2, typed_owner_test_notification,
  ) catch {
    _ => abort("notification admission must not fail")
  }
  let first_task = match first_action {
    InvokeTask(task~) => task
    ImmediateNotification => abort("first notification must invoke")
  }
  let second_task = match second_action {
    InvokeTask(task~) => task
    ImmediateNotification => abort("second notification must invoke")
  }
  assert_true(first_task.is_notification())
  assert_true(second_task.is_notification())
  match
    typed_owner_complete_notification(
      owner,
      NotificationCompleted(token=second_task.token(), completion=2),
      typed_owner_test_complete_notification,
    ) {
    Applied(owner~) => {
      assert_eq(owner.task_count(), 1)
      match
        typed_owner_complete_notification(
          owner,
          NotificationCompleted(token=first_task.token(), completion=1),
          typed_owner_test_complete_notification,
        ) {
        Applied(owner~) => assert_eq(owner.task_count(), 0)
        Ignored(reason=_) => fail("first notification must apply")
      }
    }
    Ignored(reason=_) => fail("second notification must apply")
  }
}

///|
test "typed owner applies notification success failure cancellation and late" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, first_action) = typed_owner_admit_notification(
    initial, 1, typed_owner_test_notification,
  ) catch {
    _ => abort("first notification admission must not fail")
  }
  let (second, second_action) = typed_owner_admit_notification(
    first, 2, typed_owner_test_notification,
  ) catch {
    _ => abort("second notification admission must not fail")
  }
  let (owner, third_action) = typed_owner_admit_notification(
    second, 3, typed_owner_test_notification,
  ) catch {
    _ => abort("third notification admission must not fail")
  }
  let first_task = match first_action {
    InvokeTask(task~) => task
    ImmediateNotification => abort("first notification must invoke")
  }
  let second_task = match second_action {
    InvokeTask(task~) => task
    ImmediateNotification => abort("second notification must invoke")
  }
  let third_task = match third_action {
    InvokeTask(task~) => task
    ImmediateNotification => abort("third notification must invoke")
  }
  assert_eq(first_task.request_id(), None)
  assert_eq(second_task.request_id(), None)
  assert_eq(third_task.request_id(), None)
  assert_true(first_task.is_notification())
  assert_true(second_task.is_notification())
  assert_true(third_task.is_notification())
  let after_success = match
    typed_owner_complete_notification(
      owner,
      NotificationCompleted(
        token=first_task.token(),
        completion=TestSucceeded(1),
      ),
      typed_owner_test_complete_notification_outcome,
    ) {
    Applied(owner~) => {
      assert_eq(owner.state().notification_completed, 1)
      assert_eq(owner.task_count(), 2)
      owner
    }
    Ignored(reason=_) => fail("notification success must apply")
  }
  let after_failure = match
    typed_owner_complete_notification(
      after_success,
      NotificationCompleted(
        token=second_task.token(),
        completion=TestFailed("notification failed"),
      ),
      typed_owner_test_complete_notification_outcome,
    ) {
    Applied(owner~) => {
      assert_eq(owner.state().notification_failed, ["notification failed"])
      assert_eq(owner.task_count(), 1)
      owner
    }
    Ignored(reason=_) => fail("notification failure must apply")
  }
  let after_cancel = match
    typed_owner_complete_notification(
      after_failure,
      NotificationCompleted(token=third_task.token(), completion=TestCancelled),
      typed_owner_test_complete_notification_outcome,
    ) {
    Applied(owner~) => {
      assert_eq(owner.state().notification_cancelled, 1)
      assert_eq(owner.task_count(), 0)
      owner
    }
    Ignored(reason=_) => fail("notification cancellation must apply")
  }
  match
    typed_owner_complete_notification(
      after_cancel,
      NotificationCompleted(
        token=second_task.token(),
        completion=TestFailed("late notification"),
      ),
      typed_owner_test_complete_notification_outcome,
    ) {
    Ignored(reason=UnknownTask(token~)) => assert_eq(token, second_task.token())
    _ => fail("late notification completion must be ignored")
  }
}

///|
async test "typed owner execute carries only immutable task data" {
  let owner = typed_owner_new(typed_owner_test_initial())
  let (owner, action) = typed_owner_test_admit_request(owner, Null, 90)
  ignore(owner)
  let task = match action {
    InvokeTask(task~) => task
    ImmediateResult(_) => abort("request must invoke")
  }
  let event = typed_owner_execute(task, async fn(value) {
    @async.pause()
    value + 1
  })
  match event {
    RequestCompleted(token=0, id=Null, completion=91) => ()
    _ => fail("execute must preserve token/id and completion")
  }
}

///|
async test "typed owner executes two tasks concurrently and applies reverse events" {
  let initial = typed_owner_new(typed_owner_test_initial())
  let (first, first_action) = typed_owner_test_admit_request(
    initial,
    Number(1),
    10,
  )
  let (owner, second_action) = typed_owner_test_admit_request(
    first,
    Number(2),
    20,
  )
  let first_task = match first_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => abort("first request must invoke")
  }
  let second_task = match second_action {
    InvokeTask(task~) => task
    ImmediateResult(_) => abort("second request must invoke")
  }
  let first_started : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let second_started : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let first_gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let second_gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[TypedOwnerEvent[Int]] = Queue(kind=Unbounded)
  @async.with_task_group(group => {
    let first_task_run = group.spawn(() => {
      let event = typed_owner_execute(first_task, async fn(value) {
        first_started.put(())
        first_gate.get()
        value + 100
      })
      events.put(event)
    })
    let second_task_run = group.spawn(() => {
      let event = typed_owner_execute(second_task, async fn(value) {
        second_started.put(())
        second_gate.get()
        value + 100
      })
      events.put(event)
    })
    ignore(first_started.get())
    ignore(second_started.get())
    second_gate.put(())
    let second_event = events.get()
    let owner_after_second = match second_event {
      RequestCompleted(token=1, id=Number(2), completion=120) =>
        match
          typed_owner_complete_request(
            owner, second_event, typed_owner_test_complete,
          ) {
          Applied(owner~, result~) if result == 120 => owner
          _ => abort("second reverse completion must apply")
        }
      _ => abort("second task must complete before the gated first task")
    }
    assert_eq(owner_after_second.task_count(), 1)
    assert_eq(owner_after_second.state().completed_ids, [Number(2)])
    first_gate.put(())
    let first_event = events.get()
    match first_event {
      RequestCompleted(token=0, id=Number(1), completion=110) =>
        match
          typed_owner_complete_request(
            owner_after_second, first_event, typed_owner_test_complete,
          ) {
          Applied(owner~, result~) if result == 110 => {
            assert_eq(owner.task_count(), 0)
            assert_eq(owner.state().completed_ids, [Number(2), Number(1)])
            assert_eq(owner.state().completed_invocations, [20, 10])
          }
          _ => abort("first reverse completion must apply")
        }
      _ => abort("first task must complete after its gate is released")
    }
    first_task_run.wait()
    second_task_run.wait()
  })
}

///|
async test "typed owner keeps the legacy connection runtime callable" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let options = @runtime.runtime_default_options()
  let ports : @runtime.RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  input.put(
    Some(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"typed-owner-smoke\"}\n",
      ),
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      @connection.connection_runtime_run(ports, options)
    })
    let feeder = group.spawn(() => {
      written.get()
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  match @jsonrpc.jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Success(success)) => assert_eq(success.id, Number(1))
    _ => fail("legacy runtime must still produce one response")
  }
}
