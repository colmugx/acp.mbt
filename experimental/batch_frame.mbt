///|
/// Frame-level result of splitting one newline-delimited v2 wire frame for a
/// peer whose engine consumes single-object frames only (the shared engine
/// rejects arrays at `@jsonrpc.jsonrpc_decode_json`, and that v1 behavior is
/// frozen).  Every case is total: faults carry the reply the v2 batch rules
/// require instead of an exception.
///
/// Unlike `experimental_v2_batch_decode`, which models client-to-agent
/// request/notification batches only, this splitter accepts `Response`
/// entries too: an agent-to-client batch reply is an array of response
/// objects, and a frame-level adapter must expand both directions.
pub(all) enum ExperimentalV2WireFrameSplit {
  /// The frame parsed to a non-array value; hand the original frame to the
  /// per-object codec unchanged.
  SplitLoneObject(value~ : Json)
  /// Unparseable JSON (-32700) or an empty array (-32600): the single
  /// id-null error-response object frame the v2 batch rules require a peer to
  /// send instead of an array.
  SplitSingleErrorReply(frame~ : String)
  /// A non-empty array: one re-encoded object frame per entry, in wire order.
  /// An entry that fails the envelope codec contributes its per-entry -32600
  /// id-null error-response frame in place; `intact` is true only when every
  /// entry decoded.
  SplitBatchFrames(frames~ : Array[String], intact~ : Bool)
} derive(Eq, Debug)

///|
/// Split one v2 wire frame into single-object frames a per-object engine can
/// admit.  Pure and total: unparseable frames and empty arrays return their
/// single error-reply frame, invalid array entries return their per-entry
/// -32600 frames with `intact` false, and non-array frames return their
/// parsed value for the caller's per-object codec.
pub fn experimental_v2_split_wire_frame(
  frame : String,
) -> ExperimentalV2WireFrameSplit {
  let value = @json.parse(frame) catch {
    _ =>
      return SplitSingleErrorReply(
        frame=experimental_v2_wire_error_frame(
          @jsonrpc.JsonRpcError::parse_error(),
        ),
      )
  }
  match value {
    Array(items) =>
      if items.length() == 0 {
        SplitSingleErrorReply(
          frame=experimental_v2_wire_error_frame(
            @jsonrpc.JsonRpcError::invalid_request(),
          ),
        )
      } else {
        let frames : Array[String] = []
        let mut intact = true
        for item in items {
          match experimental_v2_wire_entry_frame(item) {
            Some(text) => frames.push(text)
            None => {
              intact = false
              frames.push(
                experimental_v2_wire_error_frame(
                  @jsonrpc.JsonRpcError::invalid_request(),
                ),
              )
            }
          }
        }
        SplitBatchFrames(frames~, intact~)
      }
    _ => SplitLoneObject(value~)
  }
}

///|
/// Frame-level reply batching: collect already-encoded single-response
/// frames (for example the per-frame replies an engine emitted) into one
/// batch reply line with no framing newline.  Order is the caller's choice;
/// any order is a legal reply.  An empty input is a caller error
/// (notification-only batches get no reply at all), and a frame that is not a
/// lone response is a typed per-index failure.
pub fn experimental_v2_collect_replies(
  frames : Array[String],
) -> String raise ExperimentalV2BatchEncodeError {
  if frames.length() == 0 {
    raise EmptyResponsesInput
  }
  let responses : Array[@jsonrpc.JsonRpcResponse] = []
  for index, frame in frames {
    let message = @jsonrpc.jsonrpc_decode(frame) catch {
      cause => raise ReplyFrameDecodeFailed(index~, cause~)
    }
    match message {
      Response(response) => responses.push(response)
      _ =>
        raise ReplyFrameDecodeFailed(
          index~,
          cause=InvalidRequest(reason="reply frames must be single responses"),
        )
    }
  }
  experimental_v2_batch_responses_encode(responses)
}

///|
fn experimental_v2_wire_entry_frame(item : Json) -> String? {
  let message = @jsonrpc.jsonrpc_decode_json(item) catch { _ => return None }
  let text = @jsonrpc.jsonrpc_encode(message) catch { _ => return None }
  Some(text)
}

///|
fn experimental_v2_wire_error_frame(error : @jsonrpc.JsonRpcError) -> String {
  try! @jsonrpc.jsonrpc_encode(
    @jsonrpc.JsonRpcMessage::response(experimental_v2_batch_single_error(error)),
  )
}
