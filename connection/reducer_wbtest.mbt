///|
fn wb_request(id : RequestId, method_name : String) -> JsonRpcRequest {
  JsonRpcRequest::new(id~, method_name~) catch {
    _ => abort("request fixture must have valid params")
  }
}

///|
fn wb_notification(method_name : String, params : Json?) -> JsonRpcNotification {
  match params {
    None =>
      JsonRpcNotification::new(method_name~) catch {
        _ => abort("notification fixture must have valid params")
      }
    Some(params) =>
      JsonRpcNotification::new(method_name~, params~) catch {
        _ => abort("notification fixture must have valid params")
      }
  }
}

///|
test "outgoing requests correlate responses and reject duplicates" {
  let request = wb_request(Number(1), "compute")
  let sent = connection_reduce(connection_state(), OutgoingRequest(request))
  assert_eq(sent.state.outbound.length(), 1)
  assert_eq(sent.state.outbound[0].id, Number(1))
  match sent.commands[0] {
    WriteMessage(Request(wire_request)) => assert_eq(wire_request, request)
    _ => fail("expected an outbound request write")
  }
  let response = JsonRpcResponse::success(
    id=Number(1),
    result=Json::string("ok"),
  )
  let completed = connection_reduce(sent.state, IncomingResponse(response))
  assert_eq(sent.state.outbound.length(), 1)
  assert_eq(completed.state.outbound.length(), 0)
  match completed.commands[0] {
    CompleteOutbound(id=Number(1), response=Success(_)) => ()
    _ => fail("expected correlated completion")
  }
  try connection_reduce(completed.state, IncomingResponse(response)) catch {
    DuplicateResponse(id=Number(1)) => ()
    _ => fail("expected duplicate response failure")
  } noraise {
    _ => fail("expected duplicate response to fail")
  }
}

///|
test "outgoing responses correlate correctly when they arrive out of order" {
  let first = connection_reduce(
    connection_state(),
    OutgoingRequest(wb_request(Number(1), "first")),
  )
  let second = connection_reduce(
    first.state,
    OutgoingRequest(wb_request(String("second"), "second")),
  )
  let second_done = connection_reduce(
    second.state,
    IncomingResponse(
      JsonRpcResponse::success(id=String("second"), result=Json::string("2")),
    ),
  )
  assert_eq(second_done.state.outbound.length(), 1)
  assert_eq(second_done.state.outbound[0].id, Number(1))
  let first_done = connection_reduce(
    second_done.state,
    IncomingResponse(
      JsonRpcResponse::success(id=Number(1), result=Json::string("1")),
    ),
  )
  assert_eq(first_done.state.outbound.length(), 0)
}

///|
test "outgoing cancellation writes exact notification and is idempotence-checked" {
  let request = wb_request(String("cancel-me"), "compute")
  let sent = connection_reduce(connection_state(), OutgoingRequest(request))
  let cancelled = connection_reduce(
    sent.state,
    CancelOutbound(id=String("cancel-me")),
  )
  assert_eq(cancelled.state.outbound.length(), 0)
  assert_true(cancelled.state.settled_outbound.contains(String("cancel-me")))
  match cancelled.commands[0] {
    WriteMessage(Notification(notification)) => {
      assert_eq(notification.method_name, "$/cancel_request")
      match notification.params {
        Some(Object(fields)) =>
          assert_eq(fields["requestId"], Json::string("cancel-me"))
        _ => fail("expected structured cancellation params")
      }
    }
    _ => fail("expected cancellation notification")
  }
  match cancelled.commands[1] {
    CancelOutboundTask(id=String("cancel-me")) => ()
    _ => fail("expected local cancellation intent")
  }
  try
    connection_reduce(cancelled.state, CancelOutbound(id=String("cancel-me")))
  catch {
    DuplicateCancellation(id=String("cancel-me")) => ()
    _ => fail("expected duplicate cancellation failure")
  } noraise {
    _ => fail("expected duplicate cancellation to fail")
  }
}

///|
test "null identifiers correlate, cancel, and preserve late-event identity" {
  let request = wb_request(Null, "compute")
  let sent = connection_reduce(connection_state(), OutgoingRequest(request))
  let cancelled = connection_reduce(sent.state, CancelOutbound(id=Null))
  assert_eq(cancelled.state.outbound.length(), 0)
  assert_true(cancelled.state.settled_outbound.contains(Null))
  match cancelled.commands[0] {
    WriteMessage(Notification(notification)) =>
      match notification.params {
        Some(Object(fields)) => assert_eq(fields["requestId"], Json::null())
        _ => fail("expected null cancellation id")
      }
    _ => fail("expected cancellation notification")
  }
  match cancelled.commands[1] {
    CancelOutboundTask(id=Null) => ()
    _ => fail("expected null outbound cancellation intent")
  }
  try connection_reduce(cancelled.state, CancelOutbound(id=Null)) catch {
    DuplicateCancellation(id=Null) => ()
    _ => fail("expected duplicate null cancellation failure")
  } noraise {
    _ => fail("expected duplicate null cancellation to fail")
  }

  let response_sent = connection_reduce(
    connection_state(),
    OutgoingRequest(wb_request(Null, "compute")),
  )
  let completed = connection_reduce(
    response_sent.state,
    IncomingResponse(JsonRpcResponse::success(id=Null, result=Json::null())),
  )
  match completed.commands[0] {
    CompleteOutbound(id=Null, response=Success(success)) =>
      assert_eq(success.id, Null)
    _ => fail("expected null success response correlation")
  }
  let error_sent = connection_reduce(
    connection_state(),
    OutgoingRequest(wb_request(Null, "compute")),
  )
  let error_completed = connection_reduce(
    error_sent.state,
    IncomingResponse(
      JsonRpcResponse::error(id=Null, error=JsonRpcError::internal_error()),
    ),
  )
  match error_completed.commands[0] {
    CompleteOutbound(id=Null, response=Error(failure)) =>
      assert_eq(failure.id, Null)
    _ => fail("expected null error response correlation")
  }
  try
    connection_reduce(
      error_completed.state,
      IncomingResponse(
        JsonRpcResponse::error(id=Null, error=JsonRpcError::internal_error()),
      ),
    )
  catch {
    DuplicateResponse(id=Null) => ()
    _ => fail("expected late null response failure")
  } noraise {
    _ => fail("expected late null response to fail")
  }

  let inbound = connection_reduce(
    connection_state(),
    IncomingRequest(wb_request(Null, "long_task")),
  )
  let params : Map[String, Json] = Map([])
  params["requestId"] = Json::null()
  let marked = connection_reduce(
    inbound.state,
    IncomingNotification(
      wb_notification("$/cancel_request", Some(Json::object(params))),
    ),
  )
  match marked.commands[0] {
    CancelInboundTask(id=Null) => ()
    _ => fail("expected null inbound cancellation intent")
  }
  let finished = connection_reduce(
    marked.state,
    IncomingCompleted(id=Null, result=Json::string("late")),
  )
  match finished.commands[0] {
    WriteMessage(Response(Error(failure))) => {
      assert_eq(failure.id, Null)
      assert_eq(failure.error.code, RequestCancelled)
    }
    _ => fail("expected null cancellation response")
  }
  try
    connection_reduce(
      finished.state,
      IncomingCompleted(id=Null, result=Json::null()),
    )
  catch {
    LateInboundCompletion(id=Null) => ()
    _ => fail("expected late null completion failure")
  } noraise {
    _ => fail("expected late null completion to fail")
  }
}

///|
test "inbound notifications dispatch without responses and cancellation targets one request" {
  let initial = connection_state()
  let notification = wb_notification("$/progress", None)
  let dispatched = connection_reduce(
    initial,
    IncomingNotification(notification),
  )
  assert_eq(dispatched.state.inbound.length(), 0)
  match dispatched.commands[0] {
    DispatchNotification(value) => assert_eq(value.method_name, "$/progress")
    _ => fail("expected notification dispatch")
  }

  let request = wb_request(Number(7), "long_task")
  let received = connection_reduce(initial, IncomingRequest(request))
  let params : Map[String, Json] = Map([])
  params["requestId"] = Json::number(7.0, repr="7")
  let cancel = wb_notification("$/cancel_request", Some(Json::object(params)))
  let marked = connection_reduce(received.state, IncomingNotification(cancel))
  assert_true(marked.state.inbound[0].cancel_requested)
  match marked.commands[0] {
    CancelInboundTask(id=Number(7)) => ()
    _ => fail("expected inbound cancellation intent")
  }
  let failed = connection_reduce(
    marked.state,
    IncomingFailed(id=Number(7), error=JsonRpcError::internal_error()),
  )
  assert_eq(failed.state.inbound.length(), 0)
  match failed.commands[0] {
    WriteMessage(Response(Error(failure))) => {
      assert_eq(failure.id, Number(7))
      assert_eq(failure.error.code, RequestCancelled)
    }
    _ => fail("expected cancellation error response")
  }
}

///|
test "inbound cancellation wins a later success and emits one response" {
  let received = connection_reduce(
    connection_state(),
    IncomingRequest(wb_request(Number(9), "long_task")),
  )
  let params : Map[String, Json] = Map([])
  params["requestId"] = Json::number(9.0, repr="9")
  let marked = connection_reduce(
    received.state,
    IncomingNotification(
      wb_notification("$/cancel_request", Some(Json::object(params))),
    ),
  )
  let completed = connection_reduce(
    marked.state,
    IncomingCompleted(id=Number(9), result=Json::string("late-success")),
  )
  assert_eq(completed.state.inbound.length(), 0)
  match completed.commands[0] {
    WriteMessage(Response(Error(failure))) =>
      assert_eq(failure.error.code, RequestCancelled)
    _ => fail("expected cancellation error response")
  }
  try
    connection_reduce(
      completed.state,
      IncomingCompleted(id=Number(9), result=Json::string("duplicate")),
    )
  catch {
    LateInboundCompletion(id=Number(9)) => ()
    _ => fail("expected late completion failure")
  } noraise {
    _ => fail("expected late completion to fail")
  }
}

///|
test "completion before cancellation stays success and late cancel is visible" {
  let received = connection_reduce(
    connection_state(),
    IncomingRequest(wb_request(Number(10), "short_task")),
  )
  let completed = connection_reduce(
    received.state,
    IncomingCompleted(id=Number(10), result=Json::string("ok")),
  )
  match completed.commands[0] {
    WriteMessage(Response(Success(success))) => {
      assert_eq(success.id, Number(10))
      assert_eq(success.result, Json::string("ok"))
    }
    _ => fail("expected success response before cancellation")
  }
  try connection_reduce(completed.state, CancelInbound(id=Number(10))) catch {
    DuplicateCancellation(id=Number(10)) => ()
    _ => fail("expected late cancellation failure")
  } noraise {
    _ => fail("expected late cancellation to fail")
  }
}

///|
test "unknown and late cancellations and completions are visible" {
  try
    connection_reduce(connection_state(), CancelInbound(id=Number(99)))
  catch {
    UnknownCancellation(id=Number(99)) => ()
    _ => fail("expected unknown cancellation failure")
  } noraise {
    _ => fail("expected unknown cancellation to fail")
  }
  let received = connection_reduce(
    connection_state(),
    IncomingRequest(wb_request(Number(8), "m")),
  )
  let completed = connection_reduce(
    received.state,
    IncomingCompleted(id=Number(8), result=Json::null()),
  )
  try
    connection_reduce(
      completed.state,
      IncomingCompleted(id=Number(8), result=Json::null()),
    )
  catch {
    LateInboundCompletion(id=Number(8)) => ()
    _ => fail("expected late inbound completion failure")
  } noraise {
    _ => fail("expected late inbound completion to fail")
  }
}

///|
test "close fails every pending direction and late responses stay visible" {
  let outbound = connection_reduce(
    connection_state(),
    OutgoingRequest(wb_request(String("out"), "outbound")),
  )
  let both = connection_reduce(
    outbound.state,
    IncomingRequest(wb_request(Number(2), "inbound")),
  )
  let closed = connection_reduce(both.state, Close(reason="eof"))
  assert_eq(closed.state.outbound.length(), 0)
  assert_eq(closed.state.inbound.length(), 0)
  assert_true(
    closed.commands.any(value => value is FailOutbound(id=String("out"), ..)),
  )
  assert_true(
    closed.commands.any(value => value is FailInbound(id=Number(2), ..)),
  )
  match closed.state.phase {
    ConnectionClosed(reason="eof") => ()
    _ => fail("expected closed phase")
  }
  let late = JsonRpcResponse::success(id=String("out"), result=Json::null())
  try connection_reduce(closed.state, IncomingResponse(late)) catch {
    LateResponse(id=String("out")) => ()
    _ => fail("expected late response failure")
  } noraise {
    _ => fail("expected late response to fail")
  }
}
