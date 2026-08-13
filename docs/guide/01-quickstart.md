# 01 Quickstart：第一个 JSON-RPC frame

## 定位

本章用一个最小例子串起 ACP SDK 的三个纯边界：JSON-RPC message、JSON text
和 newline-delimited frame。它不会启动 server，也不会打开 stdin/stdout。

## 前置

需要 native MoonBit 项目。当前 module version 是 `0.1.0`，但尚未发布稳定
release；请按根 [README](../../README.mbt.md) 的依赖说明准备 package。仓库内
开发直接引用本 module，再在使用方 package 的 `moon.pkg` 中加入 ACP facade 和
core JSON：

```text
import {
  "colmugx/acp"
  "moonbitlang/core/json" @json
}
```

MoonBit 源码使用默认 alias `@acp`；`@json` 只是 MoonBit core 的 JSON 值构造器，因为 ACP
的 `JsonRpcRequest.params` 接受 core `Json`。

## 可复制示例

```mbt nocheck
fn quickstart() {
  let request = @acp.JsonRpcRequest::new(
    id=@acp.RequestId::String("quickstart"),
    method_name="initialize",
    params=@json.Json::object({
      "protocolVersion": @json.Json::number(1.0, repr="1"),
    }),
  )
  let message = @acp.JsonRpcMessage::request(request)
  let encoded = @acp.jsonrpc_encode(message)
  let decoded = @acp.jsonrpc_decode(encoded)
  assert_true(decoded is @acp.JsonRpcMessage::Request(_))

  let framed = @acp.framing_feed(
    @acp.framing_state(max_frame_bytes=128),
    b"{\"jsonrpc\":\"2.0\",\"method\":\"m\"}\n",
  )
  assert_eq(framed.frames.length(), 1)
}
```

这段不是 `docs/guide/` 自动测试；它的 message 构造、encode/decode 和 framing 断言分别对应根黑盒测试
[`facade_test.mbt`](../../facade_test.mbt) 第 3-11、39-45 行；测试证据目前
在根 package，而不是 `docs/guide/`。

`jsonrpc_encode` 返回不带换行的 JSON text；换行是 framing/transport 层的
职责。真实输入可能包含半帧或多帧，应重复调用 `framing_feed`，最后调用
`framing_finish`。

## 错误边界

- `jsonrpc_encode/decode` 失败是 `JsonRpcCodecError`，不能忽略。
- `framing_state/feed/finish` 失败是 `FramingError`，空行、超限、非法 UTF-8
  和不完整 EOF 都是可观察失败。
- 这个例子没有写 transport；不要把 `framing_feed` 当作 stdio server。

## 下一篇

继续阅读 [02 JSON-RPC 与 framing](02-jsonrpc-and-framing.md)，了解 ID、error
response 和 framing 的失败语义。
