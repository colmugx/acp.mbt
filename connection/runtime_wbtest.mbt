///|
using @runtime {runtime_default_options}

///|
fn runtime_test_options() -> RuntimeOptions {
  let options = runtime_default_options()
  { ..options, max_frame_bytes: 256 }
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
    event, state, decoder, group, writer_queue, options, ports, events, runtime_identity_handler_result,
    dispatch, runtime_owner_event_unavailable, dispatch_context, tasks, next_task_token,
    shutdown,
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
    reader: { read: _ => input.get() },
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
    reader: { read: _ => input.get() },
    writer: { write: frame => output.push(frame) },
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
    reader: { read: _ => input.get() },
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
    reader: { read: _ => input.get() },
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
    reader: { read: _ => malformed_input.get() },
    writer: { write: _ => () },
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
    reader: { read: _ => partial_input.get() },
    writer: { write: _ => () },
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
    writer: { write: _ => () },
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
    reader: { read: _ => input.get() },
    writer: { write: _ => () },
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
    reader: { read: _ => writer_input.get() },
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
    reader: { read: _ => input.get() },
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
    { task_token: 11, request_id: None, cancel: () => () },
    { task_token: 22, request_id: None, cancel: () => () },
    { task_token: 33, request_id: None, cancel: () => () },
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
    { task_token: 1, request_id: None, cancel: () => cancelled.push(1) },
    { task_token: 2, request_id: None, cancel: () => cancelled.push(2) },
    { task_token: 3, request_id: None, cancel: () => cancelled.push(3) },
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
    reader: { read: _ => input.get() },
    writer: { write: _ => () },
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
  let options = { ..runtime_test_options(), queue_capacity: 2 }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime close does not enqueue over-capacity notification failures" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get() },
    writer: { write: _ => () },
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
  let options = { ..runtime_test_options(), queue_capacity: 2 }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime close does not enqueue over-capacity request cancels" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get() },
    writer: { write: _ => () },
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
  let options = { ..runtime_test_options(), queue_capacity: 2 }
  connection_runtime_run(ports, options)
  assert_eq(close_cancellations.length(), 3)
}

///|
async test "runtime close does not enqueue over-capacity request failures" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let gate : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let close_cancellations : Array[Unit] = []
  let ports : RuntimePorts = {
    reader: { read: _ => input.get() },
    writer: { write: _ => () },
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
  let options = { ..runtime_test_options(), queue_capacity: 2 }
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    { task_token: 7, request_id: Some(Number(1)), cancel: () => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    { task_token: 11, request_id: None, cancel: () => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    { task_token: 22, request_id: None, cancel: () => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    { task_token: 23, request_id: None, cancel: () => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
        [{ task_token: 5, request_id: Some(Number(7)), cancel: () => () }],
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
  )
  assert_eq(cancelled, [Number(70)])
  assert_eq(
    traces.filter(event => event.phase == "cancel_requested").length(),
    1,
  )
  let missing_ports : RuntimePorts = { ..ports, cancel_outbound: None }
  try
    runtime_emit_command(
      CancelOutboundTask(id=Number(71)),
      writer_queue,
      8,
      missing_ports,
      [],
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
      let _result : Unit = runtime_fail_and_close(
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
        [{ task_token: 7, request_id: Some(Number(1)), cancel: () => () }],
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    { task_token: 8, request_id: Some(Number(11)), cancel: () => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
      [{ task_token: 9, request_id: Some(Number(13)), cancel: () => () }],
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
  { admitted: [], completed: [], cancelled: [], aborted: [], notifications: [] }
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
        { ..state, cancelled: runtime_owner_test_push_id(state.cancelled, id) },
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
    reader: { read: _ => input.get() },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
  let result = runtime_apply_owner_commands(
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
    reader: { read: _ => None },
    writer: { write: _ => () },
    handlers: {
      request: _ => HandlerSuccess(Json::null()),
      notification: _ => (),
      response: _ => (),
      outbound_failure: None,
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
  let result = runtime_apply_owner_commands(
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    runtime_apply_owner_commands(
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
        { ..state, cancelled: runtime_owner_test_push_id(state.cancelled, id) },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    reader: { read: _ => None },
    writer: { write: _ => () },
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
    reader: { read: _ => input.get() },
    writer: { write: frame => output.push(frame) },
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
