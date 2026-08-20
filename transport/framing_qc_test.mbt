///|
/// One generated decoder exercise: newline-free non-empty lines, plus one
/// cut flag per payload byte (consumed cyclically when the flag array is
/// shorter than the payload).  The same flags also pick each line's
/// terminator (`\r\n` or `\n`), so CRLF splitting across chunk boundaries is
/// exercised on the same cases.
struct FramingFeedCase {
  lines : Array[String]
  cuts : Array[Bool]
} derive(Debug)

///|
/// Strip CR/LF so the case's line structure is fully explicit, drop empty
/// lines, and keep at least one line so a case is never vacuous.
fn framing_qc_clean_lines(lines : Array[String]) -> Array[String] {
  let clean = []
  for line in lines {
    let kept = StringBuilder()
    for char in line {
      if char != '\n' && char != '\r' {
        kept.write_char(char)
      }
    }
    let filtered = kept.to_string()
    if filtered != "" {
      clean.push(filtered)
    }
  }
  if clean.is_empty() {
    ["acp"]
  } else {
    clean
  }
}

///|
impl @qc.Arbitrary for FramingFeedCase with fn arbitrary(size, rs) {
  let lines_source : @qc.Generator[Array[String]] = @qc.spawn()
  let cuts_source : @qc.Generator[Array[Bool]] = @qc.spawn()
  let lines = framing_qc_clean_lines(lines_source.run(size, rs))
  let cuts = cuts_source.run(size, rs)
  { lines, cuts }
}

///|
impl @shrink.Shrink for FramingFeedCase with fn shrink(self) {
  let variants : Array[FramingFeedCase] = []
  for lines in @shrink.Shrink::shrink(self.lines) {
    variants.push({ ..self, lines: framing_qc_clean_lines(lines) })
  }
  for cuts in @shrink.Shrink::shrink(self.cuts) {
    variants.push({ ..self, cuts, })
  }
  variants.iter()
}

///|
/// Encode the case into payload bytes, one terminated line after another.
fn framing_qc_payload(sample : FramingFeedCase) -> Bytes {
  let payload = StringBuilder()
  for index, line in sample.lines.iter2() {
    let terminator = if !sample.cuts.is_empty() &&
      sample.cuts[index % sample.cuts.length()] {
      "\r\n"
    } else {
      "\n"
    }
    payload.write_string(line)
    payload.write_string(terminator)
  }
  @utf8.encode(payload.to_string())
}

///|
/// Split the payload at the flagged byte positions; chunk count and sizes
/// are therefore as arbitrary as the cut flags.
fn framing_qc_chunks(sample : FramingFeedCase, payload : Bytes) -> Array[Bytes] {
  let chunks = []
  let mut start = 0
  for index in 0..<payload.length() {
    let cut = !sample.cuts.is_empty() &&
      sample.cuts[index % sample.cuts.length()]
    if cut && index + 1 < payload.length() {
      chunks.push(payload.view(start~, end=index + 1).to_owned())
      start = index + 1
    }
  }
  chunks.push(payload.view(start~, end=payload.length()).to_owned())
  chunks
}

///|
test "framing property: chunk boundaries never change decoded frames" {
  @qc.check(
    (sample : FramingFeedCase) => {
      let payload = framing_qc_payload(sample)
      let chunks = framing_qc_chunks(sample, payload)
      let mut state = framing_state(max_frame_bytes=payload.length())
      let frames = []
      for chunk in chunks {
        let step = framing_feed(state, chunk)
        state = step.state
        for frame in step.frames {
          frames.push(frame)
        }
      }
      // A completed stream must finish cleanly; a partial line would raise
      // UnexpectedEof and falsify the property.
      ignore(framing_finish(state))
      frames == sample.lines
    },
    count=300,
  )
}

///|
test "framing property: oversized frames are rejected under any chunking" {
  @qc.check(
    (sample : FramingFeedCase) => {
      // Guarantee one oversized line so every case must fail.
      let lines = ["0123456789abcdef"]
      for line in sample.lines {
        lines.push(line)
      }
      let oversized = { ..sample, lines, }
      let chunks = framing_qc_chunks(oversized, framing_qc_payload(oversized))
      try {
        let mut state = framing_state(max_frame_bytes=8)
        for chunk in chunks {
          let step = framing_feed(state, chunk)
          state = step.state
        }
        false
      } catch {
        FrameTooLarge(..) => true
        _ => false
      }
    },
    count=300,
  )
}
