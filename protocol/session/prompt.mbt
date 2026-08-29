///|
/// Why an agent stopped processing one prompt turn.
pub(all) enum StopReason {
  EndTurn
  MaxTokens
  MaxTurnRequests
  Refusal
  Cancelled
} derive(Eq, Debug)

///|
/// Parameters for `session/prompt`.
pub(all) struct PromptParams {
  session_id : SessionId
  prompt : Array[ContentBlock]
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
/// Result of `session/prompt`.
pub(all) struct PromptResult {
  stop_reason : StopReason
  meta : ProtocolNullable[Json]
} derive(Eq, Debug)

///|
fn session_prompt_decode_blocks(
  value : Json,
  path~ : String,
) -> Array[ContentBlock] raise ProtocolDecodeError {
  let values = protocol_require_array(value, path~)
  let result : Array[ContentBlock] = []
  for index, value in values {
    result.push(
      content_block_from_json(value, path=path + "[" + index.to_string() + "]"),
    )
  }
  result
}

///|
fn session_prompt_encode_blocks(
  values : Array[ContentBlock],
) -> Json raise ProtocolDecodeError {
  let result : Array[Json] = []
  for value in values {
    result.push(content_block_to_json(value))
  }
  Json::array(result)
}

///|
fn session_prompt_decode_stop_reason(
  value : Json,
  path~ : String,
) -> StopReason raise ProtocolDecodeError {
  match value {
    String("end_turn") => EndTurn
    String("max_tokens") => MaxTokens
    String("max_turn_requests") => MaxTurnRequests
    String("refusal") => Refusal
    String("cancelled") => Cancelled
    String(other) => raise InvalidDiscriminator(path~, value=other)
    _ => raise ExpectedString(path~)
  }
}

///|
fn session_prompt_encode_stop_reason(value : StopReason) -> Json {
  Json::string(
    match value {
      EndTurn => "end_turn"
      MaxTokens => "max_tokens"
      MaxTurnRequests => "max_turn_requests"
      Refusal => "refusal"
      Cancelled => "cancelled"
    },
  )
}

///|
/// Decode `session/prompt` parameters.
pub fn prompt_params_from_json(
  value : Json,
  path? : String = "session/prompt",
) -> PromptParams raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["sessionId", "prompt", "_meta"], prefix=path)
  let session_id = protocol_required_string(
    fields,
    "sessionId",
    path=path + ".sessionId",
  )
  let prompt = session_prompt_decode_blocks(
    protocol_required(fields, "prompt", path=path + ".prompt"),
    path=path + ".prompt",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { session_id, prompt, meta, }
}

///|
/// Encode `session/prompt` parameters.
pub fn prompt_params_to_json(
  value : PromptParams,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["sessionId"] = Json::string(value.session_id)
  fields["prompt"] = session_prompt_encode_blocks(value.prompt)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}

///|
/// Decode the result of `session/prompt`.
pub fn prompt_result_from_json(
  value : Json,
  path? : String = "session/prompt",
) -> PromptResult raise ProtocolDecodeError {
  let fields = protocol_require_object(value, path~)
  protocol_reject_unknown(fields, ["stopReason", "_meta"], prefix=path)
  let stop_reason = session_prompt_decode_stop_reason(
    protocol_required(fields, "stopReason", path=path + ".stopReason"),
    path=path + ".stopReason",
  )
  let meta = protocol_meta(fields, path=path + "._meta")
  { stop_reason, meta, }
}

///|
/// Encode the result of `session/prompt`.
pub fn prompt_result_to_json(
  value : PromptResult,
) -> Json raise ProtocolDecodeError {
  let fields : Map[String, Json] = Map([])
  fields["stopReason"] = session_prompt_encode_stop_reason(value.stop_reason)
  protocol_put_meta(fields, value.meta)
  Json::object(fields)
}
