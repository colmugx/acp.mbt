///|
/// Batch→object expansion state for one wrapped reader port.  The framing
/// state covers the ORIGINAL byte stream; `pending` holds rewritten
/// newline-delimited bytes the engine has not consumed yet.  The engine keeps
/// framing the REWRITTEN stream with its own decoder, which is well-formed by
/// construction, so no framing state is duplicated onto the same bytes.
priv struct ExperimentalV2BatchExpandingReader {
  inner : @runtime.RuntimeReaderPort
  mut framing : @transport.FramingState
  mut pending : Bytes
  mut eof : Bool
}

///|
/// Wrap one reader port so the engine behind it never sees a v2 batch frame.
/// The wrapper owns a framing buffer over the original byte stream, rewrites
/// each COMPLETE frame with `experimental_v2_split_wire_frame`, and re-serializes
/// the result as newline-delimited bytes: an intact batch becomes one object
/// line per entry, in order, and everything else — lone objects, unparseable
/// frames, empty arrays, batches with invalid entries — passes through
/// byte-exact so the engine's own per-object decode keeps owning fault policy
/// (fail-fast close, exactly as without the wrapper).
///
/// The wrapper therefore never synthesizes wire output.  The v2 batch rules'
/// single -32700/-32600 error replies for fault batches would have to be
/// written on the engine's serial writer, which a reader-side port cannot
/// reach without breaking the single-writer discipline; peers and proxies
/// that must answer fault batches use the pure
/// `experimental_v2_split_wire_frame` helper instead.
///
/// Chunking is transparent: reads may split frames anywhere, a read never
/// returns an empty chunk, and EOF is forwarded only after `pending` is
/// drained and the original stream ended on a frame boundary.  Framing faults
/// (empty frame line, invalid UTF-8, oversized frame, partial final line)
/// raise out of `read`, which the engine settles as its reader-failure close;
/// without the wrapper the same bytes would close through the engine's own
/// framing path with the same fail-fast outcome.
pub fn experimental_v2_batch_expanding_reader(
  reader~ : @runtime.RuntimeReaderPort,
  max_frame_bytes~ : Int,
) -> @runtime.RuntimeReaderPort {
  if max_frame_bytes <= 0 {
    abort("v2 batch expanding reader: max_frame_bytes must be positive")
  }
  let state : ExperimentalV2BatchExpandingReader = {
    inner: reader,
    framing: try! @transport.framing_state(max_frame_bytes~),
    pending: b"",
    eof: false,
  }
  { read: count => experimental_v2_batch_expanding_read(state, count) }
}

///|
/// Wrap the reader of one ports value for v2 batch expansion, leaving the
/// writer, handlers, and trace seams untouched.  This is the composition seam
/// for callers that own explicit `RuntimePorts`; the v2 runners offer the
/// same effect through their `batch` option.
pub fn experimental_v2_batch_expanding_ports(
  ports~ : @runtime.RuntimePorts,
  options~ : @runtime.RuntimeOptions,
) -> @runtime.RuntimePorts {
  {
    ..ports,
    reader: experimental_v2_batch_expanding_reader(
      reader=ports.reader,
      max_frame_bytes=options.max_frame_bytes,
    ),
  }
}

///|
async fn experimental_v2_batch_expanding_read(
  state : ExperimentalV2BatchExpandingReader,
  count : Int,
) -> Bytes? {
  for ;; {
    if state.pending.length() > 0 {
      let take = if count < state.pending.length() {
        count
      } else {
        state.pending.length()
      }
      let chunk = state.pending.view(start=0, end=take).to_owned()
      state.pending = state.pending
        .view(start=take, end=state.pending.length())
        .to_owned()
      return Some(chunk)
    }
    if state.eof {
      return None
    }
    match (state.inner.read)(count) {
      None => {
        let _ = @transport.framing_finish(state.framing)
        state.eof = true
      }
      Some(chunk) => {
        let step = @transport.framing_feed(state.framing, chunk)
        state.framing = step.state
        for frame in step.frames {
          state.pending = Bytes::add(
            state.pending,
            @utf8.encode(experimental_v2_batch_expand_frame(frame) + "\n"),
          )
        }
      }
    }
  }
}

///|
/// Rewrite one complete frame as newline-delimited object-frame text with no
/// trailing newline.  Only an intact batch is rewritten; every other shape
/// returns the original frame text unchanged.
fn experimental_v2_batch_expand_frame(frame : String) -> String {
  match experimental_v2_split_wire_frame(frame) {
    SplitBatchFrames(frames~, intact~) =>
      if intact {
        frames.join("\n")
      } else {
        frame
      }
    SplitLoneObject(..) | SplitSingleErrorReply(..) => frame
  }
}
