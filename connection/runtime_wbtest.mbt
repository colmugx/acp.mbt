///|
using @runtime {runtime_default_options}

///|
fn runtime_test_options() -> RuntimeOptions {
  let options = runtime_default_options()
  { ..options, max_frame_bytes: 256, }
}

///|
/// Legacy unit-context inbound cancellation seam for exercising the generic
/// `_of` engine functions without an owner loop.
fn runtime_wbtest_unit_cancel_inbound(
  context : Unit,
  id : RequestId,
  controls : Array[RuntimeTaskControl],
) -> RuntimeDispatchCancelResult[Unit] raise RuntimeError {
  runtime_cancel_task(controls, id)
  RuntimeDispatchCancelApplied(context~)
}

///|
/// Legacy unit-context close hook: no owner state exists to close.
#warnings("-unused_error_type")
fn runtime_wbtest_unit_close_owner(
  context : Unit,
  _tasks : Array[RuntimeTaskControl],
) -> Unit raise RuntimeError {
  context
}

///|
fn runtime_test_request() -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"work\"}\n"
}

///|
fn runtime_wbtest_request(id : RequestId) -> JsonRpcRequest {
  JsonRpcRequest::new(id~, method_name="work") catch {
    _ => abort("runtime fixture request must be valid")
  }
}

///|
/// Test-only legacy adapter for exercising individual event transitions. The
/// production connection loop uses the generic engine directly.
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
  let dispatch_context : RuntimeLegacySpawnContext[RuntimeHandlerResult] = {
    shutdown,
    handlers: ports.handlers,
    events,
    result_to_event: runtime_identity_handler_result,
    limit: options.queue_capacity,
  }
  let dispatch : RuntimeDispatchPort[
    G,
    RuntimeLegacySpawnContext[RuntimeHandlerResult],
  ] = runtime_legacy_dispatch_port()
  let (step, _) = runtime_apply_event_of(
    event,
    state,
    decoder,
    group,
    writer_queue,
    options,
    ports,
    events,
    runtime_identity_handler_result,
    dispatch,
    runtime_owner_event_unavailable,
    dispatch_context,
    tasks,
    next_task_token,
    shutdown,
    Ref(runtime_outbound_registry()),
  )
  step
}

///|
test "runtime renders a null request id without a sentinel" {
  assert_eq(runtime_request_id_text(Null), "null")
}

///|
async test "runtime uses one reader and one serial writer for a request" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let traces : Array[RuntimeTraceEvent] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
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
    trace: event => traces.push(event),
  }
  input.put(Some(@utf8.encode(runtime_test_request())))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      connection_runtime_run(ports, runtime_test_options())
    })
    let feeder = group.spawn(() => {
      written.get()
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  assert_eq(
    output[0],
    @utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}\n"),
  )
  assert_true(traces.length() >= 2)
  assert_eq(traces[0].direction, "outbound")
  assert_eq(traces[0].phase, "writer_dequeue")
  assert_eq(traces[0].request_id, "")
  assert_eq(traces[0].method_name, "")
  assert_eq(traces[0].error_kind, "")
}

///|
async test "runtime notifications never produce a response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let handled : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: frame => output.push(frame), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => handled.put(()),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  input.put(Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"method\":\"notice\"}\n")))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      connection_runtime_run(ports, runtime_test_options())
    })
    let feeder = group.spawn(() => {
      handled.get()
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 0)
}

///|
async test "runtime preserves a typed handler error response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => HandlerError(JsonRpcError::internal_error()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  input.put(Some(@utf8.encode(runtime_test_request())))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      connection_runtime_run(ports, runtime_test_options())
    })
    let feeder = group.spawn(() => {
      written.get()
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(_)) => ()
    _ => fail("expected typed handler error response")
  }
}

///|
async test "runtime cancellation completes the inbound request explicitly" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let cancel_frame = "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n"
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => {
        gate.get()
        HandlerSuccess(Json::null())
      },
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  input.put(Some(@utf8.encode(runtime_test_request() + cancel_frame)))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      connection_runtime_run(ports, runtime_test_options())
    })
    let feeder = group.spawn(() => {
      written.get()
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(failure)) => assert_eq(failure.error.code, RequestCancelled)
    _ => fail("expected cancellation error response")
  }
}

///|
async test "runtime reports malformed JSON and partial EOF" {
  let malformed_input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let malformed_ports : RuntimePorts = {
    reader: { read: _ => malformed_input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  malformed_input.put(Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\n")))
  malformed_input.put(None)
  try connection_runtime_run(malformed_ports, runtime_test_options()) catch {
    @runtime.RuntimeError::JsonRpcDecodeFailed => ()
    _ => fail("expected malformed JSON to be visible")
  } noraise {
    _ => fail("expected malformed JSON to fail")
  }

  let partial_input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let partial_ports : RuntimePorts = {
    reader: { read: _ => partial_input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  partial_input.put(Some(@utf8.encode("partial")))
  partial_input.put(None)
  try connection_runtime_run(partial_ports, runtime_test_options()) catch {
    @runtime.RuntimeError::FramingFailed => ()
    _ => fail("expected partial EOF to be visible")
  } noraise {
    _ => fail("expected partial EOF to fail")
  }
}

///|
async test "runtime normalizes reader and handler failures" {
  let reader_ports : RuntimePorts = {
    reader: {
      read: _ => {
        raise @jsonrpc.JsonRpcCodecError::ParseError(message="reader fault")
      },
    },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  try connection_runtime_run(reader_ports, runtime_test_options()) catch {
    @runtime.RuntimeError::ReaderFailed => ()
    _ => fail("expected reader failure to be visible")
  } noraise {
    _ => fail("expected reader failure to fail")
  }

  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let handler_ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => {
        raise @jsonrpc.JsonRpcCodecError::ParseError(message="handler fault")
      },
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  input.put(Some(@utf8.encode(runtime_test_request())))
  try connection_runtime_run(handler_ports, runtime_test_options()) catch {
    @runtime.RuntimeError::HandlerFailed => ()
    _ => fail("expected handler failure to be visible")
  } noraise {
    _ => fail("expected handler failure to fail")
  }

  let writer_input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let writer_ports : RuntimePorts = {
    reader: { read: _ => writer_input.get(), },
    writer: {
      write: _ => {
        raise @jsonrpc.JsonRpcCodecError::ParseError(message="writer fault")
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
  writer_input.put(Some(@utf8.encode(runtime_test_request())))
  try connection_runtime_run(writer_ports, runtime_test_options()) catch {
    @runtime.RuntimeError::WriterFailed => ()
    _ => fail("expected writer failure to be visible")
  } noraise {
    _ => fail("expected writer failure to fail")
  }
}

///|
test "runtime writer reports closed and bounded queues" {
  let request = JsonRpcRequest::new(id=Number(1), method_name="work") catch {
    _ => abort("request fixture must have valid params")
  }
  let message : JsonRpcMessage = Request(request)
  let queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(1))
  runtime_writer_offer(queue, 1, message)
  try runtime_writer_offer(queue, 1, message) catch {
    WriterQueueBackpressure(limit=1) => ()
    _ => fail("expected bounded writer queue backpressure")
  } noraise {
    _ => fail("expected bounded writer queue offer to fail")
  }
  queue.close()
  try runtime_writer_offer(queue, 1, message) catch {
    WriterQueueClosed => ()
    _ => fail("expected closed writer queue failure")
  } noraise {
    _ => fail("expected closed writer queue offer to fail")
  }
}

///|
async test "runtime cancellation converts a late raised handler failure" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let started : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let cancel_frame = "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n"
  let traces : Array[RuntimeTraceEvent] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: {
      write: frame => {
        output.push(frame)
        written.put(())
      },
    },
    handlers: {
      request: _ => {
        started.put(())
        gate.get() catch {
          _ => ()
        }
        raise @jsonrpc.JsonRpcCodecError::ParseError(
          message="late handler fault",
        )
      },
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  input.put(Some(@utf8.encode(runtime_test_request())))
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      connection_runtime_run(ports, runtime_test_options())
    })
    let feeder = group.spawn(() => {
      ignore(started.get())
      input.put(Some(@utf8.encode(cancel_frame)))
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(failure)) => assert_eq(failure.error.code, RequestCancelled)
    _ => fail("expected cancellation error response")
  }
  assert_true(traces.any(event => event.phase == "handler_failed_after_cancel"))
}

///|
async test "notification completion events remove exact tokens in reverse" {
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let notification = JsonRpcNotification::new(method_name="notice") catch {
    _ => abort("notification fixture must have valid params")
  }
  let success_handlers : RuntimeHandlerPort = {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => (),
    response: _ => (),
    outbound_failure: None,
  }
  let failure_handlers : RuntimeHandlerPort = {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => {
      raise @jsonrpc.JsonRpcCodecError::ParseError(message="notification fault")
    },
    response: _ => (),
    outbound_failure: None,
  }
  let shutdown = Ref::Ref(false)
  runtime_notification_task(
    11, notification, shutdown, success_handlers, events, 8,
  )
  runtime_notification_task(
    22, notification, shutdown, failure_handlers, events, 8,
  )
  let first = events.get()
  let second = events.get()
  match first {
    RuntimeNotificationCompleted(11) => ()
    _ => fail("expected success completion token")
  }
  match second {
    RuntimeNotificationFailed(22) => ()
    _ => fail("expected failure completion token")
  }
  let started : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let cancellation_handlers : RuntimeHandlerPort = {
    request: _ => HandlerSuccess(Json::null()),
    notification: _ => {
      started.put(())
      gate.get()
    },
    response: _ => (),
    outbound_failure: None,
  }
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      runtime_notification_task(
        33, notification, shutdown, cancellation_handlers, events, 8,
      )
    })
    ignore(started.get())
    task.cancel()
    task.wait()
  })
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 11, request_id: None, cancel: () => (), },
    { task_token: 22, request_id: None, cancel: () => (), },
    { task_token: 33, request_id: None, cancel: () => (), },
  ]
  let cancellation_event = events.get()
  let cancellation_token = match cancellation_event {
    RuntimeNotificationCancelled(token) => token
    _ => fail("expected cancellation completion token")
  }
  let after_cancel = runtime_remove_task(tasks, cancellation_token)
  let after_failure = runtime_remove_task(after_cancel, 22)
  let after_success = runtime_remove_task(after_failure, 11)
  assert_eq(after_success.length(), 0)
}

///|
test "runtime close cancels only active task controls" {
  let cancelled : Array[Int] = []
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 1, request_id: None, cancel: () => cancelled.push(1), },
    { task_token: 2, request_id: None, cancel: () => cancelled.push(2), },
    { task_token: 3, request_id: None, cancel: () => cancelled.push(3), },
  ]
  let active = runtime_remove_task(tasks, 2)
  runtime_cancel_active_tasks(active, _ => ())
  assert_eq(cancelled, [1, 3])
  try runtime_cancel_task(active, Number(99)) catch {
    TaskControlMissing => ()
    _ => fail("expected missing request task control failure")
  } noraise {
    _ => fail("expected missing request task control to fail")
  }
}

///|
async test "runtime close does not enqueue over-capacity notification cancels" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => gate.get() catch { _ => () },
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      if event.phase == "task_cancelled_on_close" {
        close_cancellations.push(())
      }
    },
  }
  let frames = "{\"jsonrpc\":\"2.0\",\"method\":\"n1\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"method\":\"n2\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"method\":\"n3\"}\n"
  input.put(Some(@utf8.encode(frames)))
  input.put(None)
  let options = { ..runtime_test_options(), queue_capacity: 2, }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime close does not enqueue over-capacity notification failures" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => {
        gate.get() catch {
          _ => ()
        }
        raise @jsonrpc.JsonRpcCodecError::ParseError(
          message="late notification fault",
        )
      },
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      if event.phase == "task_cancelled_on_close" {
        close_cancellations.push(())
      }
    },
  }
  let frames = "{\"jsonrpc\":\"2.0\",\"method\":\"n1\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"method\":\"n2\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"method\":\"n3\"}\n"
  input.put(Some(@utf8.encode(frames)))
  input.put(None)
  let options = { ..runtime_test_options(), queue_capacity: 2, }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime close does not enqueue over-capacity request cancels" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => {
        gate.get() catch {
          _ => ()
        }
        HandlerSuccess(Json::null())
      },
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      if event.phase == "task_cancelled_on_close" {
        close_cancellations.push(())
      }
    },
  }
  let frames = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"r1\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"r2\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"r3\"}\n"
  input.put(Some(@utf8.encode(frames)))
  input.put(None)
  let options = { ..runtime_test_options(), queue_capacity: 2, }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime close does not enqueue over-capacity request failures" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: _ => (), },
    handlers: {
      request: _ => {
        gate.get() catch {
          _ => ()
        }
        raise @jsonrpc.JsonRpcCodecError::ParseError(
          message="late request fault",
        )
      },
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      if event.phase == "task_cancelled_on_close" {
        close_cancellations.push(())
      }
    },
  }
  let frames = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"r1\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"r2\"}\n" +
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"r3\"}\n"
  input.put(Some(@utf8.encode(frames)))
  input.put(None)
  let options = { ..runtime_test_options(), queue_capacity: 2, }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime ignores duplicate handler completion exactly once" {
  let traces : Array[RuntimeTraceEvent] = []
  let late : Array[Unit] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(1))
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      traces.push(event)
      if event.phase == "late_handler_completion_ignored" {
        late.push(())
      }
    },
  }
  let request = runtime_wbtest_request(Number(1))
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let decoder = framing_state(max_frame_bytes=256)
  let shutdown = Ref::Ref(false)
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 7, request_id: Some(Number(1)), cancel: () => (), },
  ]
  @async.with_task_group(group => {
    let first = runtime_apply_event(
      RuntimeHandlerCompleted(7, Number(1), HandlerSuccess(Json::null())),
      state,
      decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      tasks,
      0,
      shutdown,
    )
    assert_eq(first.tasks.length(), 0)
    let second = runtime_apply_event(
      RuntimeHandlerCompleted(7, Number(1), HandlerSuccess(Json::null())),
      first.state,
      first.decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      first.tasks,
      first.next_task_token,
      shutdown,
    )
    assert_eq(second.state, first.state)
    assert_eq(second.tasks.length(), 0)
  })
  assert_eq(late.length(), 1)
  match writer_queue.get() {
    RuntimeFrame(frame) =>
      match jsonrpc_decode(@utf8.decode(frame.view())) {
        Response(Success(response)) => assert_eq(response.id, Number(1))
        _ => fail("expected exactly one handler response")
      }
    RuntimeStop => fail("expected response before writer stop")
  }
}

///|
async test "runtime ignores duplicate notification completion exactly once" {
  let traces : Array[RuntimeTraceEvent] = []
  let completed : Array[Unit] = []
  let late : Array[Unit] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(1))
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      traces.push(event)
      if event.phase == "task_completed" {
        completed.push(())
      }
      if event.phase == "late_notification_ignored" {
        late.push(())
      }
    },
  }
  let state = connection_state()
  let decoder = framing_state(max_frame_bytes=256)
  let shutdown = Ref::Ref(false)
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 11, request_id: None, cancel: () => (), },
  ]
  @async.with_task_group(group => {
    let first = runtime_apply_event(
      RuntimeNotificationCompleted(11),
      state,
      decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      tasks,
      0,
      shutdown,
    )
    assert_eq(first.tasks.length(), 0)
    let second = runtime_apply_event(
      RuntimeNotificationCompleted(11),
      first.state,
      first.decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      first.tasks,
      first.next_task_token,
      shutdown,
    )
    assert_eq(second.state, first.state)
    assert_eq(second.tasks.length(), 0)
  })
  assert_eq(completed.length(), 1)
  assert_eq(late.length(), 1)
  assert_eq(traces.length(), 2)
}

///|
async test "runtime ignores duplicate notification failure after close" {
  let failed : Array[Unit] = []
  let late : Array[Unit] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      traces.push(event)
      if event.phase == "notification_failed" {
        failed.push(())
      }
      if event.phase == "late_notification_ignored" {
        late.push(())
      }
    },
  }
  let state = connection_state()
  let decoder = framing_state(max_frame_bytes=256)
  let shutdown = Ref::Ref(false)
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 22, request_id: None, cancel: () => (), },
  ]
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeNotificationFailed(22),
        state,
        decoder,
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        tasks,
        0,
        shutdown,
      ),
    ) catch {
      NotificationFailed => ()
      _ => fail("expected notification failure to close")
    }
    let late_step = runtime_apply_event(
      RuntimeNotificationFailed(22),
      state,
      decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      [],
      0,
      shutdown,
    )
    assert_eq(late_step.state, state)
    assert_eq(late_step.tasks.length(), 0)
  })
  assert_eq(failed.length(), 1)
  assert_eq(late.length(), 1)
  assert_true(shutdown.val)
}

///|
async test "runtime ignores duplicate notification cancellation after completion" {
  let cancelled : Array[Unit] = []
  let late : Array[Unit] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => {
      traces.push(event)
      if event.phase == "task_cancelled" {
        cancelled.push(())
      }
      if event.phase == "late_notification_ignored" {
        late.push(())
      }
    },
  }
  let state = connection_state()
  let decoder = framing_state(max_frame_bytes=256)
  let shutdown = Ref::Ref(false)
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 23, request_id: None, cancel: () => (), },
  ]
  @async.with_task_group(group => {
    let first = runtime_apply_event(
      RuntimeNotificationCancelled(23),
      state,
      decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      tasks,
      0,
      shutdown,
    )
    let second = runtime_apply_event(
      RuntimeNotificationCancelled(23),
      first.state,
      first.decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      first.tasks,
      first.next_task_token,
      shutdown,
    )
    assert_eq(second.state, state)
    assert_eq(second.tasks.length(), 0)
  })
  assert_eq(cancelled.length(), 1)
  assert_eq(late.length(), 1)
  assert_true(!shutdown.val)
}

///|
async test "runtime completion command failure closes another pending request" {
  let failures : Array[RequestId] = []
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  writer_queue.close()
  let first = connection_reduce(
    connection_state(),
    OutgoingRequest(runtime_wbtest_request(Number(40))),
  )
  let sent = connection_reduce(
    first.state,
    OutgoingRequest(runtime_wbtest_request(Number(41))),
  )
  let inbound = connection_reduce(
    sent.state,
    IncomingRequest(runtime_wbtest_request(Number(7))),
  )
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: Some(fn(id, _) { failures.push(id) }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let mut cleanup_error_matches = false
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeHandlerCompleted(5, Number(7), HandlerSuccess(Json::null())),
        inbound.state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [{ task_token: 5, request_id: Some(Number(7)), cancel: () => (), }],
        0,
        shutdown,
      ),
    ) catch {
      @runtime.RuntimeError::CloseCleanupFailed(primary_kind~, cleanup_phase~) =>
        cleanup_error_matches = primary_kind == "writer_queue_closed" &&
          cleanup_phase == "writer_queue_closed"
      _ => fail("unexpected runtime error")
    }
  })
  assert_true(cleanup_error_matches)
  assert_eq(failures, [Number(40), Number(41)])
  assert_true(shutdown.val)
  let command_failures = traces.filter(event => event.phase == "command_failed")
  assert_eq(command_failures.length(), 1)
  assert_eq(command_failures[0].direction, "runtime")
  assert_eq(command_failures[0].request_id, "")
  assert_eq(command_failures[0].method_name, "")
  assert_eq(command_failures[0].error_kind, "writer_queue_closed")
  assert_eq(
    traces.filter(event => event.phase == "outbound_failed").length(),
    2,
  )
}

///|
async test "runtime response callback failure closes remaining outbound once" {
  let failures : Array[RequestId] = []
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let first = connection_reduce(
    connection_state(),
    OutgoingRequest(runtime_wbtest_request(Number(50))),
  )
  let sent = connection_reduce(
    first.state,
    OutgoingRequest(runtime_wbtest_request(Number(51))),
  )
  let response = JsonRpcResponse::success(id=Number(50), result=Json::null())
  let encoded = jsonrpc_encode(Response(response)) catch {
    _ => abort("runtime fixture response must encode")
  }
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => {
        raise @jsonrpc.JsonRpcCodecError::ParseError(
          message="response callback fault",
        )
      },
      outbound_failure: Some(fn(id, _) { failures.push(id) }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let caught : Array[Unit] = []
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeChunk(@utf8.encode(encoded + "\n")),
        sent.state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [],
        0,
        shutdown,
      ),
    ) catch {
      _ => caught.push(())
    }
  })
  assert_eq(caught.length(), 1)
  assert_eq(failures, [Number(50), Number(51)])
  assert_true(shutdown.val)
  assert_true(traces.any(event => event.phase == "response_handler_failed"))
  assert_true(traces.any(event => event.phase == "outbound_failed"))
}

///|
async test "runtime writer failure completes every outbound exactly once" {
  let failures : Array[RequestId] = []
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let first = connection_reduce(
    connection_state(),
    OutgoingRequest(runtime_wbtest_request(Number(60))),
  )
  let sent = connection_reduce(
    first.state,
    OutgoingRequest(runtime_wbtest_request(Number(61))),
  )
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: Some(fn(id, _) { failures.push(id) }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let caught : Array[Unit] = []
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeWriterFailed(WriterFailed),
        sent.state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [],
        0,
        shutdown,
      ),
    ) catch {
      _ => caught.push(())
    }
  })
  assert_eq(caught.length(), 1)
  assert_eq(failures, [Number(60), Number(61)])
  assert_true(shutdown.val)
  assert_true(traces.any(event => event.phase == "writer_failed"))
  assert_true(traces.any(event => event.phase == "outbound_failed"))
}

///|
async test "runtime outbound cancellation uses callback once and rejects missing callback" {
  let cancelled : Array[RequestId] = []
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: Some(fn(id) { cancelled.push(id) }),
    trace: event => traces.push(event),
  }
  runtime_emit_command(
    CancelOutboundTask(id=Number(70)),
    writer_queue,
    8,
    ports,
    [],
    Ref(runtime_outbound_registry()),
  )
  assert_eq(cancelled, [Number(70)])
  assert_eq(
    traces.filter(event => event.phase == "cancel_requested").length(),
    1,
  )
  let missing_ports : RuntimePorts = { ..ports, cancel_outbound: None, }
  try
    runtime_emit_command(
      CancelOutboundTask(id=Number(71)),
      writer_queue,
      8,
      missing_ports,
      [],
      Ref(runtime_outbound_registry()),
    )
  catch {
    OutboundCancelUnavailable => ()
    _ => fail("expected missing outbound cancel callback to fail")
  } noraise {
    _ => fail("expected missing outbound cancel callback to fail")
  }
  assert_eq(cancelled, [Number(70)])
}

///|
async test "runtime completion reducer failure closes every pending outbound once" {
  let failures : Array[RequestId] = []
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let first = connection_reduce(
    connection_state(),
    OutgoingRequest(runtime_wbtest_request(Number(80))),
  )
  let sent = connection_reduce(
    first.state,
    OutgoingRequest(runtime_wbtest_request(Number(81))),
  )
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: Some(fn(id, _) { failures.push(id) }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let caught : Array[Unit] = []
  @async.with_task_group(group => {
    try {
      let _result : Unit = runtime_fail_and_close_of(
        group,
        sent.state,
        "completion",
        ReducerFailed,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [],
        0,
        shutdown,
        false,
        (),
        runtime_wbtest_unit_close_owner,
        Ref(runtime_outbound_registry()),
      )
    } catch {
      _ => caught.push(())
    }
  })
  assert_eq(caught.length(), 1)
  assert_eq(failures, [Number(80), Number(81)])
  assert_true(shutdown.val)
  assert_eq(
    traces.filter(event => event.phase == "outbound_failed").length(),
    2,
  )
}

///|
test "runtime cleanup error preserves primary and cleanup categories" {
  let combined = runtime_close_cleanup_error(
    WriterFailed,
    OutboundCompletionFailed,
  )
  match combined {
    CloseCleanupFailed(primary_kind~, cleanup_phase~) => {
      assert_eq(primary_kind, "writer_failed")
      assert_eq(cleanup_phase, "outbound_completion_failed")
    }
    _ => fail("expected primary and cleanup categories")
  }
}

///|
async test "runtime rejects completion with a mismatched task request" {
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let request = runtime_wbtest_request(Number(2))
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let mut mismatch_error_matches = false
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeHandlerCompleted(7, Number(2), HandlerSuccess(Json::null())),
        state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [{ task_token: 7, request_id: Some(Number(1)), cancel: () => (), }],
        0,
        shutdown,
      ),
    ) catch {
      @runtime.RuntimeError::TaskRequestMismatch =>
        mismatch_error_matches = true
      _ => fail("unexpected runtime error")
    }
  })
  assert_true(mismatch_error_matches)
  assert_true(shutdown.val)
  assert_eq(
    traces.filter(event => event.phase == "task_request_mismatch").length(),
    1,
  )
  match writer_queue.get() {
    RuntimeFrame(frame) =>
      match jsonrpc_decode(@utf8.decode(frame.view())) {
        Response(Error(response)) => assert_eq(response.id, Number(2))
        _ => fail("mismatched completion must not produce a success response")
      }
    RuntimeStop => fail("expected the close failure response before stop")
  }
}

///|
async test "runtime rejects failed completion with a mismatched task request" {
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let state = connection_state()
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let tasks : Array[RuntimeTaskControl] = [
    { task_token: 8, request_id: Some(Number(11)), cancel: () => (), },
  ]
  let mut mismatch_error_matches = false
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeHandlerFailed(8, Number(12)),
        state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        tasks,
        0,
        shutdown,
      ),
    ) catch {
      @runtime.RuntimeError::TaskRequestMismatch =>
        mismatch_error_matches = true
      _ => fail("unexpected runtime error")
    }
  })
  assert_true(mismatch_error_matches)
  assert_true(shutdown.val)
  let mismatches = traces.filter(event => event.phase == "task_request_mismatch")
  assert_eq(mismatches.length(), 1)
  assert_eq(mismatches[0].direction, "inbound")
  assert_eq(mismatches[0].request_id, "12")
  assert_eq(mismatches[0].method_name, "")
  assert_eq(mismatches[0].error_kind, "task_control")
  let queued = writer_queue.try_get() catch {
    _ => fail("mismatch must not close the writer queue before inspection")
  }
  match queued {
    None => ()
    Some(RuntimeStop) => ()
    Some(RuntimeFrame(_)) => fail("failed mismatch must not produce a response")
  }
  assert_eq(tasks.length(), 1)
  assert_eq(tasks[0].task_token, 8)
  assert_eq(tasks[0].request_id, Some(Number(11)))
  assert_eq(state.inbound.length(), 0)
  assert_eq(state.settled_inbound.length(), 0)
}

///|
async test "runtime ignores a late failed handler after completion" {
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let state = connection_reduce(
      connection_state(),
      IncomingRequest(runtime_wbtest_request(Number(13))),
    ).state
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  @async.with_task_group(group => {
    let first = runtime_apply_event(
      RuntimeHandlerCompleted(9, Number(13), HandlerSuccess(Json::null())),
      state,
      framing_state(max_frame_bytes=256),
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      [{ task_token: 9, request_id: Some(Number(13)), cancel: () => (), }],
      0,
      shutdown,
    )
    assert_eq(first.state.settled_inbound, [Number(13)])
    assert_eq(first.state.inbound.length(), 0)
    let second = runtime_apply_event(
      RuntimeHandlerFailed(9, Number(13)),
      first.state,
      first.decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      first.tasks,
      first.next_task_token,
      shutdown,
    )
    assert_eq(second.state, first.state)
    assert_eq(second.tasks.length(), 0)
  })
  assert_true(state.settled_inbound.length() == 0)
  assert_eq(
    traces
    .filter(event => event.phase == "late_handler_failure_ignored")
    .length(),
    1,
  )
  assert_true(!shutdown.val)
}

///|
async test "runtime event queue closure has a structured seam" {
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  events.close()
  let mut queue_error_matches = false
  @async.with_task_group(_group => {
    ignore(runtime_event_get(events)) catch {
      EventQueueClosed => queue_error_matches = true
      _ => fail("unexpected runtime error")
    }
  })
  assert_true(queue_error_matches)
}

///|
async test "runtime traces an unwritten inbound failure when writer is broken" {
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  writer_queue.close()
  let state = connection_reduce(
      connection_state(),
      IncomingRequest(runtime_wbtest_request(Number(14))),
    ).state
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let mut cleanup_error_matches = false
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeWriterFailed(WriterFailed),
        state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [],
        0,
        shutdown,
      ),
    ) catch {
      @runtime.RuntimeError::CloseCleanupFailed(primary_kind~, cleanup_phase~) =>
        cleanup_error_matches = primary_kind == "writer_failed" &&
          cleanup_phase == "writer_queue_closed"
      _ => fail("unexpected runtime error")
    }
  })
  assert_true(cleanup_error_matches)
  let writer_failures = traces.filter(event => event.phase == "writer_failed")
  assert_eq(writer_failures.length(), 1)
  assert_eq(writer_failures[0].direction, "outbound")
  assert_eq(writer_failures[0].request_id, "")
  assert_eq(writer_failures[0].method_name, "")
  assert_eq(writer_failures[0].error_kind, "writer")
  let unwritten = traces.filter(event => {
    event.phase == "inbound_failure_unwritten"
  })
  assert_eq(unwritten.length(), 1)
  assert_eq(unwritten[0].direction, "inbound")
  assert_eq(unwritten[0].request_id, "14")
  assert_eq(unwritten[0].method_name, "")
  assert_eq(unwritten[0].error_kind, "writer")
  let settled = connection_reduce(state, Close(reason="writer")).state
  assert_eq(settled.inbound.length(), 0)
  assert_eq(settled.settled_inbound, [Number(14)])
}

///|
async test "runtime traces only unwritten inbound failures after bounded writer backpressure" {
  let traces : Array[RuntimeTraceEvent] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(1))
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let first = connection_reduce(
    connection_state(),
    IncomingRequest(runtime_wbtest_request(Number(15))),
  )
  let second = connection_reduce(
    first.state,
    IncomingRequest(runtime_wbtest_request(Number(16))),
  )
  let pending = connection_reduce(
    second.state,
    IncomingRequest(runtime_wbtest_request(Number(17))),
  )
  let state = pending.state
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let mut primary_category = ""
  let mut cleanup_category = ""
  @async.with_task_group(group => {
    ignore(
      runtime_apply_event(
        RuntimeWriterFailed(WriterFailed),
        state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        [],
        0,
        shutdown,
      ),
    ) catch {
      @runtime.RuntimeError::CloseCleanupFailed(primary_kind~, cleanup_phase~) => {
        primary_category = primary_kind
        cleanup_category = cleanup_phase
      }
      _ => fail("expected structured bounded writer backpressure")
    }
  })
  assert_eq(primary_category, "writer_failed")
  assert_eq(cleanup_category, "writer_queue_backpressure")
  assert_true(shutdown.val)
  let written_failures = traces.filter(event => event.phase == "inbound_failed")
  assert_eq(written_failures.length(), 1)
  assert_eq(written_failures[0].request_id, "15")
  assert_eq(written_failures[0].direction, "inbound")
  assert_eq(written_failures[0].method_name, "")
  assert_eq(written_failures[0].error_kind, "close")
  let unwritten = traces.filter(event => {
    event.phase == "inbound_failure_unwritten"
  })
  assert_eq(unwritten.length(), 2)
  let unwritten_ids : Array[String] = []
  for event in unwritten {
    unwritten_ids.push(event.request_id)
    assert_eq(event.direction, "inbound")
    assert_eq(event.method_name, "")
    assert_eq(event.error_kind, "writer")
  }
  assert_eq(unwritten_ids, ["16", "17"])
  let settled = connection_reduce(state, Close(reason="writer")).state
  assert_eq(settled.inbound.length(), 0)
  assert_eq(settled.settled_inbound, [Number(15), Number(16), Number(17)])
  assert_eq(settled.settled_inbound.filter(id => id == Number(15)).length(), 1)
  assert_eq(settled.settled_inbound.filter(id => id == Number(16)).length(), 1)
  assert_eq(settled.settled_inbound.filter(id => id == Number(17)).length(), 1)
}

///|
struct RuntimeOwnerTestState {
  admitted : Array[RequestId]
  completed : Array[Int]
  cancelled : Array[RequestId]
  aborted : Array[Int]
  notifications : Array[Int]
} derive(Eq, Debug)

///|
fn runtime_owner_test_state() -> RuntimeOwnerTestState {
  {
    admitted: [],
    completed: [],
    cancelled: [],
    aborted: [],
    notifications: [],
  }
}

///|
fn runtime_owner_test_push_id(
  values : Array[RequestId],
  id : RequestId,
) -> Array[RequestId] {
  let next = Array::copy(values)
  next.push(id)
  next
}

///|
fn runtime_owner_test_push_int(values : Array[Int], value : Int) -> Array[Int] {
  let next = Array::copy(values)
  next.push(value)
  next
}

///|
fn runtime_owner_test_port() -> RuntimeOwnerPort[
  RuntimeOwnerTestState,
  Int,
  Int,
  Unit,
] {
  {
    initial_state: runtime_owner_test_state(),
    admit_request: (state, id, _) => {
      RuntimeOwnerRequestInvoke(
        state={
          ..state,
          admitted: runtime_owner_test_push_id(state.admitted, id),
        },
        invocation=if id == Number(1) { 1 } else { 2 },
      )
    },
    admit_notification: (state, _) => {
      RuntimeOwnerNotificationInvoke(state~, invocation=7)
    },
    execute: fn(value) { value },
    execute_failure: (_, _) => -2,
    execute_cancel: (_, _) => -3,
    complete_request: (state, _, _, completion) => {
      state: {
        ..state,
        completed: runtime_owner_test_push_int(state.completed, completion),
      },
      response: HandlerSuccess(
        Json::number(completion.to_double(), repr=completion.to_string()),
      ),
      effects: [],
    },
    complete_notification: (state, _, completion) => {
      state: {
        ..state,
        notifications: runtime_owner_test_push_int(
          state.notifications,
          completion,
        ),
      },
      effects: [],
    },
    plan_local_effect: _ => RuntimeOwnerNoCommands,
    cancel_request: (state, id, _) => {
      (
        { ..state, cancelled: runtime_owner_test_push_id(state.cancelled, id), },
        -1,
      )
    },
    abort: (state, task) => {
      ..state,
      aborted: runtime_owner_test_push_int(state.aborted, task.task_token()),
    },
  }
}

///|
fn runtime_owner_run_immediate_port(
  response : RuntimeHandlerResult,
  request_effects : Array[RuntimeOwnerEffect[Unit]],
  notification_effects : Array[RuntimeOwnerEffect[Unit]],
) -> RuntimeOwnerPort[RuntimeOwnerTestState, Unit, Unit, Unit] {
  {
    initial_state: runtime_owner_test_state(),
    admit_request: (state, id, _) => {
      RuntimeOwnerRequestImmediate(completion={
        state: {
          ..state,
          admitted: runtime_owner_test_push_id(state.admitted, id),
        },
        response,
        effects: request_effects,
      })
    },
    admit_notification: (state, _) => {
      RuntimeOwnerNotificationImmediate(completion={
        state: {
          ..state,
          notifications: runtime_owner_test_push_int(state.notifications, 1),
        },
        effects: notification_effects,
      })
    },
    execute: fn(_) { () },
    execute_failure: (_, _) => (),
    execute_cancel: (_, _) => (),
    complete_request: (_, _, _, _) => {
      abort("owner immediate request must not complete asynchronously")
    },
    complete_notification: (_, _, _) => {
      abort("owner immediate notification must not complete asynchronously")
    },
    plan_local_effect: _ => RuntimeOwnerNoCommands,
    cancel_request: (state, _, _) => (state, ()),
    abort: (state, _) => state,
  }
}

///|
fn runtime_owner_run_runtime_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[RuntimeTraceEvent],
) -> RuntimePorts {
  {
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
    trace: event => traces.push(event),
  }
}

///|
fn runtime_owner_test_request(id : RequestId) -> JsonRpcRequest {
  JsonRpcRequest::new(id~, method_name="owner") catch {
    _ => abort("owner request fixture must be valid")
  }
}

///|
fn runtime_owner_test_notification() -> JsonRpcNotification {
  JsonRpcNotification::new(method_name="owner-notification") catch {
    _ => abort("owner notification fixture must be valid")
  }
}

///|
fn runtime_owner_effect_test_notification() -> JsonRpcNotification {
  JsonRpcNotification::new(method_name="owner/update") catch {
    _ => abort("owner effect notification fixture must be valid")
  }
}

///|
async test "runtime applies owner commands in order" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(2))
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[RequestId] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let notification = runtime_owner_effect_test_notification()
  let (_, result) = runtime_apply_owner_commands_of(
    [
      RuntimeOwnerWriteNotification(notification~),
      RuntimeOwnerTrace(method_name="owner/work"),
      RuntimeOwnerCancelInbound(request_id=Number(9)),
    ],
    writer_queue,
    runtime_test_options(),
    ports,
    [
      {
        task_token: 9,
        request_id: Some(Number(9)),
        cancel: () => cancelled.push(Number(9)),
      },
    ],
    (),
    runtime_wbtest_unit_cancel_inbound,
  )
  match result {
    RuntimeOwnerCommandsComplete => ()
    RuntimeOwnerCloseRequested(_) => fail("owner commands must complete")
  }
  match writer_queue.get() {
    RuntimeFrame(frame) =>
      match jsonrpc_decode(@utf8.decode(frame.view())) {
        Notification(actual) => assert_eq(actual, notification)
        _ => fail("owner notification must be queued as a notification")
      }
    RuntimeStop => fail("owner notification must be queued before stop")
  }
  assert_eq(traces.length(), 2)
  assert_eq(traces[0].direction, "runtime")
  assert_eq(traces[0].phase, "owner_trace")
  assert_eq(traces[0].request_id, "")
  assert_eq(traces[0].method_name, "owner/work")
  assert_eq(traces[0].error_kind, "owner")
  assert_eq(traces[1].direction, "inbound")
  assert_eq(traces[1].phase, "cancel_requested")
  assert_eq(traces[1].request_id, "9")
  assert_eq(traces[1].method_name, "")
  assert_eq(traces[1].error_kind, "cancel")
  assert_eq(cancelled, [Number(9)])
}

///|
async test "runtime owner close command stops interpretation" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(2))
  let traces : Array[RuntimeTraceEvent] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let (_, result) = runtime_apply_owner_commands_of(
    [
      RuntimeOwnerClose(reason="owner requested close"),
      RuntimeOwnerTrace(method_name="after-close"),
      RuntimeOwnerWriteNotification(
        notification=runtime_owner_effect_test_notification(),
      ),
    ],
    writer_queue,
    runtime_test_options(),
    ports,
    [],
    (),
    runtime_wbtest_unit_cancel_inbound,
  )
  match result {
    RuntimeOwnerCloseRequested(reason~) =>
      assert_eq(reason, "owner requested close")
    RuntimeOwnerCommandsComplete => fail("owner close must return close result")
  }
  assert_eq(traces.length(), 0)
  let queued = writer_queue.try_get() catch {
    _ => fail("owner close queue inspection must succeed")
  }
  match queued {
    None => ()
    Some(_) => fail("commands after owner close must not be executed")
  }
}

///|
async test "runtime owner missing cancellation stops interpretation" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(2))
  let traces : Array[RuntimeTraceEvent] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let mut raised = false
  try
    ignore(
      runtime_apply_owner_commands_of(
        [
          RuntimeOwnerCancelInbound(request_id=Number(99)),
          RuntimeOwnerTrace(method_name="after-missing-cancel"),
          RuntimeOwnerWriteNotification(
            notification=runtime_owner_effect_test_notification(),
          ),
        ],
        writer_queue,
        runtime_test_options(),
        ports,
        [],
        (),
        runtime_wbtest_unit_cancel_inbound,
      ),
    )
  catch {
    TaskControlMissing => raised = true
    _ => fail("missing owner cancellation must raise TaskControlMissing")
  } noraise {
    _ => fail("missing owner cancellation must raise")
  }
  assert_true(raised)
  assert_eq(traces.length(), 0)
  let queued = writer_queue.try_get() catch {
    _ => fail("owner missing-cancel queue inspection must succeed")
  }
  match queued {
    None => ()
    Some(_) => fail("commands after missing cancellation must not be executed")
  }
}

///|
enum RuntimeOwnerPlanTestEffect {
  NoCommands
  Expand
  Close
} derive(Eq, Debug)

///|
fn runtime_owner_plan_test_local(
  effect : RuntimeOwnerPlanTestEffect,
) -> RuntimeOwnerLocalPlan {
  match effect {
    NoCommands => RuntimeOwnerNoCommands
    Expand =>
      RuntimeOwnerCommands([
        RuntimeOwnerTrace(method_name="owner"),
        RuntimeOwnerCancelInbound(request_id=Number(7)),
      ])
    Close =>
      RuntimeOwnerCommands([RuntimeOwnerClose(reason="owner requested close")])
  }
}

///|
async test "runtime owner runner emits immediate success response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  let owner_port = runtime_owner_run_immediate_port(
    HandlerSuccess(Json::string("owner-success")),
    [],
    [],
  )
  input.put(
    Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"owner\"}\n")),
  )
  input.put(None)
  connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Success(response)) => {
      assert_eq(response.id, Number(41))
      assert_eq(response.result, Json::string("owner-success"))
    }
    _ => fail("owner runner must emit the immediate success response")
  }
}

///|
async test "runtime owner runner emits immediate handler error response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  let error = JsonRpcError::invalid_params()
  let owner_port = runtime_owner_run_immediate_port(HandlerError(error), [], [])
  input.put(
    Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"owner\"}\n")),
  )
  input.put(None)
  connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(response)) => {
      assert_eq(response.id, Number(42))
      assert_eq(response.error, error)
    }
    _ => fail("owner runner must emit the immediate handler error")
  }
}

///|
async test "runtime owner runner emits notification effect without response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let notification = JsonRpcNotification::new(method_name="owner/update") catch {
    _ => abort("owner runner notification fixture must be valid")
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  let owner_port = runtime_owner_run_immediate_port(
    HandlerSuccess(Json::null()),
    [],
    [WireNotification(notification~)],
  )
  input.put(Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"method\":\"owner\"}\n")))
  input.put(None)
  connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Notification(actual) => assert_eq(actual, notification)
    _ => fail("owner notification effect must not produce a response")
  }
}

///|
async test "runtime owner runner completes concurrent requests in reverse order once" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let started : @aqueue.Queue[Int] = Queue(kind=Unbounded)
  let release_one : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let release_two : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let start_order : Array[Int] = []
  let base = runtime_owner_test_port()
  let owner_port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..base,
    execute: value => {
      started.put(value)
      if value == 1 {
        release_one.get()
      } else {
        release_two.get()
      }
      value
    },
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  input.put(
    Some(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"owner\"}\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"owner\"}\n",
      ),
    ),
  )
  @async.with_task_group(group => {
    let feeder = group.spawn(() => {
      start_order.push(started.get())
      start_order.push(started.get())
      release_two.put(())
      release_one.put(())
      written.get()
      written.get()
      input.put(None)
    })
    connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
    feeder.wait()
  })
  assert_eq(start_order, [1, 2])
  assert_eq(output.length(), 2)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Success(response)) => {
      assert_eq(response.id, Number(2))
      assert_eq(response.result, Json::number(2.0, repr="2"))
    }
    _ => fail("first reverse completion response must be request two")
  }
  match jsonrpc_decode(@utf8.decode(output[1].view())) {
    Response(Success(response)) => {
      assert_eq(response.id, Number(1))
      assert_eq(response.result, Json::number(1.0, repr="1"))
    }
    _ => fail("second reverse completion response must be request one")
  }
}

///|
async test "runtime owner execute failure becomes one typed error response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let error = JsonRpcError::internal_error()
  let base = runtime_owner_test_port()
  let owner_port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..base,
    execute: _ => {
      raise @jsonrpc.JsonRpcCodecError::ParseError(
        message="owner execute fault",
      )
    },
    execute_failure: (_, _) => -88,
    complete_request: (state, _, _, completion) => {
      state: {
        ..state,
        completed: runtime_owner_test_push_int(state.completed, completion),
      },
      response: if completion == -88 {
        HandlerError(error)
      } else {
        HandlerSuccess(Json::null())
      },
      effects: [],
    },
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  input.put(
    Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":43,\"method\":\"owner\"}\n")),
  )
  @async.with_task_group(group => {
    let feeder = group.spawn(() => {
      written.get()
      input.put(None)
    })
    connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(response)) => {
      assert_eq(response.id, Number(43))
      assert_eq(response.error, error)
    }
    _ => fail("owner execute failure must produce one typed error")
  }
}

///|
async test "runtime owner notification invoke applies effects without a response" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let notification = runtime_owner_effect_test_notification()
  let base = runtime_owner_effect_test_port()
  let owner_port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, String] = {
    ..base,
    complete_notification: (state, _, completion) => {
      state: {
        ..state,
        notifications: runtime_owner_test_push_int(
          state.notifications,
          completion,
        ),
      },
      effects: [
        WireNotification(notification~),
        Local(effect="notification-effect"),
      ],
    },
    plan_local_effect: effect => {
      RuntimeOwnerCommands([RuntimeOwnerTrace(method_name=effect)])
    },
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  input.put(Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"method\":\"owner\"}\n")))
  @async.with_task_group(group => {
    let feeder = group.spawn(() => {
      written.get()
      input.put(None)
    })
    connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
    feeder.wait()
  })
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Notification(actual) => assert_eq(actual, notification)
    _ => fail("notification invoke must emit its wire effect only")
  }
  let local_effects = traces.filter(event => {
    event.phase == "owner_trace" && event.method_name == "notification-effect"
  })
  assert_eq(local_effects.length(), 1)
}

///|
async test "runtime owner task publication failure propagates from a closed queue" {
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  events.close()
  let shutdown = Ref::Ref(false)
  let task : RuntimeOwnerTask[Int] = {
    task_token: 0,
    request_id: Some(Number(1)),
    invocation: 1,
    notification: false,
    cancel_requested: false,
  }
  let mut raised = false
  try
    @async.with_task_group(group => {
      let child = group.spawn(() => {
        runtime_owner_task_loop(
          task,
          runtime_owner_test_port(),
          events,
          shutdown,
          1,
        )
      })
      child.wait()
    })
  catch {
    @runtime.RuntimeError::EventQueueClosed => raised = true
    _ => fail("closed owner event queue failure must propagate")
  } noraise {
    _ => fail("closed owner event queue failure must raise")
  }
  assert_true(raised)
}

///|
async test "runtime owner task publication backpressure propagates without hang" {
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Blocking(1))
  events.put(RuntimeChunk(@utf8.encode("occupied")))
  let shutdown = Ref::Ref(false)
  let task : RuntimeOwnerTask[Int] = {
    task_token: 0,
    request_id: Some(Number(1)),
    invocation: 1,
    notification: false,
    cancel_requested: false,
  }
  let mut raised_limit = 0
  try
    @async.with_task_group(group => {
      let child = group.spawn(() => {
        runtime_owner_task_loop(
          task,
          runtime_owner_test_port(),
          events,
          shutdown,
          1,
        )
      })
      child.wait()
    })
  catch {
    @runtime.RuntimeError::EventQueueBackpressure(limit~) =>
      raised_limit = limit
    _ => fail("owner event queue backpressure must propagate")
  } noraise {
    _ => fail("owner event queue backpressure must raise")
  }
  assert_eq(raised_limit, 1)
}

///|
async test "runtime owner runtime rejects token and id mismatch fail-fast" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let cancelled : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  let owner_port = runtime_owner_test_port()
  let request = runtime_owner_test_request(Number(1))
  let owner = runtime_owner_new(owner_port)
  let (owner, action) = runtime_owner_admit_request(owner, request, owner_port) catch {
    _ => abort("mismatch owner admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("mismatch owner request must invoke")
  }
  let context : RuntimeOwnerDispatchContext[
    RuntimeOwnerTestState,
    Int,
    Int,
    Unit,
  ] = {
    owner,
    port: owner_port,
    events,
    shutdown,
    limit: runtime_test_options().queue_capacity,
  }
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let dispatch : RuntimeDispatchPort[
    _,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()
  @async.with_task_group(group => {
    let mut raised = false
    try
      runtime_apply_event_of(
        RuntimeOwnerTaskEvent(
          RuntimeOwnerTaskCompleted(
            event=RuntimeOwnerRequestCompleted(
              token=task.task_token(),
              id=Number(99),
              completion=1,
            ),
          ),
        ),
        state,
        framing_state(max_frame_bytes=256),
        group,
        writer_queue,
        runtime_test_options(),
        ports,
        events,
        runtime_owner_handler_result_unavailable,
        dispatch,
        runtime_owner_apply_task_event,
        context,
        [
          {
            task_token: task.task_token(),
            request_id: Some(Number(1)),
            cancel: () => cancelled.push(()),
          },
        ],
        1,
        shutdown,
        Ref(runtime_outbound_registry()),
      )
    catch {
      @runtime.RuntimeError::TaskRequestMismatch => raised = true
      _ => fail("mismatched owner event must raise TaskRequestMismatch")
    } noraise {
      _ => fail("mismatched owner event must raise")
    }
    assert_true(raised)
  })
  assert_eq(cancelled.length(), 1)
}

///|
async test "runtime owner runtime ignores a duplicate completion after settling" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let owner_port = runtime_owner_test_port()
  let request = runtime_owner_test_request(Number(1))
  let (owner, action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    request,
    owner_port,
  ) catch {
    _ => abort("duplicate owner admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("duplicate owner request must invoke")
  }
  let context : RuntimeOwnerDispatchContext[
    RuntimeOwnerTestState,
    Int,
    Int,
    Unit,
  ] = {
    owner,
    port: owner_port,
    events,
    shutdown,
    limit: runtime_test_options().queue_capacity,
  }
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let dispatch : RuntimeDispatchPort[
    _,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()
  let event = RuntimeOwnerTaskEvent(
    RuntimeOwnerTaskCompleted(
      event=RuntimeOwnerRequestCompleted(
        token=task.task_token(),
        id=Number(1),
        completion=1,
      ),
    ),
  )
  @async.with_task_group(group => {
    let (first, next_context) = runtime_apply_event_of(
      event,
      state,
      framing_state(max_frame_bytes=256),
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      runtime_owner_handler_result_unavailable,
      dispatch,
      runtime_owner_apply_task_event,
      context,
      [
        {
          task_token: task.task_token(),
          request_id: Some(Number(1)),
          cancel: () => (),
        },
      ],
      1,
      shutdown,
      Ref(runtime_outbound_registry()),
    )
    assert_eq(first.tasks.length(), 0)
    let (second, _) = runtime_apply_event_of(
      event,
      first.state,
      first.decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      runtime_owner_handler_result_unavailable,
      dispatch,
      runtime_owner_apply_task_event,
      next_context,
      first.tasks,
      first.next_task_token,
      shutdown,
      Ref(runtime_outbound_registry()),
    )
    assert_eq(second.tasks.length(), 0)
  })
  match writer_queue.get() {
    RuntimeFrame(_) => ()
    RuntimeStop => fail("settled owner request must queue one response")
  }
  let duplicate = writer_queue.try_get() catch { _ => None }
  match duplicate {
    None => ()
    Some(_) =>
      fail("duplicate owner completion must not queue another response")
  }
  let late = traces.filter(event => {
    event.phase == "late_owner_completion_ignored"
  })
  assert_eq(late.length(), 1)
}

///|
fn runtime_owner_effect_test_port() -> RuntimeOwnerPort[
  RuntimeOwnerTestState,
  Int,
  Int,
  String,
] {
  {
    initial_state: runtime_owner_test_state(),
    admit_request: (state, id, _) => {
      RuntimeOwnerRequestInvoke(
        state={
          ..state,
          admitted: runtime_owner_test_push_id(state.admitted, id),
        },
        invocation=9,
      )
    },
    admit_notification: (state, _) => {
      RuntimeOwnerNotificationInvoke(state~, invocation=10)
    },
    execute: fn(value) { value },
    execute_failure: (_, _) => -2,
    execute_cancel: (_, _) => -3,
    complete_request: (state, _, _, completion) => {
      state: {
        ..state,
        completed: runtime_owner_test_push_int(state.completed, completion),
      },
      response: HandlerSuccess(Json::string("request-result")),
      effects: [
        WireNotification(notification=runtime_owner_effect_test_notification()),
        Local(effect="request-effect"),
      ],
    },
    complete_notification: (state, _, completion) => {
      state: {
        ..state,
        notifications: runtime_owner_test_push_int(
          state.notifications,
          completion,
        ),
      },
      effects: [Local(effect="notification-effect")],
    },
    plan_local_effect: _ => RuntimeOwnerNoCommands,
    cancel_request: (state, id, _) => {
      (
        { ..state, cancelled: runtime_owner_test_push_id(state.cancelled, id), },
        -1,
      )
    },
    abort: (state, task) => {
      ..state,
      aborted: runtime_owner_test_push_int(state.aborted, task.task_token()),
    },
  }
}

///|
test "runtime owner completions atomically return wire and local effects" {
  let port = runtime_owner_effect_test_port()
  let owner = runtime_owner_new(port)
  let (owner, action) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(20)),
    port,
  ) catch {
    _ => abort("effect request admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("effect request must invoke")
  }
  let result = runtime_owner_complete_request(
    owner,
    RuntimeOwnerRequestCompleted(
      token=task.task_token(),
      id=Number(20),
      completion=9,
    ),
    port,
  )
  let (owner, completion) = match result {
    RuntimeOwnerCompletionApplied(owner~, completion~) => (owner, completion)
    RuntimeOwnerCompletionIgnored(reason=_) =>
      abort("effect request completion must apply")
  }
  assert_eq(completion.state, owner.state())
  assert_eq(owner.state().completed, [9])
  assert_eq(owner.task_count(), 0)
  match completion.response {
    HandlerSuccess(String(value)) => assert_eq(value, "request-result")
    _ => fail("request completion must contain one response")
  }
  assert_eq(completion.effects.length(), 2)
  match completion.effects[0] {
    WireNotification(notification~) =>
      assert_eq(notification, runtime_owner_effect_test_notification())
    _ => fail("request completion must retain wire notification effect")
  }
  match completion.effects[1] {
    Local(effect~) => assert_eq(effect, "request-effect")
    _ => fail("request completion must retain local effect")
  }

  let (owner, action) = runtime_owner_admit_notification(
    owner,
    runtime_owner_test_notification(),
    port,
  ) catch {
    _ => abort("effect notification admission must succeed")
  }
  let task = match action {
    RuntimeOwnerNotificationInvoke(task~) => task
    _ => abort("effect notification must invoke")
  }
  let result = runtime_owner_complete_notification(
    owner,
    RuntimeOwnerNotificationCompleted(token=task.task_token(), completion=10),
    port,
  )
  let (owner, completion) = match result {
    RuntimeOwnerCompletionApplied(owner~, completion~) => (owner, completion)
    RuntimeOwnerCompletionIgnored(reason=_) =>
      abort("effect notification completion must apply")
  }
  assert_eq(completion.state, owner.state())
  assert_eq(owner.state().notifications, [10])
  assert_eq(owner.task_count(), 0)
  assert_eq(completion.effects.length(), 1)
  match completion.effects[0] {
    Local(effect~) => assert_eq(effect, "notification-effect")
    _ => fail("notification completion must retain local effect")
  }
}

///|
test "runtime owner effect plan preserves wire order and expands local effects" {
  let first = runtime_owner_effect_test_notification()
  let second = JsonRpcNotification::new(method_name="owner/next") catch {
    _ => abort("second owner effect notification fixture must be valid")
  }
  let effects : Array[RuntimeOwnerEffect[RuntimeOwnerPlanTestEffect]] = [
    WireNotification(notification=first),
    Local(effect=NoCommands),
    Local(effect=Expand),
    WireNotification(notification=second),
    Local(effect=Close),
  ]
  let commands = runtime_owner_plan_effects(
    effects, runtime_owner_plan_test_local,
  )
  assert_eq(commands.length(), 5)
  match commands[0] {
    RuntimeOwnerWriteNotification(notification~) =>
      assert_eq(notification, first)
    _ => fail("first wire effect must stay first")
  }
  match commands[1] {
    RuntimeOwnerTrace(method_name~) => assert_eq(method_name, "owner")
    _ => fail("local planner must preserve its first command")
  }
  match commands[2] {
    RuntimeOwnerCancelInbound(request_id=Number(value)) => assert_eq(value, 7)
    _ => fail("local planner must retain the request id")
  }
  match commands[3] {
    RuntimeOwnerWriteNotification(notification~) =>
      assert_eq(notification, second)
    _ => fail("later wire effect must follow expanded local commands")
  }
  match commands[4] {
    RuntimeOwnerClose(reason~) => assert_eq(reason, "owner requested close")
    _ => fail("later local effect must remain last")
  }
  assert_eq(
    runtime_owner_plan_effects([], runtime_owner_plan_test_local).length(),
    0,
  )
  assert_eq(
    runtime_owner_plan_effects(
      [Local(effect=NoCommands)],
      runtime_owner_plan_test_local,
    ).length(),
    0,
  )
}

///|
test "runtime owner admits two requests before completion" {
  let port = runtime_owner_test_port()
  let owner = runtime_owner_new(port)
  let (owner, first) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(1)),
    port,
  ) catch {
    _ => abort("first owner admission must succeed")
  }
  let (owner, second) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(2)),
    port,
  ) catch {
    _ => abort("second owner admission must succeed")
  }
  match (first, second) {
    (RuntimeOwnerInvoke(task=first_task), RuntimeOwnerInvoke(task=second_task)) => {
      assert_eq(first_task.task_token(), 0)
      assert_eq(second_task.task_token(), 1)
      assert_eq(owner.task_count(), 2)
      assert_eq(owner.state().admitted, [Number(1), Number(2)])
    }
    _ => fail("both requests must cross the async seam")
  }
}

///|
async test "runtime owner executes overlapping requests and completes reverse order" {
  let started : @aqueue.Queue[Int] = Queue(kind=Unbounded)
  let first_gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let second_gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..runtime_owner_test_port(),
    execute: async fn(value) {
      started.put(value)
      if value == 1 {
        first_gate.get()
      } else {
        second_gate.get()
      }
      value
    },
  }
  let owner = runtime_owner_new(port)
  let (owner, first) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(1)),
    port,
  ) catch {
    _ => abort("first owner admission must succeed")
  }
  let (owner, second) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(2)),
    port,
  ) catch {
    _ => abort("second owner admission must succeed")
  }
  let first_task = match first {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("first request must invoke")
  }
  let second_task = match second {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("second request must invoke")
  }
  @async.with_task_group(group => {
    let first_handle = runtime_owner_spawn(group, first_task, port)
    let second_handle = runtime_owner_spawn(group, second_task, port)
    ignore(started.get())
    ignore(started.get())
    second_gate.put(())
    let second_event = second_handle.wait()
    let owner = match
      runtime_owner_complete_request(owner, second_event, port) {
      RuntimeOwnerCompletionApplied(owner~, completion~) => {
        match completion.response {
          HandlerSuccess(Number(_, repr~)) => assert_eq(repr, Some("2"))
          _ => fail("request completion must contain one success response")
        }
        assert_eq(completion.effects.length(), 0)
        owner
      }
      RuntimeOwnerCompletionIgnored(reason=_) =>
        abort("second completion must apply")
    }
    first_gate.put(())
    let first_event = first_handle.wait()
    let owner = match runtime_owner_complete_request(owner, first_event, port) {
      RuntimeOwnerCompletionApplied(owner~, completion~) => {
        match completion.response {
          HandlerSuccess(Number(_, repr~)) => assert_eq(repr, Some("1"))
          _ => fail("request completion must contain one success response")
        }
        assert_eq(completion.effects.length(), 0)
        owner
      }
      RuntimeOwnerCompletionIgnored(reason=_) =>
        abort("first completion must apply")
    }
    assert_eq(owner.task_count(), 0)
    assert_eq(owner.state().completed, [2, 1])
  })
}

///|
test "runtime owner rejects a mismatched completion without consuming task" {
  let port = runtime_owner_test_port()
  let owner = runtime_owner_new(port)
  let (owner, action) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(3)),
    port,
  ) catch {
    _ => abort("owner admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("owner request must invoke")
  }
  let result = runtime_owner_complete_request(
    owner,
    RuntimeOwnerRequestCompleted(
      token=task.task_token(),
      id=String("wrong"),
      completion=3,
    ),
    port,
  )
  match result {
    RuntimeOwnerCompletionIgnored(
      reason=RequestIdMismatch(expected=Number(3), actual=String("wrong"))
    ) => assert_eq(owner.task_count(), 1)
    _ => fail("mismatched owner completion must be ignored")
  }
}

///|
test "runtime owner cancellation completes and releases reservation" {
  let port = runtime_owner_test_port()
  let owner = runtime_owner_new(port)
  let (owner, _) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(4)),
    port,
  ) catch {
    _ => abort("owner admission must succeed")
  }
  let (owner, task, event) = match
    runtime_owner_cancel_request(owner, Number(4), port) {
    RuntimeOwnerCancelRequested(owner~, task~, event~) => (owner, task, event)
    RuntimeOwnerCancelIgnored(reason=_) =>
      abort("owner cancellation must apply")
  }
  assert_true(task.cancel_requested())
  let owner = match runtime_owner_complete_request(owner, event, port) {
    RuntimeOwnerCompletionApplied(owner~, completion~) => {
      match completion.response {
        HandlerSuccess(Number(_, repr~)) => assert_eq(repr, Some("-1"))
        _ => fail("cancel completion must contain one response")
      }
      assert_eq(completion.effects.length(), 0)
      owner
    }
    RuntimeOwnerCompletionIgnored(reason=_) =>
      abort("cancel completion must apply")
  }
  assert_eq(owner.task_count(), 0)
  assert_eq(owner.state().cancelled, [Number(4)])
  match runtime_owner_cancel_request(owner, Number(4), port) {
    RuntimeOwnerCancelIgnored(reason=UnknownRequest(id=Number(4))) => ()
    _ => fail("released cancellation must not remain pending")
  }
}

///|
test "runtime owner close aborts pending work once and ignores late events" {
  let port = runtime_owner_test_port()
  let owner = runtime_owner_new(port)
  let (owner, first) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(5)),
    port,
  ) catch {
    _ => abort("first owner admission must succeed")
  }
  let (owner, second) = runtime_owner_admit_notification(
    owner,
    runtime_owner_test_notification(),
    port,
  ) catch {
    _ => abort("notification admission must succeed")
  }
  let first_task = match first {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("first request must invoke")
  }
  let second_task = match second {
    RuntimeOwnerNotificationInvoke(task~) => task
    _ => abort("notification must invoke")
  }
  let closed = runtime_owner_close(owner, port)
  let (closed_owner, aborted) = match closed {
    RuntimeOwnerClosed(owner~, aborted~) => (owner, aborted)
    RuntimeOwnerAlreadyClosed(_) => abort("owner must close once")
  }
  assert_true(closed_owner.is_closed())
  assert_eq(aborted.length(), 2)
  assert_eq(closed_owner.state().aborted, [
    first_task.task_token(),
    second_task.task_token(),
  ])
  match
    runtime_owner_complete_request(
      closed_owner,
      RuntimeOwnerRequestCompleted(
        token=first_task.task_token(),
        id=Number(5),
        completion=5,
      ),
      port,
    ) {
    RuntimeOwnerCompletionIgnored(reason=Closed) => ()
    _ => fail("late completion after close must be ignored")
  }
  match runtime_owner_close(closed_owner, port) {
    RuntimeOwnerAlreadyClosed(_) => ()
    RuntimeOwnerClosed(..) => fail("close must abort once")
  }
}

///|
async test "runtime owner notification overlap has no response or request id" {
  let started : @aqueue.Queue[Int] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..runtime_owner_test_port(),
    execute: async fn(value) {
      started.put(value)
      gate.get()
      value
    },
  }
  let owner = runtime_owner_new(port)
  let (owner, action) = runtime_owner_admit_notification(
    owner,
    runtime_owner_test_notification(),
    port,
  ) catch {
    _ => abort("notification admission must succeed")
  }
  let task = match action {
    RuntimeOwnerNotificationInvoke(task~) => task
    _ => abort("notification must invoke")
  }
  assert_true(task.is_notification())
  assert_eq(task.request_id(), None)
  @async.with_task_group(group => {
    let handle = runtime_owner_spawn(group, task, port)
    ignore(started.get())
    gate.put(())
    let event = handle.wait()
    let owner = match runtime_owner_complete_notification(owner, event, port) {
      RuntimeOwnerCompletionApplied(owner~, completion~) => {
        assert_eq(completion.effects.length(), 0)
        owner
      }
      RuntimeOwnerCompletionIgnored(reason=_) =>
        abort("notification completion must apply")
    }
    assert_eq(owner.task_count(), 0)
    assert_eq(owner.state().notifications, [7])
  })
}

///|
test "runtime owner applies handler failure as typed completion" {
  let port = runtime_owner_test_port()
  let owner = runtime_owner_new(port)
  let (owner, action) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(6)),
    port,
  ) catch {
    _ => abort("owner admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("owner request must invoke")
  }
  let owner = match
    runtime_owner_complete_request(
      owner,
      RuntimeOwnerRequestCompleted(
        token=task.task_token(),
        id=Number(6),
        completion=-99,
      ),
      port,
    ) {
    RuntimeOwnerCompletionApplied(owner~, completion~) => {
      match completion.response {
        HandlerSuccess(Number(_, repr~)) => assert_eq(repr, Some("-99"))
        _ => fail("failure completion must contain one response")
      }
      assert_eq(completion.effects.length(), 0)
      owner
    }
    RuntimeOwnerCompletionIgnored(reason=_) =>
      abort("handler failure completion must apply")
  }
  assert_eq(owner.state().completed, [-99])
  assert_eq(owner.task_count(), 0)
}

///|
test "runtime owner rejects admission after close" {
  let port = runtime_owner_test_port()
  let owner = runtime_owner_new(port)
  let owner = match runtime_owner_close(owner, port) {
    RuntimeOwnerClosed(owner~, ..) => owner
    RuntimeOwnerAlreadyClosed(_) => abort("initial owner must be open")
  }
  try
    runtime_owner_admit_request(
      owner,
      runtime_owner_test_request(Number(7)),
      port,
    )
  catch {
    Closed => ()
  } noraise {
    _ => fail("closed owner admission must raise")
  }
}

///|
test "runtime owner immediate admission stays on owner loop" {
  let port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..runtime_owner_test_port(),
    admit_request: (state, id, _) => {
      RuntimeOwnerRequestImmediate(completion={
        state: {
          ..state,
          admitted: runtime_owner_test_push_id(state.admitted, id),
        },
        response: HandlerSuccess(Json::string("immediate-result")),
        effects: [
          WireNotification(notification=runtime_owner_test_notification()),
          Local(effect=()),
        ],
      })
    },
    execute: fn(_) { abort("immediate request admission must not execute") },
    complete_request: (_, _, _, _) => {
      abort("immediate request admission must not complete asynchronously")
    },
  }
  let owner = runtime_owner_new(port)
  let (owner, action) = runtime_owner_admit_request(
    owner,
    runtime_owner_test_request(Number(8)),
    port,
  ) catch {
    _ => abort("immediate owner admission must succeed")
  }
  match action {
    RuntimeOwnerImmediate(completion~) => {
      assert_eq(completion.state, owner.state())
      assert_eq(owner.state().admitted, [Number(8)])
      match completion.response {
        HandlerSuccess(String(value)) => assert_eq(value, "immediate-result")
        _ => fail("immediate admission must return a success response")
      }
      assert_eq(completion.effects.length(), 2)
      match completion.effects[0] {
        WireNotification(notification~) =>
          assert_eq(notification, runtime_owner_test_notification())
        _ => fail("immediate request wire effect must be preserved")
      }
      match completion.effects[1] {
        Local(effect=_) => ()
        _ => fail("immediate request local effect must be preserved")
      }
    }
    _ => fail("immediate admission must not create a task")
  }
  assert_eq(owner.task_count(), 0)
  assert_eq(owner.state().completed, [])
}

///|
test "runtime owner immediate notification commits effects without response" {
  let port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, String] = {
    ..runtime_owner_effect_test_port(),
    admit_notification: (state, _) => {
      RuntimeOwnerNotificationImmediate(completion={
        state: {
          ..state,
          notifications: runtime_owner_test_push_int(state.notifications, 99),
        },
        effects: [
          WireNotification(notification=runtime_owner_test_notification()),
          Local(effect="immediate-notification"),
        ],
      })
    },
    execute: fn(_) {
      abort("immediate notification admission must not execute")
    },
    complete_notification: (_, _, _) => {
      abort("immediate notification admission must not complete asynchronously")
    },
  }
  let owner = runtime_owner_new(port)
  let (owner, action) = runtime_owner_admit_notification(
    owner,
    runtime_owner_test_notification(),
    port,
  ) catch {
    _ => abort("immediate notification admission must succeed")
  }
  match action {
    RuntimeOwnerNotificationImmediate(completion~) => {
      assert_eq(completion.state, owner.state())
      assert_eq(owner.state().notifications, [99])
      assert_eq(completion.effects.length(), 2)
      match completion.effects[0] {
        WireNotification(notification~) =>
          assert_eq(notification, runtime_owner_test_notification())
        _ => fail("immediate notification wire effect must be preserved")
      }
      match completion.effects[1] {
        Local(effect~) => assert_eq(effect, "immediate-notification")
        _ => fail("immediate notification local effect must be preserved")
      }
    }
    _ => fail("immediate notification must not create a task")
  }
  assert_eq(owner.task_count(), 0)
}

///|
async test "runtime dispatch threads updated context across events" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  @async.with_task_group(group => {
    let dispatch : RuntimeDispatchPort[_, Int] = {
      request: (group, token, request, context) => {
        let task = group.spawn(() => ())
        RuntimeDispatchSpawned(
          context=context + 1,
          task={
            task_token: token,
            request_id: Some(request.id),
            cancel: () => task.cancel(),
          },
          next_task_token=token + 1,
        )
      },
      notification: (group, token, _, context) => {
        let task = group.spawn(() => ())
        RuntimeDispatchSpawned(
          context=context + 10,
          task={
            task_token: token,
            request_id: None,
            cancel: () => task.cancel(),
          },
          next_task_token=token + 1,
        )
      },
      cancel_inbound: (context, id, tasks) => {
        runtime_cancel_task(tasks, id)
        RuntimeDispatchCancelApplied(context~)
      },
      close_owner: (context, _) => context,
    }
    let (first, first_context) = runtime_apply_event_of(
      RuntimeChunk(
        @utf8.encode(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"one\"}\n" +
          "{\"jsonrpc\":\"2.0\",\"method\":\"two\"}\n",
        ),
      ),
      connection_state(),
      framing_state(max_frame_bytes=256),
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      runtime_identity_handler_result,
      dispatch,
      runtime_owner_event_unavailable,
      0,
      [],
      0,
      shutdown,
      Ref(runtime_outbound_registry()),
    )
    assert_eq(first_context, 11)
    assert_eq(first.tasks.length(), 2)
    assert_eq(first.tasks[0].task_token, 0)
    assert_eq(first.tasks[1].task_token, 1)
    assert_eq(first.next_task_token, 2)
  })
}

///|
async test "runtime applies immediate request completion before owner commands" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: _ => (),
  }
  let request = runtime_wbtest_request(Number(41))
  let step = connection_reduce(connection_state(), IncomingRequest(request)) catch {
    _ => abort("immediate request fixture must reduce")
  }
  @async.with_task_group(group => {
    let dispatch : RuntimeDispatchPort[_, Int] = {
      request: (_group, _token, request, context) => {
        RuntimeDispatchRequestImmediate(
          context=context + 1,
          event=IncomingCompleted(
            id=request.id,
            result=Json::string("immediate-result"),
          ),
          commands=[
            RuntimeOwnerWriteNotification(
              notification=runtime_owner_test_notification(),
            ),
          ],
        )
      },
      notification: (_group, _token, _notification, context) => {
        RuntimeDispatchNotificationImmediate(context~, commands=[])
      },
      cancel_inbound: (context, id, tasks) => {
        runtime_cancel_task(tasks, id)
        RuntimeDispatchCancelApplied(context~)
      },
      close_owner: (context, _) => context,
    }
    let state_ref = Ref::Ref(step.state)
    let (tasks, token, context, control) = runtime_apply_step(
      group,
      step,
      state_ref,
      writer_queue,
      runtime_test_options(),
      ports,
      dispatch,
      0,
      [],
      0,
      Ref(runtime_outbound_registry()),
    )
    assert_eq(context, 1)
    assert_eq(tasks.length(), 0)
    assert_eq(token, 0)
    match control {
      RuntimeApplyContinue => ()
      RuntimeApplyOwnerClose(_) => fail("immediate request must continue")
    }
    match writer_queue.get() {
      RuntimeFrame(frame) =>
        match jsonrpc_decode(@utf8.decode(frame.view())) {
          Response(Success(response)) => {
            assert_eq(response.id, Number(41))
            assert_eq(response.result, Json::string("immediate-result"))
          }
          _ => fail("immediate request must queue its response first")
        }
      RuntimeStop => fail("immediate request must not stop writer")
    }
    match writer_queue.get() {
      RuntimeFrame(frame) =>
        match jsonrpc_decode(@utf8.decode(frame.view())) {
          Notification(notification) =>
            assert_eq(notification, runtime_owner_test_notification())
          _ => fail("owner notification must follow immediate response")
        }
      RuntimeStop => fail("owner notification must remain queued")
    }
  })
}

///|
async test "runtime engine returns generic dispatch state after close" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let cancellations : Array[Unit] = []
  let closes : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get(), },
    writer: { write: frame => output.push(frame), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => if event.phase == "reducer_trace" { closes.push(()) },
  }
  input.put(
    Some(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"one\"}\n" +
        "{\"jsonrpc\":\"2.0\",\"method\":\"two\"}\n",
      ),
    ),
  )
  input.put(None)
  let context = @async.with_task_group(group => {
    runtime_connection_engine_with_dispatch(
      group,
      ports,
      runtime_test_options(),
      (_events, _shutdown) => {
        let dispatch : RuntimeDispatchPort[_, Int] = {
          request: (_group, token, request, context) => {
            RuntimeDispatchSpawned(
              context=context + 1,
              task={
                task_token: token,
                request_id: Some(request.id),
                cancel: () => cancellations.push(()),
              },
              next_task_token=token + 1,
            )
          },
          notification: (_group, token, _notification, context) => {
            RuntimeDispatchSpawned(
              context=context + 10,
              task={
                task_token: token,
                request_id: None,
                cancel: () => cancellations.push(()),
              },
              next_task_token=token + 1,
            )
          },
          cancel_inbound: (context, id, tasks) => {
            runtime_cancel_task(tasks, id)
            RuntimeDispatchCancelApplied(context~)
          },
          close_owner: (context, _) => context,
        }
        (dispatch, 0)
      },
    )
  })
  assert_eq(context, 11)
  assert_eq(cancellations.length(), 2)
  assert_eq(closes.length(), 1)
  assert_eq(output.length(), 1)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(failure)) => assert_eq(failure.error.code, InternalError)
    _ => fail("expected close to flush the pending request failure")
  }
}

///|
/// Shared no-I/O ports fixture for whitebox seams that only need tracing.
fn runtime_wbtest_trace_ports(
  traces : Array[RuntimeTraceEvent],
) -> RuntimePorts {
  {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
}

///|
/// Build the real owner dispatch context around one admitted owner.
fn runtime_wbtest_owner_context(
  owner : RuntimeOwner[RuntimeOwnerTestState, Int],
  port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit],
  events : @aqueue.Queue[RuntimeEventOf[Int]],
  shutdown : Ref[Bool],
) -> RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit] {
  {
    owner,
    port,
    events,
    shutdown,
    limit: runtime_test_options().queue_capacity,
  }
}

///|
/// Recording owner port: typed completions, typed cancel admissions, and
/// close aborts are also pushed into caller-owned arrays so engine-internal
/// owner state stays observable without escaping the loop.
fn runtime_owner_recording_port(
  completed : Array[Int],
  cancelled : Array[RequestId],
  aborted : Array[Int],
) -> RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] {
  {
    ..runtime_owner_test_port(),
    complete_request: (state, _, _, completion) => {
      completed.push(completion)
      {
        state: {
          ..state,
          completed: runtime_owner_test_push_int(state.completed, completion),
        },
        response: HandlerSuccess(
          Json::number(completion.to_double(), repr=completion.to_string()),
        ),
        effects: [],
      }
    },
    cancel_request: (state, id, _) => {
      cancelled.push(id)
      (
        { ..state, cancelled: runtime_owner_test_push_id(state.cancelled, id), },
        -1,
      )
    },
    abort: (state, task) => {
      aborted.push(task.task_token())
      state
    },
  }
}

///|
async test "runtime owner inbound cancel releases one task and keeps its sibling" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let started : @aqueue.Queue[Int] = Queue(kind=Unbounded)
  let release_one : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let release_two : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let start_order : Array[Int] = []
  let completed : Array[Int] = []
  let cancelled : Array[RequestId] = []
  let aborted : Array[Int] = []
  let owner_port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..runtime_owner_recording_port(completed, cancelled, aborted),
    execute: value => {
      started.put(value)
      if value == 1 {
        release_one.get()
      } else {
        release_two.get()
      }
      value
    },
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  let cancel_frame = "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n"
  input.put(
    Some(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"owner\"}\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"owner\"}\n",
      ),
    ),
  )
  @async.with_task_group(group => {
    let feeder = group.spawn(() => {
      start_order.push(started.get())
      start_order.push(started.get())
      input.put(Some(@utf8.encode(cancel_frame)))
      written.get()
      release_two.put(())
      written.get()
      input.put(None)
    })
    connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
    feeder.wait()
  })
  assert_eq(start_order, [1, 2])
  assert_eq(cancelled, [Number(1)])
  assert_eq(completed, [-1, 2])
  assert_eq(aborted, [])
  assert_eq(output.length(), 2)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(failure)) => {
      assert_eq(failure.id, Number(1))
      assert_eq(failure.error.code, RequestCancelled)
    }
    _ =>
      fail("cancelled request must settle with one RequestCancelled response")
  }
  match jsonrpc_decode(@utf8.decode(output[1].view())) {
    Response(Success(response)) => {
      assert_eq(response.id, Number(2))
      match response.result {
        Number(value, repr~) => {
          assert_eq(value, 2.0)
          // The core parser keeps `repr` only for literals a Double cannot
          // represent losslessly, so the decoded integer result carries none.
          assert_eq(repr, None)
        }
        _ => fail("sibling request must complete with its own typed result")
      }
    }
    _ => fail("sibling request must complete exactly once after the cancel")
  }
  let cancel_traces = traces.filter(event => {
    event.direction == "inbound" && event.phase == "cancel_requested"
  })
  assert_eq(cancel_traces.length(), 1)
  assert_eq(cancel_traces[0].request_id, "1")
  assert_eq(cancel_traces[0].error_kind, "cancel")
  assert_eq(
    traces.filter(event => event.phase == "owner_cancel_ignored").length(),
    0,
  )
  assert_eq(
    traces.filter(event => event.phase == "task_cancelled_on_close").length(),
    0,
  )
}

///|
async test "runtime owner dispatch cancel applies exactly one typed cancel event" {
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[Int] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let owner_port = runtime_owner_test_port()
  let (owner, action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    runtime_owner_test_request(Number(1)),
    owner_port,
  ) catch {
    _ => abort("dispatch cancel admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("dispatch cancel request must invoke")
  }
  let context = runtime_wbtest_owner_context(
    owner, owner_port, events, shutdown,
  )
  // Only `cancel_inbound` is exercised here, so the task-group parameter is
  // pinned explicitly instead of leaking an unresolved type variable.
  let dispatch : RuntimeDispatchPort[
    Unit,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()
  let controls : Array[RuntimeTaskControl] = [
    {
      task_token: task.task_token(),
      request_id: Some(Number(1)),
      cancel: () => cancelled.push(task.task_token()),
    },
    {
      task_token: task.task_token() + 5,
      request_id: Some(Number(9)),
      cancel: () => cancelled.push(task.task_token() + 5),
    },
  ]
  let next_context = runtime_apply_inbound_cancel(
    Number(1),
    ports,
    controls,
    context,
    dispatch.cancel_inbound,
  )
  assert_eq(cancelled, [task.task_token()])
  assert_eq(traces.length(), 1)
  assert_eq(traces[0].direction, "inbound")
  assert_eq(traces[0].phase, "cancel_requested")
  assert_eq(traces[0].request_id, "1")
  assert_eq(traces[0].error_kind, "cancel")
  assert_eq(next_context.owner.state().cancelled, [Number(1)])
  assert_eq(next_context.owner.task_count(), 1)
  match events.get() {
    RuntimeOwnerTaskEvent(
      RuntimeOwnerTaskCompleted(
        event=RuntimeOwnerRequestCompleted(
          token=actual_token,
          id=Number(1),
          completion=-1
        )
      )
    ) => assert_eq(actual_token, task.task_token())
    _ => fail("typed cancel must publish exactly one typed completion event")
  }
  let leftover = events.try_get() catch { _ => None }
  match leftover {
    None => ()
    Some(_) => fail("typed cancel must not publish a second event")
  }
}

///|
async test "runtime owner dispatch cancel fails fast on unknown or settled ids" {
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[Int] = []
  let cancelled_ids : Array[RequestId] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let owner_port = runtime_owner_recording_port([], cancelled_ids, [])
  // Only `cancel_inbound` is exercised here, so the task-group parameter is
  // pinned explicitly instead of leaking an unresolved type variable.
  let dispatch : RuntimeDispatchPort[
    Unit,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()

  // Unknown id: no runtime task control carries the request id, so the
  // dispatch port fails before any owner state changes.
  let (unknown_owner, _) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    runtime_owner_test_request(Number(31)),
    owner_port,
  ) catch {
    _ => abort("unknown cancel admission must succeed")
  }
  let unknown_context = runtime_wbtest_owner_context(
    unknown_owner, owner_port, events, shutdown,
  )
  let mut native_missing = false
  try
    ignore(
      runtime_apply_inbound_cancel(
        Number(31),
        ports,
        [],
        unknown_context,
        dispatch.cancel_inbound,
      ),
    )
  catch {
    TaskControlMissing => native_missing = true
    _ => fail("cancel without a task control must raise TaskControlMissing")
  } noraise {
    _ => fail("cancel without a task control must raise")
  }
  assert_true(native_missing)
  assert_eq(traces.length(), 0)
  assert_eq(cancelled.length(), 0)
  assert_eq(cancelled_ids.length(), 0)
  assert_eq(unknown_context.owner.task_count(), 1)

  // Already-completed id: the owner released its task, but a stale control
  // still matches; the ignored owner cancel must fail fast and cancel nobody.
  let (settled_owner, settled_action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    runtime_owner_test_request(Number(32)),
    owner_port,
  ) catch {
    _ => abort("settled cancel admission must succeed")
  }
  let settled_task = match settled_action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("settled cancel request must invoke")
  }
  let settled_owner = match
    runtime_owner_complete_request(
      settled_owner,
      RuntimeOwnerRequestCompleted(
        token=settled_task.task_token(),
        id=Number(32),
        completion=1,
      ),
      owner_port,
    ) {
    RuntimeOwnerCompletionApplied(owner~, ..) => owner
    RuntimeOwnerCompletionIgnored(reason=_) =>
      abort("settled cancel fixture completion must apply")
  }
  assert_eq(settled_owner.task_count(), 0)
  let settled_context = runtime_wbtest_owner_context(
    settled_owner, owner_port, events, shutdown,
  )
  let mut settled_missing = false
  try
    ignore(
      runtime_apply_inbound_cancel(
        Number(32),
        ports,
        [
          {
            task_token: settled_task.task_token(),
            request_id: Some(Number(32)),
            cancel: () => cancelled.push(settled_task.task_token()),
          },
          {
            task_token: 90,
            request_id: Some(Number(90)),
            cancel: () => cancelled.push(90),
          },
        ],
        settled_context,
        dispatch.cancel_inbound,
      ),
    )
  catch {
    TaskControlMissing => settled_missing = true
    _ => fail("settled cancel must raise TaskControlMissing")
  } noraise {
    _ => fail("settled cancel must raise")
  }
  assert_true(settled_missing)
  assert_eq(cancelled.length(), 0)
  let ignored = traces.filter(event => event.phase == "owner_cancel_ignored")
  assert_eq(ignored.length(), 1)
  assert_eq(ignored[0].direction, "inbound")
  assert_eq(ignored[0].request_id, "32")
  assert_eq(ignored[0].method_name, "")
  assert_eq(ignored[0].error_kind, "unknown_request")

  // Already-cancelled id: the first cancel holds the reservation, so the
  // second owner cancel is ignored and fails fast without a second admission.
  let (repeat_owner, repeat_action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    runtime_owner_test_request(Number(33)),
    owner_port,
  ) catch {
    _ => abort("repeat cancel admission must succeed")
  }
  let repeat_task = match repeat_action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("repeat cancel request must invoke")
  }
  let repeat_owner = match
    runtime_owner_cancel_request(repeat_owner, Number(33), owner_port) {
    RuntimeOwnerCancelRequested(owner~, ..) => owner
    RuntimeOwnerCancelIgnored(reason=_) =>
      abort("repeat cancel fixture must apply once")
  }
  let repeat_context = runtime_wbtest_owner_context(
    repeat_owner, owner_port, events, shutdown,
  )
  let mut repeat_missing = false
  try
    ignore(
      runtime_apply_inbound_cancel(
        Number(33),
        ports,
        [
          {
            task_token: repeat_task.task_token(),
            request_id: Some(Number(33)),
            cancel: () => cancelled.push(repeat_task.task_token()),
          },
        ],
        repeat_context,
        dispatch.cancel_inbound,
      ),
    )
  catch {
    TaskControlMissing => repeat_missing = true
    _ => fail("already-cancelled request must raise TaskControlMissing")
  } noraise {
    _ => fail("already-cancelled request must raise")
  }
  assert_true(repeat_missing)
  assert_eq(cancelled.length(), 0)
  let ignored = traces.filter(event => event.phase == "owner_cancel_ignored")
  assert_eq(ignored.length(), 2)
  assert_eq(ignored[1].request_id, "33")
  assert_eq(ignored[1].error_kind, "already_cancelled")
  assert_eq(cancelled_ids, [Number(33)])
  assert_eq(repeat_context.owner.task_count(), 1)
  let leftover = events.try_get() catch { _ => None }
  match leftover {
    None => ()
    Some(_) => fail("failed owner cancels must not publish task events")
  }
}

///|
/// ACP v1 makes `$/cancel_request` best-effort, and real clients (Zed)
/// routinely send cancels that lose the race with an already-delivered
/// response. This tolerance proof pins the full-engine behavior for every
/// benign race — an unknown id before any traffic, a repeated cancel for
/// one still-live pending, and a settle-then-cancel after the response was
/// delivered — each traced with its precise reason while the connection
/// keeps serving requests. The genuinely live cancel in the middle keeps
/// today's exact semantics: one typed cancellation event, exactly one
/// RequestCancelled response, and an untouched sibling task. Genuine engine
/// invariant violations (a live reducer pending whose task control is
/// missing, or a diverged owner reservation) stay fail-fast and are proven
/// separately by the TaskControlMissing pins above.
async test "runtime owner tolerates benign wire cancels and keeps serving requests" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let started : @aqueue.Queue[Int] = Queue(kind=Unbounded)
  let release_one : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let release_two : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let owner_port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..runtime_owner_test_port(),
    execute: value => {
      started.put(value)
      if value == 1 {
        release_one.get()
      } else {
        release_two.get()
      }
      value
    },
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  // One chunk, so both request frames are admitted before any completion:
  // the unknown cancel is processed first, then both tasks park.
  input.put(
    Some(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":99}}\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"owner\"}\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"owner\"}\n",
      ),
    ),
  )
  @async.with_task_group(group => {
    let feeder = group.spawn(() => {
      let _ = started.get()
      let _ = started.get()
      // Both cancel frames share one chunk, so the second is reduced while
      // the first cancellation completion is still queued: the pending is
      // live and already marked, which is precisely the repeated-cancel
      // race. The live first cancel applies through the real engine seam.
      input.put(
        Some(
          @utf8.encode(
            "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n" +
            "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n",
          ),
        ),
      )
      written.get() // exactly one RequestCancelled response for request one
      // The settle-then-cancel race: the cancellation response above was
      // delivered, so this late cancel targets an already-settled id.
      input.put(
        Some(
          @utf8.encode(
            "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n",
          ),
        ),
      )
      release_two.put(())
      written.get() // the sibling still round-trips: the connection survived
      input.put(None)
    })
    connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
    feeder.wait()
  })
  // Exactly two responses: the typed cancellation for request one and the
  // normal success for request two. No close, no synthesized extra frame.
  assert_eq(output.length(), 2)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(failure)) => {
      assert_eq(failure.id, Number(1))
      assert_eq(failure.error.code, RequestCancelled)
    }
    _ => fail("live cancel must still produce exactly one cancellation error")
  }
  match jsonrpc_decode(@utf8.decode(output[1].view())) {
    Response(Success(response)) => {
      assert_eq(response.id, Number(2))
      assert_eq(response.result, Json::number(2.0, repr="2"))
    }
    _ => fail("request two must complete normally after every benign cancel")
  }
  // The live cancel still crossed the engine seam exactly once.
  let requested = traces.filter(event => event.phase == "cancel_requested")
  assert_eq(requested.length(), 1)
  assert_eq(requested[0].direction, "inbound")
  assert_eq(requested[0].request_id, "1")
  // Every benign race produced one exact traced no-op with its reason.
  let ignored = traces.filter(event => event.phase == "cancel_ignored")
  assert_eq(ignored.length(), 3)
  assert_eq(ignored[0].direction, "inbound")
  assert_eq(ignored[0].request_id, "99")
  assert_eq(ignored[0].method_name, "")
  assert_eq(ignored[0].error_kind, "unknown_request")
  assert_eq(ignored[1].request_id, "1")
  assert_eq(ignored[1].error_kind, "already_cancelled")
  assert_eq(ignored[2].request_id, "1")
  assert_eq(ignored[2].error_kind, "already_settled")
  // No failure path ever fired.
  assert_true(!traces.any(event => event.phase == "reducer_failed"))
  assert_true(!traces.any(event => event.phase == "command_failed"))
  assert_true(!traces.any(event => event.phase == "owner_cancel_ignored"))
}

///|
async test "runtime owner eof close stops admission and empties pending work" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[Int] = []
  let completed : Array[Int] = []
  let cancelled_ids : Array[RequestId] = []
  let aborted : Array[Int] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let owner_port = runtime_owner_recording_port(
    completed, cancelled_ids, aborted,
  )
  let request = runtime_owner_test_request(Number(1))
  let (owner, request_action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    request,
    owner_port,
  ) catch {
    _ => abort("close request admission must succeed")
  }
  let request_task = match request_action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("close request must invoke")
  }
  let (owner, notification_action) = runtime_owner_admit_notification(
    owner,
    runtime_owner_test_notification(),
    owner_port,
  ) catch {
    _ => abort("close notification admission must succeed")
  }
  let notification_task = match notification_action {
    RuntimeOwnerNotificationInvoke(task~) => task
    _ => abort("close notification must invoke")
  }
  let context = runtime_wbtest_owner_context(
    owner, owner_port, events, shutdown,
  )
  let dispatch : RuntimeDispatchPort[
    _,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let controls : Array[RuntimeTaskControl] = [
    {
      task_token: request_task.task_token(),
      request_id: Some(Number(1)),
      cancel: () => cancelled.push(request_task.task_token()),
    },
    {
      task_token: notification_task.task_token(),
      request_id: None,
      cancel: () => cancelled.push(notification_task.task_token()),
    },
  ]
  @async.with_task_group(group => {
    let (step, closed_context) = runtime_apply_event_of(
      RuntimeEof,
      state,
      framing_state(max_frame_bytes=256),
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      runtime_owner_handler_result_unavailable,
      dispatch,
      runtime_owner_apply_task_event,
      context,
      controls,
      2,
      shutdown,
      Ref(runtime_outbound_registry()),
    )
    assert_true(step.stop)
    assert_eq(step.tasks.length(), 0)
    assert_true(closed_context.owner.is_closed())
    assert_eq(closed_context.owner.task_count(), 0)
    let mut admission_stopped = false
    try
      ignore(
        (dispatch.request)(
          group,
          7,
          runtime_owner_test_request(Number(7)),
          closed_context,
        ),
      )
    catch {
      ReducerFailed => admission_stopped = true
      _ => fail("admission after close must fail fast")
    } noraise {
      _ => fail("admission after close must raise")
    }
    assert_true(admission_stopped)
    assert_eq(closed_context.owner.task_count(), 0)
  })
  assert_eq(aborted, [request_task.task_token(), notification_task.task_token()])
  assert_eq(cancelled, [
    request_task.task_token(),
    notification_task.task_token(),
  ])
  assert_eq(completed, [])
  assert_eq(cancelled_ids, [])
  assert_true(shutdown.val)
  match writer_queue.get() {
    RuntimeFrame(frame) =>
      match jsonrpc_decode(@utf8.decode(frame.view())) {
        Response(Error(failure)) => {
          assert_eq(failure.id, Number(1))
          assert_eq(failure.error.code, InternalError)
        }
        _ => fail("close must flush the pending request as one internal error")
      }
    RuntimeStop => fail("close must write the pending failure before stop")
  }
  match writer_queue.get() {
    RuntimeStop => ()
    RuntimeFrame(_) =>
      fail("close must stop the writer after the failure frame")
  }
  // The reducer close step empties connection pending: the flushed failure
  // frame above is the wire proof, and the settled close state is the state
  // proof that no inbound request stays pending after close.
  let settled = connection_reduce(state, Close(reason="eof")).state
  assert_eq(settled.inbound.length(), 0)
  assert_eq(settled.settled_inbound, [Number(1)])
  let close_cancels = traces.filter(event => {
    event.phase == "task_cancelled_on_close"
  })
  assert_eq(close_cancels.length(), 2)
  let failed_inbound = traces.filter(event => event.phase == "inbound_failed")
  assert_eq(failed_inbound.length(), 1)
  assert_eq(failed_inbound[0].request_id, "1")
  assert_eq(failed_inbound[0].error_kind, "close")
}

///|
async test "runtime owner task loop drops its completion after shutdown begins" {
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(true)
  let task : RuntimeOwnerTask[Int] = {
    task_token: 4,
    request_id: Some(Number(4)),
    invocation: 4,
    notification: false,
    cancel_requested: false,
  }
  @async.with_task_group(group => {
    let handle = group.spawn(() => {
      runtime_owner_task_loop(
        task,
        runtime_owner_test_port(),
        events,
        shutdown,
        8,
      )
    })
    handle.wait()
  })
  let queued = events.try_get() catch { _ => None }
  match queued {
    None => ()
    Some(_) =>
      fail("a completion after shutdown must not reach the event queue")
  }
}

///|
async test "runtime owner late completion after close is traced and ignored" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let owner_port = runtime_owner_test_port()
  let request = runtime_owner_test_request(Number(1))
  let (owner, action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    request,
    owner_port,
  ) catch {
    _ => abort("late completion admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("late completion request must invoke")
  }
  let context = runtime_wbtest_owner_context(
    owner, owner_port, events, shutdown,
  )
  let dispatch : RuntimeDispatchPort[
    _,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let late_event : RuntimeEventOf[Int] = RuntimeOwnerTaskEvent(
    RuntimeOwnerTaskCompleted(
      event=RuntimeOwnerRequestCompleted(
        token=task.task_token(),
        id=Number(1),
        completion=1,
      ),
    ),
  )
  @async.with_task_group(group => {
    let (closed_step, closed_context) = runtime_apply_event_of(
      RuntimeEof,
      state,
      framing_state(max_frame_bytes=256),
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      runtime_owner_handler_result_unavailable,
      dispatch,
      runtime_owner_apply_task_event,
      context,
      [
        {
          task_token: task.task_token(),
          request_id: Some(Number(1)),
          cancel: () => (),
        },
      ],
      1,
      shutdown,
      Ref(runtime_outbound_registry()),
    )
    assert_true(closed_step.stop)
    assert_true(closed_context.owner.is_closed())
    let (late_step, late_context) = runtime_apply_event_of(
      late_event,
      closed_step.state,
      closed_step.decoder,
      group,
      writer_queue,
      runtime_test_options(),
      ports,
      events,
      runtime_owner_handler_result_unavailable,
      dispatch,
      runtime_owner_apply_task_event,
      closed_context,
      closed_step.tasks,
      closed_step.next_task_token,
      shutdown,
      Ref(runtime_outbound_registry()),
    )
    assert_eq(late_step.state, closed_step.state)
    assert_eq(late_step.tasks.length(), 0)
    assert_true(!late_step.stop)
    assert_true(late_context.owner.is_closed())
    let late_traces = traces.filter(event => {
      event.phase == "late_owner_completion_ignored"
    })
    assert_eq(late_traces.length(), 1)
    assert_eq(late_traces[0].request_id, "1")
  })
  match writer_queue.get() {
    RuntimeFrame(_) => ()
    RuntimeStop => fail("close must flush its failure frame before stop")
  }
  match writer_queue.get() {
    RuntimeStop => ()
    RuntimeFrame(_) => fail("close must stop the writer once")
  }
  let leftover = writer_queue.try_get() catch { _ => None }
  match leftover {
    None => ()
    Some(_) => fail("late completion must not write a second response")
  }
}

///|
async test "runtime dispatch admission failure leaves no task or pending leak" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[Int] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let state = connection_reduce(
      connection_state(),
      IncomingRequest(runtime_wbtest_request(Number(21))),
    ).state
  let controls : Array[RuntimeTaskControl] = [
    {
      task_token: 0,
      request_id: Some(Number(21)),
      cancel: () => cancelled.push(0),
    },
  ]
  let dispatch : RuntimeDispatchPort[_, Unit] = {
    request: (_group, _token, _request, _context) => raise ReducerFailed,
    notification: (_group, _token, _notification, _context) => {
      raise ReducerFailed
    },
    cancel_inbound: (context, id, tasks) => {
      runtime_cancel_task(tasks, id)
      RuntimeDispatchCancelApplied(context~)
    },
    close_owner: (context, _) => context,
  }
  @async.with_task_group(group => {
    let mut admission_error = false
    try
      ignore(
        runtime_apply_event_of(
          RuntimeChunk(
            @utf8.encode(
              "{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"work\"}\n",
            ),
          ),
          state,
          framing_state(max_frame_bytes=256),
          group,
          writer_queue,
          runtime_test_options(),
          ports,
          events,
          runtime_identity_handler_result,
          dispatch,
          runtime_owner_event_unavailable,
          (),
          controls,
          1,
          shutdown,
          Ref(runtime_outbound_registry()),
        ),
      )
    catch {
      @runtime.RuntimeError::ReducerFailed => admission_error = true
      _ => fail("admission failure must surface its runtime error")
    } noraise {
      _ => fail("admission failure must raise")
    }
    assert_true(admission_error)
  })
  assert_eq(cancelled, [0])
  assert_true(shutdown.val)
  let dispatch_failures = traces.filter(event => {
    event.phase == "dispatch_failed"
  })
  assert_eq(dispatch_failures.length(), 1)
  assert_eq(dispatch_failures[0].error_kind, "reducer_failed")
  // Close flushes pending inbound failures in admission order; the decoded
  // failure ids are typed wire ids, not raw JSON values.
  let expected_ids : Array[@jsonrpc.JsonRpcId] = [Number(21), Number(22)]
  for expected in expected_ids {
    match writer_queue.get() {
      RuntimeFrame(frame) =>
        match jsonrpc_decode(@utf8.decode(frame.view())) {
          Response(Error(failure)) => {
            assert_eq(failure.error.code, InternalError)
            assert_eq(failure.id, expected)
          }
          _ => fail("admission failure must fail every pending request once")
        }
      RuntimeStop => fail("admission failure must flush failures before stop")
    }
  }
  match writer_queue.get() {
    RuntimeStop => ()
    RuntimeFrame(_) => fail("admission failure must stop the writer last")
  }
}

///|
async test "runtime typed cancel failure settles its pending without leaks" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[Int] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let request = runtime_wbtest_request(Number(1))
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  // The pending request is reducer-admitted, but its runtime task control is
  // gone, so the typed cancel seam must fail fast instead of settling quietly.
  let dispatch : RuntimeDispatchPort[_, Unit] = {
    request: (_group, _token, _request, _context) => raise ReducerFailed,
    notification: (_group, _token, _notification, _context) => {
      raise ReducerFailed
    },
    cancel_inbound: (context, id, tasks) => {
      runtime_cancel_task(tasks, id)
      RuntimeDispatchCancelApplied(context~)
    },
    close_owner: (context, _) => context,
  }
  @async.with_task_group(group => {
    let mut cancel_error = false
    try
      ignore(
        runtime_apply_event_of(
          RuntimeChunk(
            @utf8.encode(
              "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":1}}\n",
            ),
          ),
          state,
          framing_state(max_frame_bytes=256),
          group,
          writer_queue,
          runtime_test_options(),
          ports,
          events,
          runtime_identity_handler_result,
          dispatch,
          runtime_owner_event_unavailable,
          (),
          [],
          1,
          shutdown,
          Ref(runtime_outbound_registry()),
        ),
      )
    catch {
      @runtime.RuntimeError::TaskControlMissing => cancel_error = true
      _ => fail("cancel failure must surface its runtime error")
    } noraise {
      _ => fail("cancel failure must raise")
    }
    assert_true(cancel_error)
  })
  assert_eq(cancelled, [])
  assert_true(shutdown.val)
  let command_failures = traces.filter(event => event.phase == "command_failed")
  assert_eq(command_failures.length(), 1)
  assert_eq(command_failures[0].error_kind, "task_control_missing")
  match writer_queue.get() {
    RuntimeFrame(frame) =>
      match jsonrpc_decode(@utf8.decode(frame.view())) {
        Response(Error(failure)) => {
          assert_eq(failure.id, Number(1))
          assert_eq(failure.error.code, InternalError)
        }
        _ => fail("cancel failure must settle the pending request once")
      }
    RuntimeStop =>
      fail("cancel failure must flush the settle frame before stop")
  }
  match writer_queue.get() {
    RuntimeStop => ()
    RuntimeFrame(_) => fail("cancel failure must stop the writer last")
  }
  let settled = connection_reduce(state, Close(reason="protocol")).state
  assert_eq(settled.inbound.length(), 0)
  assert_eq(settled.settled_inbound, [Number(1)])
}

///|
async test "runtime owner handler failure cleans its task without leaking siblings" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let started : @aqueue.Queue[Int] = Queue(kind=Unbounded)
  let release_two : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let start_order : Array[Int] = []
  let completed : Array[Int] = []
  let cancelled : Array[RequestId] = []
  let aborted : Array[Int] = []
  let failure = JsonRpcError::internal_error()
  let owner_port : RuntimeOwnerPort[RuntimeOwnerTestState, Int, Int, Unit] = {
    ..runtime_owner_recording_port(completed, cancelled, aborted),
    execute: value => {
      started.put(value)
      if value == 1 {
        raise @jsonrpc.JsonRpcCodecError::ParseError(
          message="owner handler fault",
        )
      }
      release_two.get()
      value
    },
    complete_request: (state, _, _, completion) => {
      completed.push(completion)
      {
        state: {
          ..state,
          completed: runtime_owner_test_push_int(state.completed, completion),
        },
        response: if completion == -2 {
          HandlerError(failure)
        } else {
          HandlerSuccess(
            Json::number(completion.to_double(), repr=completion.to_string()),
          )
        },
        effects: [],
      }
    },
  }
  let ports = runtime_owner_run_runtime_ports(input, output, written, traces)
  input.put(
    Some(
      @utf8.encode(
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"owner\"}\n" +
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"owner\"}\n",
      ),
    ),
  )
  @async.with_task_group(group => {
    let feeder = group.spawn(() => {
      start_order.push(started.get())
      start_order.push(started.get())
      written.get()
      release_two.put(())
      written.get()
      input.put(None)
    })
    connection_runtime_run_owner(ports, runtime_test_options(), owner_port)
    feeder.wait()
  })
  assert_eq(start_order, [1, 2])
  assert_eq(completed, [-2, 2])
  assert_eq(cancelled, [])
  assert_eq(aborted, [])
  assert_eq(output.length(), 2)
  match jsonrpc_decode(@utf8.decode(output[0].view())) {
    Response(Error(response)) => {
      assert_eq(response.id, Number(1))
      assert_eq(response.error, failure)
    }
    _ => fail("failed handler must settle with one typed error response")
  }
  match jsonrpc_decode(@utf8.decode(output[1].view())) {
    Response(Success(response)) => {
      assert_eq(response.id, Number(2))
      match response.result {
        Number(value, repr~) => {
          assert_eq(value, 2.0)
          // The core parser keeps `repr` only for literals a Double cannot
          // represent losslessly, so the decoded integer result carries none.
          assert_eq(repr, None)
        }
        _ => fail("sibling request must complete with its own typed result")
      }
    }
    _ => fail("sibling request must complete exactly once after the failure")
  }
  assert_eq(
    traces.filter(event => event.phase == "task_cancelled_on_close").length(),
    0,
  )
}

///|
async test "runtime owner close cleanup failure still cancels tasks and settles pending" {
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Unbounded)
  writer_queue.close()
  let events : @aqueue.Queue[RuntimeEventOf[Int]] = Queue(kind=Unbounded)
  let shutdown = Ref::Ref(false)
  let traces : Array[RuntimeTraceEvent] = []
  let cancelled : Array[Int] = []
  let aborted : Array[Int] = []
  let ports = runtime_wbtest_trace_ports(traces)
  let owner_port = runtime_owner_recording_port([], [], aborted)
  let request = runtime_owner_test_request(Number(1))
  let (owner, action) = runtime_owner_admit_request(
    runtime_owner_new(owner_port),
    request,
    owner_port,
  ) catch {
    _ => abort("cleanup failure admission must succeed")
  }
  let task = match action {
    RuntimeOwnerInvoke(task~) => task
    _ => abort("cleanup failure request must invoke")
  }
  let context = runtime_wbtest_owner_context(
    owner, owner_port, events, shutdown,
  )
  let dispatch : RuntimeDispatchPort[
    _,
    RuntimeOwnerDispatchContext[RuntimeOwnerTestState, Int, Int, Unit],
  ] = runtime_owner_dispatch_port()
  let state = connection_reduce(connection_state(), IncomingRequest(request)).state
  let controls : Array[RuntimeTaskControl] = [
    {
      task_token: task.task_token(),
      request_id: Some(Number(1)),
      cancel: () => cancelled.push(task.task_token()),
    },
  ]
  @async.with_task_group(group => {
    let mut writer_error = false
    try
      ignore(
        runtime_apply_event_of(
          RuntimeEof,
          state,
          framing_state(max_frame_bytes=256),
          group,
          writer_queue,
          runtime_test_options(),
          ports,
          events,
          runtime_owner_handler_result_unavailable,
          dispatch,
          runtime_owner_apply_task_event,
          context,
          controls,
          1,
          shutdown,
          Ref(runtime_outbound_registry()),
        ),
      )
    catch {
      @runtime.RuntimeError::WriterQueueClosed => writer_error = true
      _ => fail("close cleanup failure must surface the writer error")
    } noraise {
      _ => fail("close cleanup failure must raise")
    }
    assert_true(writer_error)
  })
  assert_eq(aborted, [task.task_token()])
  assert_eq(cancelled, [task.task_token()])
  assert_true(shutdown.val)
  let unwritten = traces.filter(event => {
    event.phase == "inbound_failure_unwritten"
  })
  assert_eq(unwritten.length(), 1)
  assert_eq(unwritten[0].request_id, "1")
  assert_eq(unwritten[0].error_kind, "writer")
  let command_failures = traces.filter(event => event.phase == "command_failed")
  assert_eq(command_failures.length(), 1)
  assert_eq(command_failures[0].error_kind, "writer_queue_closed")
}

///|
/// Outbound-channel test ports: the response and outbound-failure callbacks
/// record typed ids so settle-once is observable without engine internals.
fn runtime_outbound_run_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[RuntimeTraceEvent],
  responses : Array[RequestId],
  failures : Array[(RequestId, RuntimeOutboundFailureKind)],
) -> RuntimePorts {
  {
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
      response: response => responses.push(connection_response_id(response)),
      outbound_failure: Some((id, failure) => {
        failures.push((id, failure.reason))
      }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
}

///|
/// Run the one owner engine with an outbound channel and hand the channel to
/// spawned submitters through an unbounded queue. The factory is
/// synchronous, so it enqueues with `try_put`; that call wakes any submitter
/// already parked on `get` point-to-point, making the handoff deterministic
/// without any task-scheduling assumption.
async fn runtime_outbound_run(
  ports : RuntimePorts,
  options : RuntimeOptions,
  captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]],
) -> Unit {
  connection_runtime_run_owner_with_outbound(ports, options, channel => {
    let _ = captured.try_put(channel) catch { _ => false }
    runtime_owner_run_immediate_port(HandlerSuccess(Json::null()), [], [])
  })
}

///|
async test "runtime outbound channel round-trips one request through the wire" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = runtime_outbound_run_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      runtime_outbound_run(ports, runtime_test_options(), captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      channel.submit_request(method_name="ask", params=Json::null())
    })
    written.get()
    input.put(
      Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"done\"}\n")),
    )
    input.put(None)
    let response = submitter.wait()
    runner.wait()
    match response {
      Success(success) => {
        assert_eq(success.id, Number(1))
        assert_eq(success.result, Json::string("done"))
      }
      Error(_) => fail("channel round-trip must deliver the success response")
    }
    assert_eq(output.length(), 1)
    match jsonrpc_decode(@utf8.decode(output[0].view())) {
      Request(request) => {
        assert_eq(request.id, Number(1))
        assert_eq(request.method_name, "ask")
      }
      _ => fail("channel must write exactly the submitted request frame")
    }
    assert_eq(responses, [Number(1)])
    assert_eq(failures.length(), 0)
  })
}

///|
async test "runtime outbound submission fails fast under writer backpressure" {
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(1))
  writer_queue.put(RuntimeFrame(@utf8.encode("occupied\n")))
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: response => responses.push(connection_response_id(response)),
      outbound_failure: Some((id, failure) => {
        failures.push((id, failure.reason))
      }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let reply : @aqueue.Queue[RuntimeOutboundReply] = Queue(kind=Unbounded)
  let options = { ..runtime_test_options(), queue_capacity: 1, }
  let mut backpressure_limit = 0
  @async.with_task_group(group => {
    // The drain task only runs after the offer already failed synchronously,
    // then frees the stop sentinel so the close path cannot park forever.
    let drain = group.spawn(() => {
      for ;; {
        let item = writer_queue.get() catch { _ => break }
        match item {
          RuntimeStop => break
          RuntimeFrame(_) => ()
        }
      }
    })
    try
      ignore(
        runtime_apply_event(
          RuntimeOutboundRequestSubmitted(
            method_name="ask",
            params=Json::null(),
            reply~,
          ),
          connection_state(),
          framing_state(max_frame_bytes=256),
          group,
          writer_queue,
          options,
          ports,
          events,
          [],
          0,
          shutdown,
        ),
      )
    catch {
      @runtime.RuntimeError::WriterQueueBackpressure(limit~) =>
        backpressure_limit = limit
      _ => fail("writer backpressure must surface the primary writer error")
    } noraise {
      _ => fail("writer backpressure must raise")
    }
    drain.wait()
  })
  assert_eq(backpressure_limit, 1)
  assert_true(shutdown.val)
  assert_eq(responses.length(), 0)
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].0, Number(1))
  assert_true(failures[0].1 is Writer)
  match reply.get() {
    RuntimeOutboundFailed(kind~) => assert_true(kind is Writer)
    RuntimeOutboundReplied(_) =>
      fail("backpressure must fail the parked submitter")
  }
  match (reply.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("backpressure must release the waiter exactly once")
  }
}

///|
async test "runtime outbound parked waiter settles once on eof close" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = runtime_outbound_run_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  // The parked submitter classifies its own failure inside its task, so an
  // expected submission failure never fails the shared task group.
  let submit_error : Array[String] = []
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      runtime_outbound_run(ports, runtime_test_options(), captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      try {
        ignore(channel.submit_request(method_name="ask", params=Json::null()))
        submit_error.push("none")
      } catch {
        @runtime.RuntimeError::ReaderFailed =>
          submit_error.push("reader_failed")
        _ => submit_error.push("unexpected")
      }
    })
    written.get()
    input.put(None)
    submitter.wait()
    runner.wait()
  })
  assert_eq(submit_error, ["reader_failed"])
  assert_eq(responses.length(), 0)
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].0, Number(1))
  assert_true(failures[0].1 is EndOfInput)
  let outbound_failed = traces.filter(event => event.phase == "outbound_failed")
  assert_eq(outbound_failed.length(), 1)
}

///|
async test "runtime outbound notification acks enqueue before flush" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = runtime_outbound_run_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      runtime_outbound_run(ports, runtime_test_options(), captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      channel.submit_notification(method_name="note", params=Json::null())
    })
    written.get()
    submitter.wait()
    input.put(None)
    runner.wait()
    assert_eq(output.length(), 1)
    match jsonrpc_decode(@utf8.decode(output[0].view())) {
      Notification(notification) => assert_eq(notification.method_name, "note")
      _ => fail("channel must write exactly the submitted notification frame")
    }
    assert_eq(responses.length(), 0)
    assert_eq(failures.length(), 0)
  })
}

///|
async test "runtime outbound notification fails with writer kind under backpressure" {
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let writer_queue : @aqueue.Queue[RuntimeWriterItem] = Queue(kind=Blocking(1))
  writer_queue.put(RuntimeFrame(@utf8.encode("occupied\n")))
  let events : @aqueue.Queue[RuntimeEvent] = Queue(kind=Unbounded)
  let ports : RuntimePorts = {
    reader: { read: _ => None, },
    writer: { write: _ => (), },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: response => responses.push(connection_response_id(response)),
      outbound_failure: Some((id, failure) => {
        failures.push((id, failure.reason))
      }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let shutdown = Ref::Ref(false)
  let ack : @aqueue.Queue[RuntimeOutboundAck] = Queue(kind=Unbounded)
  let options = { ..runtime_test_options(), queue_capacity: 1, }
  let mut backpressure_limit = 0
  @async.with_task_group(group => {
    let drain = group.spawn(() => {
      for ;; {
        let item = writer_queue.get() catch { _ => break }
        match item {
          RuntimeStop => break
          RuntimeFrame(_) => ()
        }
      }
    })
    try
      ignore(
        runtime_apply_event(
          RuntimeOutboundNotificationSubmitted(
            method_name="note",
            params=Json::null(),
            ack~,
          ),
          connection_state(),
          framing_state(max_frame_bytes=256),
          group,
          writer_queue,
          options,
          ports,
          events,
          [],
          0,
          shutdown,
        ),
      )
    catch {
      @runtime.RuntimeError::WriterQueueBackpressure(limit~) =>
        backpressure_limit = limit
      _ => fail("notification backpressure must surface the writer error")
    } noraise {
      _ => fail("notification backpressure must raise")
    }
    drain.wait()
  })
  assert_eq(backpressure_limit, 1)
  assert_true(shutdown.val)
  // A notification owns no reducer pending, so no outbound_failure may fire.
  assert_eq(failures.length(), 0)
  match ack.get() {
    RuntimeOutboundAckFailed(kind~) => assert_true(kind is Writer)
    RuntimeOutboundAcked => fail("notification backpressure must fail the ack")
  }
  match (ack.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("backpressure must release the ack exactly once")
  }
}

///|
async test "runtime outbound reverse replies reach each own waiter" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = runtime_outbound_run_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      runtime_outbound_run(ports, runtime_test_options(), captured)
    })
    let first = group.spawn(() => {
      let channel = captured.get()
      // Hand the same channel handle to the second submitter before
      // parking, so both waiters share the one engine-owned channel.
      let _ = captured.try_put(channel) catch { _ => false }
      channel.submit_request(method_name="one", params=Json::null())
    })
    written.get()
    let second = group.spawn(() => {
      let channel = captured.get()
      channel.submit_request(method_name="two", params=Json::null())
    })
    written.get()
    input.put(
      Some(
        @utf8.encode(
          "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":\"second\"}\n" +
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"first\"}\n",
        ),
      ),
    )
    input.put(None)
    let second_response = second.wait()
    let first_response = first.wait()
    runner.wait()
    match second_response {
      Success(success) => {
        assert_eq(success.id, Number(2))
        assert_eq(success.result, Json::string("second"))
      }
      Error(_) => fail("second waiter must receive its own response")
    }
    match first_response {
      Success(success) => {
        assert_eq(success.id, Number(1))
        assert_eq(success.result, Json::string("first"))
      }
      Error(_) => fail("first waiter must receive its own response")
    }
    assert_eq(output.length(), 2)
    match jsonrpc_decode(@utf8.decode(output[0].view())) {
      Request(request) => assert_eq(request.method_name, "one")
      _ => fail("first frame must be the first request")
    }
    match jsonrpc_decode(@utf8.decode(output[1].view())) {
      Request(request) => assert_eq(request.method_name, "two")
      _ => fail("second frame must be the second request")
    }
    // Replies are applied in wire order, so the reverse response for id 2
    // completes before the response for id 1.
    assert_eq(responses, [Number(2), Number(1)])
    assert_eq(failures.length(), 0)
  })
}

///|
async test "runtime outbound submit after shutdown fails immediately" {
  // Engine-level: after a graceful EOF close the captured channel must
  // reject both submission kinds without parking.
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = runtime_outbound_run_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  input.put(None)
  connection_runtime_run_owner_with_outbound(ports, runtime_test_options(), channel => {
    let _ = captured.try_put(channel) catch { _ => false }
    runtime_owner_run_immediate_port(HandlerSuccess(Json::null()), [], [])
  })
  let channel = captured.get()
  let mut request_rejected = false
  try
    ignore(channel.submit_request(method_name="ask", params=Json::null()))
  catch {
    @runtime.RuntimeError::EventQueueClosed => request_rejected = true
    _ =>
      fail(
        "post-close request submission must fail with the closed queue error",
      )
  } noraise {
    _ => fail("post-close request submission must raise")
  }
  assert_true(request_rejected)
  let mut notification_rejected = false
  try
    channel.submit_notification(method_name="note", params=Json::null())
  catch {
    @runtime.RuntimeError::EventQueueClosed => notification_rejected = true
    _ =>
      fail(
        "post-close notification submission must fail with the closed queue error",
      )
  } noraise {
    _ => fail("post-close notification submission must raise")
  }
  assert_true(notification_rejected)
  // Unit seam: a shutdown flag alone rejects before enqueueing.
  let events : @aqueue.Queue[RuntimeEventOf[Unit]] = Queue(kind=Blocking(1))
  let shutdown : Ref[Bool] = Ref(false)
  shutdown.val = true
  let guarded : RuntimeOutboundChannel[Unit] = { events, shutdown, limit: 1, }
  let mut local_rejected = false
  try
    ignore(guarded.submit_request(method_name="ask", params=Json::null()))
  catch {
    @runtime.RuntimeError::EventQueueClosed => local_rejected = true
    _ => fail("shutdown guard must fail with the closed queue error")
  } noraise {
    _ => fail("shutdown guard must raise")
  }
  assert_true(local_rejected)
  match (events.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("drain must leave the event queue empty")
  }
}

///|
async test "runtime outbound submit rejects a full event queue without parking" {
  let events : @aqueue.Queue[RuntimeEventOf[Unit]] = Queue(kind=Blocking(1))
  events.put(RuntimeEof)
  let shutdown : Ref[Bool] = Ref(false)
  let channel : RuntimeOutboundChannel[Unit] = { events, shutdown, limit: 1, }
  let mut observed_limit = 0
  try
    ignore(channel.submit_request(method_name="ask", params=Json::null()))
  catch {
    @runtime.RuntimeError::EventQueueBackpressure(limit~) =>
      observed_limit = limit
    _ => fail("full event queue must surface event queue backpressure")
  } noraise {
    _ => fail("full event queue must raise")
  }
  assert_eq(observed_limit, 1)
  // The rejected submission never entered the queue and never parked.
  match (events.try_get() catch { _ => None }) {
    Some(RuntimeEof) => ()
    _ => fail("backpressure must not enqueue the rejected submission")
  }
}

///|
async test "runtime outbound drain settles stranded submissions once" {
  let events : @aqueue.Queue[RuntimeEventOf[Unit]] = Queue(kind=Unbounded)
  let reply : @aqueue.Queue[RuntimeOutboundReply] = Queue(kind=Unbounded)
  let ack : @aqueue.Queue[RuntimeOutboundAck] = Queue(kind=Unbounded)
  events.put(
    RuntimeOutboundRequestSubmitted(
      method_name="ask",
      params=Json::null(),
      reply~,
    ),
  )
  events.put(RuntimeChunk(@utf8.encode("dead letter\n")))
  events.put(
    RuntimeOutboundNotificationSubmitted(
      method_name="note",
      params=Json::null(),
      ack~,
    ),
  )
  runtime_outbound_drain_stranded(events)
  match reply.get() {
    RuntimeOutboundFailed(kind~) => assert_true(kind is Runtime)
    RuntimeOutboundReplied(_) =>
      fail("stranded request must fail, not complete")
  }
  match ack.get() {
    RuntimeOutboundAckFailed(kind~) => assert_true(kind is Runtime)
    RuntimeOutboundAcked => fail("stranded notification must fail, not ack")
  }
  match (reply.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("backpressure must release the waiter exactly once")
  }
  match (ack.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("backpressure must release the ack exactly once")
  }
  match (events.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("drain must leave the event queue empty")
  }
}

///|
async test "runtime outbound sync notification reaches the wire without parking" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[RuntimeTraceEvent] = []
  let responses : Array[RequestId] = []
  let failures : Array[(RequestId, RuntimeOutboundFailureKind)] = []
  let ports = runtime_outbound_run_ports(
    input, output, written, traces, responses, failures,
  )
  let captured : @aqueue.Queue[RuntimeOutboundChannel[Unit]] = Queue(
    kind=Unbounded,
  )
  @async.with_task_group(group => {
    let runner = group.spawn(() => {
      runtime_outbound_run(ports, runtime_test_options(), captured)
    })
    let submitter = group.spawn(() => {
      let channel = captured.get()
      let notification = channel.submit_notification_sync(
        method_name="session/cancel",
        params=Json::null(),
      )
      // Hand the channel back before parking so the post-close check below
      // can reuse the exact engine-owned handle.
      let _ = captured.try_put(channel) catch { _ => false }
      // The loop must keep serving after the ack-less event: a parked
      // request round-trips through the same single engine.
      let response = channel.submit_request(
        method_name="ask",
        params=Json::null(),
      )
      (notification, response)
    })
    written.get()
    match jsonrpc_decode(@utf8.decode(output[0].view())) {
      Notification(notification) =>
        assert_eq(notification.method_name, "session/cancel")
      _ => fail("sync submission must write exactly the notification frame")
    }
    written.get()
    input.put(
      Some(@utf8.encode("{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"done\"}\n")),
    )
    let (notification, response) = submitter.wait()
    assert_true(notification is Ok(_))
    match response {
      Success(success) => assert_eq(success.result, Json::string("done"))
      Error(_) => fail("the loop must keep serving after a sync notification")
    }
    input.put(None)
    runner.wait()
    assert_eq(output.length(), 2)
    assert_eq(responses, [Number(1)])
    // The ack-less interpretation registers no waiter or pending: the close
    // sweep settles nothing for it and the engine ends clean at EOF.
    assert_eq(failures.length(), 0)
    // Engine-level guard: after the graceful EOF close the same channel
    // rejects a sync submission without enqueueing anything.
    let channel = captured.get()
    match
      channel.submit_notification_sync(
        method_name="session/cancel",
        params=Json::null(),
      ) {
      Err(EventQueueClosed) => ()
      _ => fail("post-close sync submission must fail with the closed error")
    }
  })
}

///|
async test "runtime outbound sync notification rejects a full event queue" {
  let events : @aqueue.Queue[RuntimeEventOf[Unit]] = Queue(kind=Blocking(1))
  events.put(RuntimeEof)
  let shutdown : Ref[Bool] = Ref(false)
  let channel : RuntimeOutboundChannel[Unit] = { events, shutdown, limit: 1, }
  match
    channel.submit_notification_sync(
      method_name="session/cancel",
      params=Json::null(),
    ) {
    Err(EventQueueBackpressure(limit~)) => assert_eq(limit, 1)
    _ => fail("a full event queue must surface typed backpressure")
  }
  // The rejected submission never entered the queue: the sentinel event is
  // still the one and only queued item, so the loop is unaffected.
  match (events.try_get() catch { _ => None }) {
    Some(RuntimeEof) => ()
    _ => fail("backpressure must not enqueue the rejected sync submission")
  }
  // With capacity available again, the same channel accepts the next sync
  // submission and queues exactly its fire-and-forget event.
  match
    channel.submit_notification_sync(
      method_name="session/cancel",
      params=Json::null(),
    ) {
    Ok(_) => ()
    _ => fail("the channel must accept a sync submission once capacity frees")
  }
  match (events.try_get() catch { _ => None }) {
    Some(RuntimeOutboundNotificationEnqueued(method_name~, ..)) =>
      assert_eq(method_name, "session/cancel")
    _ => fail("the accepted sync submission must be queued as its event")
  }
  match (events.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("the queue must hold exactly one accepted event")
  }
}

///|
async test "runtime outbound sync notification after shutdown fails closed" {
  let events : @aqueue.Queue[RuntimeEventOf[Unit]] = Queue(kind=Blocking(1))
  let shutdown : Ref[Bool] = Ref(false)
  shutdown.val = true
  let channel : RuntimeOutboundChannel[Unit] = { events, shutdown, limit: 1, }
  match
    channel.submit_notification_sync(
      method_name="session/cancel",
      params=Json::null(),
    ) {
    Err(EventQueueClosed) => ()
    _ => fail("post-shutdown sync submission must fail with the closed error")
  }
  match (events.try_get() catch { _ => None }) {
    None => ()
    Some(_) => fail("shutdown guard must not enqueue the sync submission")
  }
}
