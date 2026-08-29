///|
/// Deterministic in-memory ports for the v2 runner tests: identical contract
/// to the broker test ports (queue-fed reader, recording writer, response and
/// outbound-failure settle callbacks).
fn experimental_v2_runtime_test_ports(
  input : @aqueue.Queue[Bytes?],
  output : Array[Bytes],
  written : @aqueue.Queue[Unit],
  traces : Array[@runtime.RuntimeTraceEvent],
  responses : Array[String],
  failures : Array[(@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind)],
) -> @runtime.RuntimePorts {
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
      response: response => {
        responses.push(
          match response {
            Success(success) => @runtime.runtime_request_id_text(success.id)
            Error(failure) =>
              match failure.id {
                String(value) => value
                Number(value) => value.to_string()
                Null => "null"
              }
          },
        )
      },
      outbound_failure: Some((id, failure) => {
        failures.push((id, failure.reason))
      }),
    },
    cancel_outbound: None,
    trace: event => traces.push(event),
  }
}

///|
fn experimental_v2_runtime_test_chunk(frame : String) -> Bytes? {
  Some(@utf8.encode(frame))
}

///|
fn experimental_v2_runtime_test_initialize(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":2,\"info\":{\"name\":\"client\",\"version\":\"1\"},\"capabilities\":{}}}\n"
}

///|
fn experimental_v2_runtime_test_session_new(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/new\",\"params\":{\"cwd\":\"/\"}}\n"
}

///|
fn experimental_v2_runtime_test_session_prompt(id : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":\"" +
  id +
  "\",\"method\":\"session/prompt\",\"params\":{\"sessionId\":\"created\",\"prompt\":[]}}\n"
}

///|
fn experimental_v2_runtime_test_decode(
  frame : Bytes,
) -> @jsonrpc.JsonRpcResponse raise {
  match @jsonrpc.jsonrpc_decode(@utf8.decode(frame.view())) {
    Response(response) => response
    _ => fail("expected one JSON-RPC response frame")
  }
}

///|
fn experimental_v2_runtime_test_success_id(
  frame : Bytes,
) -> @jsonrpc.RequestId raise {
  match experimental_v2_runtime_test_decode(frame) {
    Success(success) => success.id
    Error(_) => fail("expected a successful JSON-RPC response")
  }
}

///|
fn experimental_v2_runtime_test_update(
  update : String,
) -> ExperimentalV2UpdateSessionNotification raise {
  experimental_v2_decode_update_session_notification(
    experimental_v2_broker_test_notification_params(
      experimental_v2_broker_test_notification(
        @utf8.encode(
          "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"created\",\"update\":" +
          update +
          "}}",
        ),
      ),
    ),
  )
}

///|
/// The full-turn prompt handler: stream a user-message upsert plus a
/// `state_update running`, round-trip one permission request through the
/// outbound context, stream `state_update idle`, then finish the turn.  The
/// observed permission outcome and every streamed notification are recorded
/// for assertion.
async fn experimental_v2_runtime_test_streaming_prompt(
  context : ExperimentalV2AgentContext,
  streamed : Array[ExperimentalV2UpdateSessionNotification],
  replies : Array[ExperimentalV2RequestPermissionResponse],
  _params : ExperimentalV2PromptParams,
) -> ExperimentalV2PromptResult {
  let user_message : ExperimentalV2UpdateSessionNotification = {
    session_id: "created",
    update: Known(
      UpdateUserMessage({
        message_id: "m1",
        content: PatchValue([
          Known(BlockText({ text: "hello", annotations: None, meta: None, })),
        ]),
        meta: PatchOmitted,
      }),
    ),
    meta: None,
  }
  let running : ExperimentalV2UpdateSessionNotification = {
    session_id: "created",
    update: Known(UpdateState(Known(StateRunning({ meta: None, })))),
    meta: None,
  }
  let idle : ExperimentalV2UpdateSessionNotification = {
    session_id: "created",
    update: Known(
      UpdateState(
        Known(StateIdle({ stop_reason: Some(StopReasonEndTurn), meta: None, })),
      ),
    ),
    meta: None,
  }
  context.session_update(user_message)
  streamed.push(user_message)
  context.session_update(running)
  streamed.push(running)
  let reply = context.request_permission({
    session_id: "created",
    title: "proceed?",
    description: None,
    subject: None,
    options: [
      {
        option_id: "allow",
        name: "Allow",
        kind: OptionKindAllowOnce,
        meta: None,
      },
    ],
    meta: None,
  })
  replies.push(reply)
  context.session_update(idle)
  streamed.push(idle)
  { meta: None, }
}

///|
async test "v2 agent runtime run with outbound streams a full turn with permission" {
  let streamed : Array[ExperimentalV2UpdateSessionNotification] = []
  let replies : Array[ExperimentalV2RequestPermissionResponse] = []
  let endpoint = experimental_v2_agent_test_endpoint(prompt=async fn(
    context,
    params,
  ) {
    experimental_v2_runtime_test_streaming_prompt(
      context, streamed, replies, params,
    )
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_runtime_test_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      experimental_v2_runtime_test_initialize("init"),
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => {
          experimental_v2_agent_context_over_channel(channel~)
        },
        initial_state=experimental_v2_agent_test_adapter_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    // Each frame is offered only after the previous write is observed, so
    // admission and write order stay deterministic without sleeps.
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      input.put(
        experimental_v2_runtime_test_chunk(
          experimental_v2_runtime_test_session_new("new"),
        ),
      )
      ignore(written.get()) // session/new response
      input.put(
        experimental_v2_runtime_test_chunk(
          experimental_v2_runtime_test_session_prompt("prompt"),
        ),
      )
      ignore(written.get()) // session/update user message
      ignore(written.get()) // session/update running
      ignore(written.get()) // session/request_permission request
      input.put(
        experimental_v2_runtime_test_chunk(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"outcome\":{\"outcome\":\"selected\",\"optionId\":\"allow\"}}}\n",
        ),
      )
      ignore(written.get()) // session/update idle
      ignore(written.get()) // session/prompt response
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(output.length(), 7)
  assert_eq(experimental_v2_runtime_test_success_id(output[0]), String("init"))
  assert_eq(experimental_v2_runtime_test_success_id(output[1]), String("new"))
  // The three streamed notifications decode back to the typed values, and
  // the fold consumes them exactly as a client session store would.
  let first = experimental_v2_runtime_test_update(
    "{\"sessionUpdate\":\"user_message\",\"messageId\":\"m1\",\"content\":[{\"type\":\"text\",\"text\":\"hello\"}]}",
  )
  let second = experimental_v2_runtime_test_update(
    "{\"sessionUpdate\":\"state_update\",\"state\":\"running\"}",
  )
  let third = experimental_v2_runtime_test_update(
    "{\"sessionUpdate\":\"state_update\",\"state\":\"idle\",\"stopReason\":\"end_turn\"}",
  )
  assert_eq(streamed, [first, second, third])
  let fold_one = match
    experimental_v2_session_fold_apply(
      experimental_v2_session_fold_new(),
      first.update,
    ) {
    Ok(state) => state
    Err(error) => fail("expected the user message to fold: \{Repr(error)}")
  }
  assert_eq(fold_one.user_messages.length(), 1)
  let fold_two = match
    experimental_v2_session_fold_apply(fold_one, second.update) {
    Ok(state) => state
    Err(error) => fail("expected the running state to fold: \{Repr(error)}")
  }
  assert_eq(fold_two.phase, TurnRunning)
  let fold_three = match
    experimental_v2_session_fold_apply(fold_two, third.update) {
    Ok(state) => state
    Err(error) => fail("expected the idle state to fold: \{Repr(error)}")
  }
  assert_eq(fold_three.phase, TurnIdle)
  assert_true(fold_three.stop_reason is Some(StopReasonEndTurn))
  // The permission request frame carries the typed request; the observed
  // reply is the selected outcome the peer returned.
  let permission_frame = experimental_v2_broker_test_request(output[4])
  assert_eq(permission_frame.method_name, "session/request_permission")
  assert_eq(permission_frame.id, Number(1))
  let decoded_permission = try! experimental_v2_decode_request_permission_request(
    experimental_v2_broker_test_request_params(permission_frame),
  )
  assert_eq(decoded_permission.session_id, "created")
  assert_eq(decoded_permission.options[0].option_id, "allow")
  assert_eq(replies.length(), 1)
  assert_true(
    replies[0].outcome is Known(OutcomeSelected({ option_id: "allow", .. })),
  )
  assert_eq(
    experimental_v2_runtime_test_success_id(output[6]),
    String("prompt"),
  )
  assert_eq(responses, ["1"])
  assert_eq(failures.length(), 0)
}

///|
async test "v2 agent runtime outbound settles a parked submitter once on close" {
  let observed : Array[ExperimentalV2AgentContextError] = []
  let endpoint = experimental_v2_agent_test_endpoint(prompt=async fn(
    context,
    _params,
  ) {
    try {
      let _ = context.request_permission({
        session_id: "created",
        title: "proceed?",
        description: None,
        subject: None,
        options: [
          {
            option_id: "allow",
            name: "Allow",
            kind: OptionKindAllowOnce,
            meta: None,
          },
        ],
        meta: None,
      })
      ()
    } catch {
      error => observed.push(error)
    }
    { meta: None, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_runtime_test_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      experimental_v2_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      experimental_v2_runtime_test_session_prompt("prompt"),
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => {
          experimental_v2_agent_context_over_channel(channel~)
        },
        initial_state=experimental_v2_agent_test_adapter_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/request_permission request
      input.put(None)
      ignore(written.get()) // close settle for the pending prompt request
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  match observed[0] {
    ContextBrokerFailure(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected a typed context broker failure after close settle")
  }
  assert_eq(output.length(), 3)
  assert_eq(experimental_v2_runtime_test_success_id(output[0]), String("init"))
  assert_eq(
    experimental_v2_broker_test_request(output[1]).method_name,
    "session/request_permission",
  )
  let failure = try! experimental_v2_runtime_test_decode(output[2])
  guard failure is Error(failed) else {
    fail("expected the settled prompt request to answer with an error")
  }
  assert_eq(failed.error.code, InternalError)
  assert_eq(failures.length(), 1)
  assert_eq(failures[0].0, Number(1))
  assert_true(failures[0].1 is EndOfInput)
}

///|
async test "v2 agent runtime outbound maps the cancelled error code to a typed cancel" {
  let observed : Array[ExperimentalV2AgentContextError] = []
  let endpoint = experimental_v2_agent_test_endpoint(prompt=async fn(
    context,
    _params,
  ) {
    try {
      let _ = context.request_permission({
        session_id: "created",
        title: "proceed?",
        description: None,
        subject: None,
        options: [
          {
            option_id: "allow",
            name: "Allow",
            kind: OptionKindAllowOnce,
            meta: None,
          },
        ],
        meta: None,
      })
      ()
    } catch {
      error => observed.push(error)
    }
    { meta: None, }
  })
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_runtime_test_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      experimental_v2_runtime_test_initialize("init"),
    ),
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      experimental_v2_runtime_test_session_prompt("prompt"),
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_agent_runtime_run_with_outbound(
        endpoint~,
        context_factory=channel => {
          experimental_v2_agent_context_over_channel(channel~)
        },
        initial_state=experimental_v2_agent_test_adapter_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    let feeder = group.spawn(() => {
      ignore(written.get()) // initialize response
      ignore(written.get()) // session/request_permission request
      input.put(
        experimental_v2_runtime_test_chunk(
          "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32800,\"message\":\"cancelled\"}}\n",
        ),
      )
      ignore(written.get()) // session/prompt response
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(observed.length(), 1)
  match observed[0] {
    ContextCancelled(method_name~) =>
      assert_eq(method_name, "session/request_permission")
    _ => fail("expected a typed context cancellation")
  }
  assert_eq(output.length(), 3)
  assert_eq(
    experimental_v2_runtime_test_success_id(output[2]),
    String("prompt"),
  )
}

///|
async test "v2 client runtime run answers a reverse permission turn" {
  let updates : Array[ExperimentalV2UpdateSessionNotification] = []
  let permissions : Array[ExperimentalV2RequestPermissionRequest] = []
  let endpoint = experimental_v2_client_test_endpoint(updates, permissions, [])
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_runtime_test_ports(
    input, output, written, traces, responses, failures,
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      "{\"jsonrpc\":\"2.0\",\"id\":\"perm\",\"method\":\"session/request_permission\",\"params\":{\"sessionId\":\"session\",\"title\":\"proceed?\",\"options\":[{\"optionId\":\"allow\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}}\n",
    ),
  )
  input.put(
    experimental_v2_runtime_test_chunk(
      "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"session\",\"update\":{\"sessionUpdate\":\"state_update\",\"state\":\"running\"}}}\n",
    ),
  )
  // A late cancel for an id the client never admitted must be tolerated
  // without a response or a crash.
  input.put(
    experimental_v2_runtime_test_chunk(
      "{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"gone\"}}\n",
    ),
  )
  @async.with_task_group(group => {
    let runtime = group.spawn(() => {
      experimental_v2_client_runtime_run(
        endpoint~,
        initial_state=experimental_v2_client_test_adapter_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    // EOF is gated behind the permission response write so the pending
    // request settles through the normal completion path.
    let feeder = group.spawn(() => {
      ignore(written.get())
      input.put(None)
    })
    runtime.wait()
    feeder.wait()
  })
  assert_eq(permissions.length(), 1)
  assert_eq(updates.length(), 1)
  assert_true(updates[0].update is Known(UpdateState(Known(StateRunning(_)))))
  assert_eq(output.length(), 1)
  match experimental_v2_runtime_test_decode(output[0]) {
    Success(success) => {
      assert_eq(success.id, String("perm"))
      guard success.result is Object(fields) else {
        fail("expected a permission outcome object")
      }
      guard fields.get("outcome") is Some(Object(outcome)) else {
        fail("expected a permission outcome")
      }
      assert_true(outcome.get("outcome") is Some(String("selected")))
      assert_true(outcome.get("optionId") is Some(String("allow")))
    }
    Error(_) => fail("expected the permission turn to settle successfully")
  }
}

///|
async test "v2 agent serve stdio validates options before binding stdio" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let raised : Array[Unit] = []
  try {
    experimental_v2_agent_serve_stdio_with_outbound(
      endpoint~,
      context_factory=_channel => experimental_v2_agent_fail_fast_context(),
      initial_state=experimental_v2_agent_test_adapter_state(endpoint),
      options={ ..@runtime.runtime_default_options(), max_frame_bytes: 0, },
      trace=_ => (),
    )
    ()
  } catch {
    _ => raised.push(())
  }
  assert_eq(raised.length(), 1)
}
