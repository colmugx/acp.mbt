///|
/// One v2 batch frame: a JSON array of `ExperimentalV2BatchItem` entries on a
/// single line.
///
/// Normative framing (agentclientprotocol.com /protocol/v2/transports.md):
/// mixed and notification-only batches are valid; an all-notification batch
/// gets no reply at all (never an empty array); replies are arrays of response
/// objects matched by id in any order, so the responses encoder keeps whatever
/// order the caller chooses.
///
/// Advisory: entries SHOULD NOT batch `initialize`, `auth/login`,
/// `session/new`, `session/resume`, or `session/prompt`.  This codec is
/// envelope-level and deliberately does not enforce that list; enforcement
/// belongs to the v2 state machine layer.
pub type ExperimentalV2Batch = Array[ExperimentalV2BatchItem]

///|
/// An invalid batch entry: the typed codec failure plus the per-entry -32600
/// id-null error response the batch rules require for it.  Invalid entries are
/// never dropped; sibling entries still decode.
pub(all) struct ExperimentalV2BatchInvalidItem {
  cause : @jsonrpc.JsonRpcCodecError
  response : @jsonrpc.JsonRpcResponse
} derive(Eq, Debug)

///|
/// One decoded batch entry.  Ids reuse `@jsonrpc.RequestId` because the batch
/// codec composes the shared jsonrpc envelope types; the model-scoped
/// `ExperimentalV2RequestId` in elicitation.mbt serves elicitation payloads
/// and is unrelated to envelope correlation.
pub(all) enum ExperimentalV2BatchItem {
  Request(@jsonrpc.JsonRpcRequest)
  Notification(@jsonrpc.JsonRpcNotification)
  InvalidItem(ExperimentalV2BatchInvalidItem)
} derive(Eq, Debug)

///|
/// Batch-level decode failures.  `BatchParseFailed` and `EmptyBatch` carry the
/// exact single (non-array) error response the v2 batch rules require;
/// `NotABatch` carries the parsed value so the caller can hand a lone object
/// to the per-object codec without re-parsing.
pub(all) suberror ExperimentalV2BatchDecodeError {
  BatchParseFailed(message~ : String, response~ : @jsonrpc.JsonRpcResponse)
  EmptyBatch(response~ : @jsonrpc.JsonRpcResponse)
  NotABatch(value~ : Json)
} derive(Eq, Debug)

///|
/// Batch-level encode failures.  Empty inputs are caller errors: an empty
/// batch or an empty response array is never a valid frame to send.
pub(all) suberror ExperimentalV2BatchEncodeError {
  EmptyBatchInput
  EmptyResponsesInput
  ItemEncodeFailed(index~ : Int, cause~ : @jsonrpc.JsonRpcCodecError)
  ResponseEncodeFailed(index~ : Int, cause~ : @jsonrpc.JsonRpcCodecError)
} derive(Eq, Debug)

///|
/// Decode one v2 batch frame.  Invalid batch JSON raises `BatchParseFailed`
/// and an empty array raises `EmptyBatch`, each carrying the single id-null
/// error response (-32700 / -32600) the caller must send instead of an array.
pub fn experimental_v2_batch_decode(
  source : String,
) -> ExperimentalV2Batch raise ExperimentalV2BatchDecodeError {
  let value = @json.parse(source) catch {
    error =>
      raise BatchParseFailed(
        message=error.to_string(),
        response=experimental_v2_batch_single_error(
          @jsonrpc.JsonRpcError::parse_error(),
        ),
      )
  }
  match value {
    Array(items) =>
      if items.length() == 0 {
        raise EmptyBatch(
          response=experimental_v2_batch_single_error(
            @jsonrpc.JsonRpcError::invalid_request(),
          ),
        )
      } else {
        items.map(item => experimental_v2_batch_decode_item(item))
      }
    _ => raise NotABatch(value~)
  }
}

///|
/// Encode batch items as one compact array frame with no framing newline.
/// Invalid entries encode as their own -32600 id-null error responses.
pub fn experimental_v2_batch_encode(
  batch : ExperimentalV2Batch,
) -> String raise ExperimentalV2BatchEncodeError {
  if batch.length() == 0 {
    raise EmptyBatchInput
  }
  let frames : Array[Json] = []
  for index, item in batch {
    let frame = @jsonrpc.jsonrpc_to_json(
      experimental_v2_batch_item_message(item),
    ) catch {
      cause => raise ItemEncodeFailed(index~, cause~)
    }
    frames.push(frame)
  }
  Json::array(frames).stringify()
}

///|
/// Encode batch replies as one compact array frame with no framing newline.
/// The order is the caller's choice; any order is a legal reply.  An empty
/// array is a caller error: notification-only batches get no reply at all.
pub fn experimental_v2_batch_responses_encode(
  responses : Array[@jsonrpc.JsonRpcResponse],
) -> String raise ExperimentalV2BatchEncodeError {
  if responses.length() == 0 {
    raise EmptyResponsesInput
  }
  let frames : Array[Json] = []
  for index, response in responses {
    let frame = @jsonrpc.jsonrpc_to_json(
      @jsonrpc.JsonRpcMessage::response(response),
    ) catch {
      cause => raise ResponseEncodeFailed(index~, cause~)
    }
    frames.push(frame)
  }
  Json::array(frames).stringify()
}

///|
/// Collect the request ids of a batch in wire order for reply correlation.
/// Notifications and invalid entries contribute nothing.
pub fn experimental_v2_batch_request_ids(
  batch : ExperimentalV2Batch,
) -> Array[@jsonrpc.RequestId] {
  let ids : Array[@jsonrpc.RequestId] = []
  for item in batch {
    match item {
      Request(request) => ids.push(request.id)
      _ => ()
    }
  }
  ids
}

///|
/// True when every entry is a notification: the batch gets no reply at all,
/// never an empty array.  Invalid entries count as non-notifications because
/// each one carries an error response.
pub fn experimental_v2_batch_is_notification_only(
  batch : ExperimentalV2Batch,
) -> Bool {
  batch.fold(init=true, (only, item) => only && item is Notification(_))
}

///|
fn experimental_v2_batch_decode_item(item : Json) -> ExperimentalV2BatchItem {
  try @jsonrpc.jsonrpc_decode_json(item) catch {
    cause => experimental_v2_batch_invalid_item(cause)
  } noraise {
    message =>
      match message {
        Request(request) => Request(request)
        Notification(notification) => Notification(notification)
        Response(_) =>
          experimental_v2_batch_invalid_item(
            InvalidRequest(
              reason="batch entries must be requests or notifications",
            ),
          )
      }
  }
}

///|
fn experimental_v2_batch_item_message(
  item : ExperimentalV2BatchItem,
) -> @jsonrpc.JsonRpcMessage {
  match item {
    Request(request) => @jsonrpc.JsonRpcMessage::request(request)
    Notification(notification) =>
      @jsonrpc.JsonRpcMessage::notification(notification)
    InvalidItem(invalid) => @jsonrpc.JsonRpcMessage::response(invalid.response)
  }
}

///|
fn experimental_v2_batch_invalid_item(
  cause : @jsonrpc.JsonRpcCodecError,
) -> ExperimentalV2BatchItem {
  InvalidItem({
    cause,
    response: experimental_v2_batch_single_error(
      @jsonrpc.JsonRpcError::invalid_request(),
    ),
  })
}

///|
fn experimental_v2_batch_single_error(
  error : @jsonrpc.JsonRpcError,
) -> @jsonrpc.JsonRpcResponse {
  @jsonrpc.JsonRpcResponse::error(id=Null, error~)
}
