///|
/// Decode, encode, decode the encoding again, and require both decoded values
/// to be equal.  Key-order differences in the encoding can therefore never
/// mask a field loss.  Returns the first decode for further assertions.
fn[T : Eq + Debug] model_test_round_trip(
  source : String,
  decode : (Json) -> T raise ExperimentalV2DecodeError,
  encode : (T) -> Json raise ExperimentalV2DecodeError,
) -> T raise {
  let first = decode(experimental_v2_parse_json(source))
  let second = decode(encode(first))
  assert_eq(first, second)
  first
}

///|
/// Parse one JSON object fixture into its fields.
fn model_test_fields(
  source : String,
) -> Map[String, Json] raise ExperimentalV2DecodeError {
  experimental_v2_require_object(
    experimental_v2_parse_json(source),
    path="fixture",
  )
}
