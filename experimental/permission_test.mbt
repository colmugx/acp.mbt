///|
test "v2 permission option kinds model defined and open values" {
  let cases : Array[(String, ExperimentalV2PermissionOptionKind)] = [
    ("allow_once", OptionKindAllowOnce),
    ("allow_always", OptionKindAllowAlways),
    ("reject_once", OptionKindRejectOnce),
    ("reject_always", OptionKindRejectAlways),
    ("_trust", OptionKindExtension(tag="_trust")),
    ("maybe", OptionKindFuture(raw="maybe")),
  ]
  for entry in cases {
    let (tag, expected) = entry
    let decoded = experimental_v2_decode_permission_option_kind(
      Json::string(tag),
    )
    assert_eq(decoded, expected)
    assert_eq(
      experimental_v2_decode_permission_option_kind(
        experimental_v2_encode_permission_option_kind(decoded),
      ),
      decoded,
    )
  }
  let option = model_test_round_trip(
    "{\"optionId\":\"o1\",\"name\":\"Allow\",\"kind\":\"allow_once\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_permission_option(value),
    experimental_v2_encode_permission_option,
  )
  assert_eq(option.option_id, "o1")
  assert_true(option.kind is OptionKindAllowOnce)
}

///|
test "v2 permission outcome covers cancelled selected and open arms" {
  let cancelled = model_test_round_trip(
    "{\"outcome\":\"cancelled\"}",
    value => experimental_v2_decode_permission_outcome(value),
    experimental_v2_encode_permission_outcome,
  )
  assert_true(cancelled is Known(OutcomeCancelled))
  let selected = model_test_round_trip(
    "{\"outcome\":\"selected\",\"optionId\":\"o1\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_permission_outcome(value),
    experimental_v2_encode_permission_outcome,
  )
  assert_true(selected is Known(OutcomeSelected({ option_id: "o1", .. })))
  let extension = model_test_round_trip(
    "{\"outcome\":\"_escrow\",\"held\":true}",
    value => experimental_v2_decode_permission_outcome(value),
    experimental_v2_encode_permission_outcome,
  )
  assert_true(extension is Extension(tag="_escrow", ..))
  let future = model_test_round_trip(
    "{\"outcome\":\"deferred\",\"until\":\"later\"}",
    value => experimental_v2_decode_permission_outcome(value),
    experimental_v2_encode_permission_outcome,
  )
  assert_true(future is Future(tag="deferred", ..))
  try
    experimental_v2_decode_permission_outcome(
      experimental_v2_parse_json(
        "{\"outcome\":\"cancelled\",\"optionId\":\"o1\"}",
      ),
    )
  catch {
    error => assert_eq(error, UnknownField(path="outcome.optionId"))
  } noraise {
    _ => fail("expected UnknownField for extra fields on a cancelled outcome")
  }
  try
    experimental_v2_decode_permission_outcome(
      experimental_v2_parse_json("{\"outcome\":\"selected\"}"),
    )
  catch {
    error => assert_eq(error, MissingField(path="outcome.optionId"))
  } noraise {
    _ => fail("expected MissingField for a selected outcome without optionId")
  }
}

///|
test "v2 permission subject models tool call and command arms and open values" {
  let tool_call = model_test_round_trip(
    "{\"type\":\"tool_call\",\"toolCall\":{\"toolCallId\":\"tc1\",\"title\":\"Run build\",\"kind\":\"execute\",\"status\":\"pending\",\"rawInput\":{\"cmd\":\"make\"}}}",
    value => experimental_v2_decode_permission_subject(value),
    experimental_v2_encode_permission_subject,
  )
  guard tool_call is Known(SubjectToolCall(subject)) else {
    fail("expected a tool call subject")
  }
  assert_eq(subject.tool_call.tool_call_id, "tc1")
  assert_true(subject.tool_call.kind is PatchValue(ToolKindExecute))
  assert_true(subject.tool_call.status is PatchValue(ToolCallStatusPending))
  let command = model_test_round_trip(
    "{\"type\":\"command\",\"command\":\"rm -rf /tmp/x\",\"cwd\":\"/repo\",\"toolCallId\":null,\"terminalId\":\"t1\",\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_permission_subject(value),
    experimental_v2_encode_permission_subject,
  )
  guard command is Known(SubjectCommand(subject)) else {
    fail("expected a command subject")
  }
  assert_eq(subject.command, "rm -rf /tmp/x")
  assert_eq(subject.cwd, "/repo")
  assert_eq(subject.tool_call_id, None)
  assert_eq(subject.terminal_id, Some("t1"))
  let extension = model_test_round_trip(
    "{\"type\":\"_network\",\"host\":\"db\"}",
    value => experimental_v2_decode_permission_subject(value),
    experimental_v2_encode_permission_subject,
  )
  assert_true(extension is Extension(tag="_network", ..))
  let future = model_test_round_trip(
    "{\"type\":\"spend\",\"amount\":5}",
    value => experimental_v2_decode_permission_subject(value),
    experimental_v2_encode_permission_subject,
  )
  assert_true(future is Future(tag="spend", ..))
}

///|
test "v2 command permission subject requires command and absolute cwd" {
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    ("{\"cwd\":\"/repo\"}", MissingField(path="subject.command")),
    ("{\"command\":\"ls\"}", MissingField(path="subject.cwd")),
    (
      "{\"command\":\"ls\",\"cwd\":\"repo\"}",
      InvalidPath(path="subject.cwd", value="repo"),
    ),
    (
      "{\"command\":\"ls\",\"cwd\":\"/repo\",\"toolCallId\":\"\"}",
      InvalidField(path="subject.toolCallId", reason="id must not be empty"),
    ),
    (
      "{\"command\":\"ls\",\"cwd\":\"/repo\",\"terminalId\":\"\"}",
      InvalidField(path="subject.terminalId", reason="id must not be empty"),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_command_permission_subject(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed command subject")
    }
  }
}

///|
test "v2 request permission request validates required fields and options" {
  let request = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"title\":\"Run command\",\"description\":\"needed for build\",\"subject\":{\"type\":\"command\",\"command\":\"make\",\"cwd\":\"/repo\"},\"options\":[{\"optionId\":\"o1\",\"name\":\"Allow once\",\"kind\":\"allow_once\"},{\"optionId\":\"o2\",\"name\":\"Reject\",\"kind\":\"reject_always\"}],\"_meta\":{\"k\":1}}",
    value => experimental_v2_decode_request_permission_request(value),
    experimental_v2_encode_request_permission_request,
  )
  assert_eq(request.session_id, "s1")
  assert_eq(request.title, "Run command")
  assert_eq(request.options.length(), 2)
  let bare = model_test_round_trip(
    "{\"sessionId\":\"s1\",\"title\":\"t\",\"options\":[{\"optionId\":\"o1\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
    value => experimental_v2_decode_request_permission_request(value),
    experimental_v2_encode_request_permission_request,
  )
  assert_true(bare.description is None && bare.subject is None)
  assert_true(
    experimental_v2_decode_request_permission_request(
      experimental_v2_parse_json(
        "{\"sessionId\":\"s1\",\"title\":\"t\",\"description\":null,\"subject\":null,\"options\":[{\"optionId\":\"o1\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      ),
    ).description
    is None,
  )
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"title\":\"t\",\"options\":[{\"optionId\":\"o1\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      MissingField(path="session/request_permission.sessionId"),
    ),
    (
      "{\"sessionId\":\"s1\",\"options\":[{\"optionId\":\"o1\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      MissingField(path="session/request_permission.title"),
    ),
    (
      "{\"sessionId\":\"s1\",\"title\":\"t\"}",
      MissingField(path="session/request_permission.options"),
    ),
    (
      "{\"sessionId\":\"s1\",\"title\":\"t\",\"options\":[]}",
      InvalidField(
        path="session/request_permission.options",
        reason="options must contain at least one option",
      ),
    ),
    (
      "{\"sessionId\":\"\",\"title\":\"t\",\"options\":[{\"optionId\":\"o1\",\"name\":\"Allow\",\"kind\":\"allow_once\"}]}",
      InvalidField(
        path="session/request_permission.sessionId",
        reason="id must not be empty",
      ),
    ),
  ]
  for entry in cases {
    let (source, expected) = entry
    try
      experimental_v2_decode_request_permission_request(
        experimental_v2_parse_json(source),
      )
    catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed permission request")
    }
  }
}

///|
test "v2 request permission response round-trips every outcome" {
  let cases : Array[(String, String)] = [
    ("{\"outcome\":{\"outcome\":\"cancelled\"}}", "cancelled"),
    ("{\"outcome\":{\"outcome\":\"selected\",\"optionId\":\"o1\"}}", "selected"),
    ("{\"outcome\":{\"outcome\":\"_escrow\"}}", "extension"),
    ("{\"outcome\":{\"outcome\":\"deferred\"}}", "future"),
  ]
  for entry in cases {
    let (outcome_source, shape) = entry
    let response = model_test_round_trip(
      outcome_source,
      value => experimental_v2_decode_request_permission_response(value),
      experimental_v2_encode_request_permission_response,
    )
    let matched = match response.outcome {
      Known(OutcomeCancelled) => shape == "cancelled"
      Known(OutcomeSelected(_)) => shape == "selected"
      Extension(_) => shape == "extension"
      Future(_) => shape == "future"
    }
    assert_true(matched)
  }
  try
    experimental_v2_decode_request_permission_response(
      experimental_v2_parse_json("{\"_meta\":{}}"),
    )
  catch {
    error =>
      assert_eq(error, MissingField(path="session/request_permission.outcome"))
  } noraise {
    _ => fail("expected MissingField for a response without outcome")
  }
}
