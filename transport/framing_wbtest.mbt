///|
test "framing preserves chunks, multiple lines, CRLF, and noise" {
  let initial = framing_state(max_frame_bytes=128)
  let first = framing_feed(initial, b"{\"text\":")
  assert_eq(first.frames, [])
  assert_eq(first.state.pending, b"{\"text\":")
  let second = framing_feed(first.state, b"\"中文\"}\nnoise\r\n")
  assert_eq(second.frames, ["{\"text\":\"中文\"}", "noise"])
  assert_eq(second.state.pending, b"")
  let finished = framing_finish(second.state)
  assert_eq(finished.frames, [])
  assert_true(finished.state.closed)
}

///|
test "framing handles UTF-8 code points split across chunks" {
  let encoded = @utf8.encode("中\n")
  let first = framing_feed(
    framing_state(max_frame_bytes=16),
    encoded.view(start=0, end=1).to_owned(),
  )
  let second = framing_feed(
    first.state,
    encoded.view(start=1, end=encoded.length()).to_owned(),
  )
  assert_eq(second.frames, ["中"])
}

///|
test "framing rejects empty lines, invalid UTF-8, and oversized frames" {
  try framing_feed(framing_state(max_frame_bytes=8), b"\n") catch {
    EmptyFrame => ()
    _ => fail("expected empty frame failure")
  } noraise {
    _ => fail("expected empty frame to fail")
  }
  let invalid : Bytes = [0xff, b'\n']
  try framing_feed(framing_state(max_frame_bytes=8), invalid) catch {
    InvalidUtf8 => ()
    _ => fail("expected invalid UTF-8 failure")
  } noraise {
    _ => fail("expected invalid UTF-8 to fail")
  }
  try framing_feed(framing_state(max_frame_bytes=3), b"abcd\n") catch {
    FrameTooLarge(limit=3, actual=4) => ()
    _ => fail("expected oversized frame failure")
  } noraise {
    _ => fail("expected oversized frame to fail")
  }
}

///|
test "framing reports partial EOF and rejects use after close" {
  let step = framing_feed(framing_state(max_frame_bytes=32), b"partial")
  try framing_finish(step.state) catch {
    UnexpectedEof => ()
    _ => fail("expected partial EOF failure")
  } noraise {
    _ => fail("expected partial EOF to fail")
  }
  let closed = framing_finish(framing_state(max_frame_bytes=32))
  try framing_feed(closed.state, b"late\n") catch {
    Closed => ()
    _ => fail("expected closed decoder failure")
  } noraise {
    _ => fail("expected use after close to fail")
  }
}
