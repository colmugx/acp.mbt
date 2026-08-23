///|
fn batch_expand_test_chunk(text : String) -> Bytes? {
  Some(@utf8.encode(text))
}

///|
/// Drain one reader port fully, reading in tiny chunks so the wrapper's
/// pending-byte slicing is exercised, and return the decoded stream text.
async fn batch_expand_test_drain(reader : @runtime.RuntimeReaderPort) -> String {
  let collected = StringBuilder()
  for ;; {
    match (reader.read)(3) {
      None => return collected.to_string()
      Some(chunk) => collected.write_string(@utf8.decode(chunk.view()))
    }
  }
}

///|
async test "v2 batch expanding reader rewrites intact batches and passes lone frames" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  // The stream splits the lone frame and the batch across chunk boundaries so
  // the wrapper's internal framing buffer is load-bearing.
  input.put(batch_expand_test_chunk("{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"met"))
  input.put(
    batch_expand_test_chunk(
      "hod\":\"m\"}\n[{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"},{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"r1\"}}]\n{\"jsonrpc\":\"2.0\",\"method\":\"n\"}\n",
    ),
  )
  input.put(None)
  let reader = experimental_v2_batch_expanding_reader(
    reader={ read: _ => input.get() },
    max_frame_bytes=1024 * 1024,
  )
  let drained = batch_expand_test_drain(reader)
  assert_eq(
    drained, "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"m\"}\n{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"session/list\"}\n{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"r1\"}}\n{\"jsonrpc\":\"2.0\",\"method\":\"n\"}\n",
  )
}

///|
async test "v2 batch expanding reader passes fault batches byte-exact" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  input.put(
    batch_expand_test_chunk(
      "[]\n[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session/list\"},\"junk\"]\n[{\"jsonrpc\"\n",
    ),
  )
  input.put(None)
  let reader = experimental_v2_batch_expanding_reader(
    reader={ read: _ => input.get() },
    max_frame_bytes=1024 * 1024,
  )
  let drained = batch_expand_test_drain(reader)
  // Empty array, invalid-entry batch, and truncated batch JSON all pass
  // through unchanged: the engine's per-object decode keeps fault policy.
  assert_eq(
    drained, "[]\n[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session/list\"},\"junk\"]\n[{\"jsonrpc\"\n",
  )
}

///|
async test "v2 batch expanding reader raises on a partial final line" {
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  input.put(batch_expand_test_chunk("{\"jsonrpc\":\"2.0\",\"id\":1"))
  input.put(None)
  let reader = experimental_v2_batch_expanding_reader(
    reader={ read: _ => input.get() },
    max_frame_bytes=1024 * 1024,
  )
  let raised : Array[Unit] = []
  try {
    let _ = batch_expand_test_drain(reader)
    ()
  } catch {
    _ => raised.push(())
  }
  assert_eq(raised.length(), 1)
}

///|
/// The runner-level integration proof: one batched frame carrying an
/// `initialize` request plus a benign `$/cancel_request` notification is
/// expanded before the shared engine, both entries are processed in order,
/// exactly one response is written, and the connection still ends cleanly on
/// EOF.
async test "v2 agent runner over batch expanding ports processes batched entries" {
  let endpoint = experimental_v2_agent_test_endpoint()
  let input : @aqueue.Queue[Bytes?] = Queue(kind=Unbounded)
  let output : Array[Bytes] = []
  let written : @aqueue.Queue[Unit] = Queue(kind=Unbounded)
  let traces : Array[@runtime.RuntimeTraceEvent] = []
  let responses : Array[String] = []
  let failures : Array[
    (@jsonrpc.RequestId, @runtime.RuntimeOutboundFailureKind),
  ] = []
  let ports = experimental_v2_batch_expanding_ports(
    ports=experimental_v2_runtime_test_ports(
      input, output, written, traces, responses, failures,
    ),
    options=@runtime.runtime_default_options(),
  )
  input.put(
    batch_expand_test_chunk(
      "[{\"jsonrpc\":\"2.0\",\"id\":\"init\",\"method\":\"initialize\",\"params\":{\"protocolVersion\":2,\"info\":{\"name\":\"client\",\"version\":\"1\"},\"capabilities\":{}}},{\"jsonrpc\":\"2.0\",\"method\":\"$/cancel_request\",\"params\":{\"requestId\":\"gone\"}}]\n",
    ),
  )
  input.put(None)
  @async.with_task_group(group => {
    group
    .spawn(() => {
      experimental_v2_agent_runtime_run(
        endpoint~,
        context=experimental_v2_agent_fail_fast_context(),
        initial_state=experimental_v2_agent_test_adapter_state(endpoint),
        ports~,
        options=@runtime.runtime_default_options(),
      )
    })
    .wait()
  })
  assert_eq(output.length(), 1)
  assert_eq(experimental_v2_runtime_test_success_id(output[0]), String("init"))
  assert_eq(failures.length(), 0)
}
