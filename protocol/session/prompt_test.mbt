///|
fn session_prompt_test_meta() -> ProtocolNullable[Json] {
  Omitted
}

///|
fn session_prompt_test_blocks() -> Array[ContentBlock] {
  [
    Text({
      annotations: Omitted,
      text: "hello",
      meta: session_prompt_test_meta(),
    }),
    ResourceLink({
      annotations: Omitted,
      description: Null,
      mime_type: Omitted,
      name: "README",
      size: Omitted,
      title: Omitted,
      uri: "file:///workspace/README.md",
      meta: session_prompt_test_meta(),
    }),
  ]
}

///|
test "session prompt content blocks and metadata round trip" {
  let params : PromptParams = {
    session_id: "s-prompt",
    prompt: session_prompt_test_blocks(),
    meta: Null,
  }
  assert_eq(prompt_params_from_json(prompt_params_to_json(params)), params)

  let result : PromptResult = {
    stop_reason: Cancelled,
    meta: Value({ "turn": Json::string("cancelled") }),
  }
  assert_eq(prompt_result_from_json(prompt_result_to_json(result)), result)
}

///|
test "all five stable stop reasons use exact discriminators" {
  let end_turn : PromptResult = { stop_reason: EndTurn, meta: Omitted, }
  let max_tokens : PromptResult = { stop_reason: MaxTokens, meta: Omitted, }
  let max_turn_requests : PromptResult = {
    stop_reason: MaxTurnRequests,
    meta: Omitted,
  }
  let refusal : PromptResult = { stop_reason: Refusal, meta: Omitted, }
  let cancelled : PromptResult = { stop_reason: Cancelled, meta: Omitted, }
  assert_eq(
    prompt_result_to_json(end_turn),
    protocol_parse_json("{\"stopReason\":\"end_turn\"}"),
  )
  assert_eq(
    prompt_result_to_json(max_tokens),
    protocol_parse_json("{\"stopReason\":\"max_tokens\"}"),
  )
  assert_eq(
    prompt_result_to_json(max_turn_requests),
    protocol_parse_json("{\"stopReason\":\"max_turn_requests\"}"),
  )
  assert_eq(
    prompt_result_to_json(refusal),
    protocol_parse_json("{\"stopReason\":\"refusal\"}"),
  )
  assert_eq(
    prompt_result_to_json(cancelled),
    protocol_parse_json("{\"stopReason\":\"cancelled\"}"),
  )
  assert_eq(prompt_result_from_json(prompt_result_to_json(end_turn)), end_turn)
  assert_eq(
    prompt_result_from_json(prompt_result_to_json(max_tokens)),
    max_tokens,
  )
  assert_eq(
    prompt_result_from_json(prompt_result_to_json(max_turn_requests)),
    max_turn_requests,
  )
  assert_eq(prompt_result_from_json(prompt_result_to_json(refusal)), refusal)
  assert_eq(
    prompt_result_from_json(prompt_result_to_json(cancelled)),
    cancelled,
  )
}

///|
test "prompt accepts an empty content array and preserves omitted fields" {
  let params = prompt_params_from_json(
    protocol_parse_json("{\"sessionId\":\"s\",\"prompt\":[]}"),
  )
  assert_eq(params.session_id, "s")
  assert_eq(params.prompt, [])
  assert_eq(params.meta, Omitted)
}

///|
test "prompt rejects invalid stop reasons content tags and unknown fields" {
  try prompt_result_from_json(protocol_parse_json("{}")) catch {
    MissingField(path="session/prompt.stopReason") => ()
    _ => fail("expected missing stop reason rejection")
  } noraise {
    _ => fail("expected missing stop reason rejection")
  }

  try
    prompt_result_from_json(protocol_parse_json("{\"stopReason\":\"future\"}"))
  catch {
    InvalidDiscriminator(path="session/prompt.stopReason", value="future") => ()
    _ => fail("expected unknown stop reason rejection")
  } noraise {
    _ => fail("expected unknown stop reason rejection")
  }

  try
    prompt_result_from_json(protocol_parse_json("{\"stopReason\":null}"))
  catch {
    ExpectedString(path="session/prompt.stopReason") => ()
    _ => fail("expected null stop reason rejection")
  } noraise {
    _ => fail("expected null stop reason rejection")
  }

  try
    prompt_params_from_json(
      protocol_parse_json(
        "{\"sessionId\":\"s\",\"prompt\":[{\"type\":\"future\"}]}",
      ),
    )
  catch {
    InvalidDiscriminator(path="session/prompt.prompt[0].type", value="future") =>
      ()
    _ => fail("expected unknown content tag rejection")
  } noraise {
    _ => fail("expected unknown content tag rejection")
  }

  try
    prompt_params_from_json(
      protocol_parse_json("{\"sessionId\":\"s\",\"prompt\":[],\"extra\":true}"),
    )
  catch {
    UnknownField(path="session/prompt.extra") => ()
    _ => fail("expected prompt unknown field rejection")
  } noraise {
    _ => fail("expected prompt unknown field rejection")
  }
}
