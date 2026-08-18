///|
test "v2 diff round-trips mixed known operations with file types" {
  let decoded = model_test_round_trip(
    "{\"changes\":[{\"operation\":\"add\",\"path\":\"/tmp/new.txt\",\"fileType\":\"text\",\"mimeType\":\"text/plain\"},{\"operation\":\"delete\",\"path\":\"/tmp/old.bin\",\"fileType\":\"binary\"},{\"operation\":\"modify\",\"path\":\"/tmp/mod\"},{\"operation\":\"move\",\"oldPath\":\"/tmp/a\",\"path\":\"/tmp/b\",\"fileType\":\"_virtual\"},{\"operation\":\"copy\",\"oldPath\":\"/tmp/c\",\"path\":\"/tmp/d\",\"fileType\":\"weird\"}],\"patch\":{\"format\":\"git_patch\",\"text\":\"diff --git a/x b/x\"},\"_meta\":{\"d\":1}}",
    value => experimental_v2_decode_diff(value),
    experimental_v2_encode_diff,
  )
  guard decoded.changes[0] is Known(ChangeAdd(change)) else {
    fail("expected a known add change")
  }
  assert_eq(change.path, "/tmp/new.txt")
  assert_true(change.file_type is Some(DiffFileTypeText))
  guard decoded.changes[3] is Known(ChangeMove(moved)) else {
    fail("expected a known move change")
  }
  assert_eq(moved.old_path, "/tmp/a")
  assert_true(moved.file_type is Some(DiffFileTypeExtension(tag="_virtual")))
  guard decoded.changes[4] is Known(ChangeCopy(copy)) else {
    fail("expected a known copy change")
  }
  assert_true(copy.file_type is Some(DiffFileTypeFuture(raw="weird")))
  guard decoded.patch is Some(patch) else { fail("expected a decoded patch") }
  assert_true(patch.format is DiffPatchFormatGitPatch)
}

///|
test "v2 diff op required-field matrix rejects missing and extra fields" {
  let cases : Array[(String, ExperimentalV2DecodeError)] = [
    (
      "{\"changes\":[{\"operation\":\"modify\"}]}",
      MissingField(path="diff.changes[0].path"),
    ),
    (
      "{\"changes\":[{\"operation\":\"add\"}]}",
      MissingField(path="diff.changes[0].path"),
    ),
    (
      "{\"changes\":[{\"operation\":\"delete\"}]}",
      MissingField(path="diff.changes[0].path"),
    ),
    (
      "{\"changes\":[{\"operation\":\"move\",\"path\":\"/tmp/b\"}]}",
      MissingField(path="diff.changes[0].oldPath"),
    ),
    (
      "{\"changes\":[{\"operation\":\"copy\",\"oldPath\":\"/tmp/a\"}]}",
      MissingField(path="diff.changes[0].path"),
    ),
    (
      "{\"changes\":[{\"operation\":\"add\",\"path\":\"/tmp/a\",\"oldPath\":\"/tmp/b\"}]}",
      UnknownField(path="diff.changes[0].oldPath"),
    ),
    (
      "{\"changes\":[{\"operation\":\"move\",\"oldPath\":\"/tmp/a\",\"path\":\"/tmp/b\",\"extra\":1}]}",
      UnknownField(path="diff.changes[0].extra"),
    ),
    (
      "{\"changes\":[{\"path\":\"/tmp/a\"}]}",
      MissingField(path="diff.changes[0].operation"),
    ),
    (
      "{\"changes\":[{\"operation\":\"modify\",\"path\":\"relative/path\"}]}",
      InvalidPath(path="diff.changes[0].path", value="relative/path"),
    ),
    ("{}", MissingField(path="diff.changes")),
  ]
  for entry in cases {
    let (source, expected) = entry
    try experimental_v2_decode_diff(experimental_v2_parse_json(source)) catch {
      error => assert_eq(error, expected)
    } noraise {
      _ => fail("expected a typed failure for a malformed diff")
    }
  }
}

///|
test "v2 diff patch is optional null equals omitted and formats stay open" {
  assert_true(
    experimental_v2_decode_diff(experimental_v2_parse_json("{\"changes\":[]}")).patch
    is None,
  )
  assert_true(
    experimental_v2_decode_diff(
      experimental_v2_parse_json("{\"changes\":[],\"patch\":null}"),
    ).patch
    is None,
  )
  let extension = model_test_round_trip(
    "{\"changes\":[],\"patch\":{\"format\":\"_vendor\",\"text\":\"x\"}}",
    value => experimental_v2_decode_diff(value),
    experimental_v2_encode_diff,
  )
  assert_true(
    extension.patch
    is Some({ format: DiffPatchFormatExtension(tag="_vendor"), .. }),
  )
  let future = model_test_round_trip(
    "{\"changes\":[],\"patch\":{\"format\":\"ndiff\",\"text\":\"y\"}}",
    value => experimental_v2_decode_diff(value),
    experimental_v2_encode_diff,
  )
  assert_true(
    future.patch is Some({ format: DiffPatchFormatFuture(raw="ndiff"), .. }),
  )
  try
    experimental_v2_decode_diff(
      experimental_v2_parse_json(
        "{\"changes\":[],\"patch\":{\"format\":\"git_patch\"}}",
      ),
    )
  catch {
    error => assert_eq(error, MissingField(path="diff.patch.text"))
  } noraise {
    _ => fail("expected MissingField for a patch without text")
  }
}

///|
test "v2 diff change open fallback preserves unknown operations raw" {
  let extension = model_test_round_trip(
    "{\"changes\":[{\"operation\":\"_link\",\"path\":\"/tmp/a\",\"target\":\"/tmp/b\"}]}",
    value => experimental_v2_decode_diff(value),
    experimental_v2_encode_diff,
  )
  assert_true(extension.changes[0] is Extension(tag="_link", ..))
  let future = model_test_round_trip(
    "{\"changes\":[{\"operation\":\"chmod\",\"mode\":493}]}",
    value => experimental_v2_decode_diff(value),
    experimental_v2_encode_diff,
  )
  assert_true(future.changes[0] is Future(tag="chmod", ..))
}
