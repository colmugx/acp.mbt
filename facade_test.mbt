///|
test "root facade exposes stable wire, message, runtime, and manifest APIs" {
  let request : RequestId = String("facade")
  let envelope = JsonRpcRequest::new(
    id=request,
    method_name="initialize",
    params=Json::object({ "protocolVersion": Json::number(1.0) }),
  )
  assert_eq(envelope.method_name, "initialize")
  let message = JsonRpcMessage::request(envelope)
  assert_eq(jsonrpc_decode(jsonrpc_encode(message)), message)

  let implementation : Implementation = {
    name: "facade",
    title: Omitted,
    version: "test",
    meta: Omitted,
  }
  assert_eq(
    implementation_from_json(implementation_to_json(implementation)),
    implementation,
  )

  let methods = acp_v1_method_manifest()
  assert_true(methods.length() == 25)
  assert_eq(methods[0].method_name, "initialize")

  let agent_request = decode_agent_request(
    "initialize",
    Some(Json::object({ "protocolVersion": Json::number(1.0) })),
  )
  assert_true(agent_request is Initialize(_))
  let client_notification = decode_client_notification(
    "$/cancel_request",
    Some(Json::object({ "requestId": Json::string("facade") })),
  )
  assert_true(client_notification is CancelRequest(_))

  let options = runtime_default_options()
  runtime_validate_options(options)
  let framed = framing_feed(
    framing_state(max_frame_bytes=128),
    b"{\"jsonrpc\":\"2.0\",\"method\":\"m\"}\n",
  )
  assert_eq(framed.frames.length(), 1)

  let error = JsonRpcError::auth_required()
  let response_id : ResponseId = String("response")
  let error_response = JsonRpcResponse::error(id=response_id, error~)
  assert_true(error_response is Error(_))
}
