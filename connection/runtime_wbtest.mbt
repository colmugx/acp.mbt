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
