///|
/// Errors raised by the newline-delimited transport boundary.
///
/// Framing deliberately does not parse JSON.  Every non-empty line is emitted
/// as a UTF-8 frame so that transport noise cannot be silently discarded; the
/// JSON-RPC codec remains the next, explicit validation step.
pub(all) suberror FramingError {
  InvalidMaxFrameSize
  Closed
  EmptyFrame
  InvalidUtf8
  FrameTooLarge(limit~ : Int, actual~ : Int)
  UnexpectedEof
} derive(Eq, Debug)

///|
/// Immutable state for a newline-delimited decoder.
pub(all) struct FramingState {
  pending : Bytes
  max_frame_bytes : Int
  closed : Bool
} derive(Eq, Debug)

///|
/// Frames emitted by one feed operation and the state for the next operation.
pub(all) struct FramingStep {
  state : FramingState
  frames : Array[String]
} derive(Eq, Debug)

///|
/// Create a decoder with a positive maximum payload size in bytes.
#warnings("-unused_value")
pub fn framing_state(max_frame_bytes~ : Int) -> FramingState raise FramingError {
  if max_frame_bytes <= 0 {
    raise InvalidMaxFrameSize
  }
  { pending: b"", max_frame_bytes, closed: false }
}

///|
/// Feed an arbitrary byte chunk.  A chunk may contain partial or multiple
/// frames.  CRLF is accepted by removing the CR immediately before LF.
#warnings("-unused_value")
pub fn framing_feed(
  state : FramingState,
  chunk : Bytes,
) -> FramingStep raise FramingError {
  if state.closed {
    raise Closed
  }
  let combined = Bytes::add(state.pending, chunk)
  let frames : Array[String] = []
  let mut line_start = 0
  for index, byte in combined.iter2() {
    if byte == b'\n' {
      let mut line_end = index
      if index > line_start && combined[index - 1] == b'\r' {
        line_end = index - 1
      }
      let line_length = line_end - line_start
      if line_length == 0 {
        raise EmptyFrame
      }
      if line_length > state.max_frame_bytes {
        raise FrameTooLarge(limit=state.max_frame_bytes, actual=line_length)
      }
      let line = combined.view(start=line_start, end=line_end)
      let text = @utf8.decode(line) catch { _ => raise InvalidUtf8 }
      frames.push(text)
      line_start = index + 1
    }
  }
  let pending_length = combined.length() - line_start
  if pending_length > state.max_frame_bytes {
    raise FrameTooLarge(limit=state.max_frame_bytes, actual=pending_length)
  }
  let pending = combined
    .view(start=line_start, end=combined.length())
    .to_owned()
  { state: { ..state, pending, }, frames }
}

///|
/// Finish the stream.  A partial line is never silently discarded.
#warnings("-unused_value")
pub fn framing_finish(state : FramingState) -> FramingStep raise FramingError {
  if state.closed {
    raise Closed
  }
  if !state.pending.is_empty() {
    raise UnexpectedEof
  }
  { state: { ..state, closed: true }, frames: [] }
}
