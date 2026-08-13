# 08 Runtime ports：native seam，不是 server

## 定位

`RuntimeReaderPort`、`RuntimeWriterPort`、`RuntimeHandlerPort`、`RuntimePorts` 和
`RuntimeOptions` 描述调用方提供给 native runtime 的 immutable ports/config。它们
用于依赖注入、测试 fault/backpressure 和 trace；当前不等于一个已经完成的
server runner。

## 前置

完成 [01 Quickstart](01-quickstart.md) 和 [07 ClientConnection](07-client-connection.md)。
需要理解 `async` callback、`Bytes` 和结构化 `RuntimeError`。

当前 module version 是 `0.1.0`，但尚未发布稳定 release；请按根
[README](../../README.mbt.md) 的依赖说明准备 package。仓库内开发直接引用本
module，并在使用方 package 的 `moon.pkg` 中写：

```text
import {
  "colmugx/acp"
  "moonbitlang/core/json" @json
}
```

源码使用默认 alias `@acp` 和 `@json`。

## 可复制用法

```mbt nocheck
fn make_ports() -> @acp.RuntimePorts raise @acp.RuntimeError {
  let handlers : @acp.RuntimeHandlerPort = {
    request: async fn(_request) {
      @acp.RuntimeHandlerResult::HandlerSuccess(@json.Json::null())
    },
    notification: async fn(_notification) { () },
    response: async fn(_response) { () },
    outbound_failure: None,
  }
  let options = @acp.runtime_default_options()
  @acp.runtime_validate_options(options)
  let reader : @acp.RuntimeReaderPort = {
    read: async fn(_max_len) { None },
  }
  let writer : @acp.RuntimeWriterPort = {
    write: async fn(_frame) { () },
  }
  {
    reader,
    writer,
    handlers,
    cancel_outbound: None,
    trace: _event => (),
  }
}
```

`runtime_default_options` 与 option validation 的根 facade 证据见
[`facade_test.mbt`](../../facade_test.mbt) 第 39-40 行；端口和错误类别的公开
定义见 [`runtime/ports.mbt`](../../runtime/ports.mbt) 第 19-168 行。

## 错误边界

无效 bounds、reader/writer 关闭或 backpressure、framing/codec/reducer/task
失败都应成为 `RuntimeError` 或 trace；trace 只能使用 redacted routing metadata。
`RuntimePorts.trace` 不应写 stdout，协议 stdout 只能承载 ACP JSON-RPC frames。

transport package 中的 `stdio_transport` 当前没有从 root facade 导出；即便直接
看到该 package，也不能据此宣称 `serve_stdio` 或完整 stdio lifecycle 已完成。

## 下一篇

继续阅读 [09 错误、取消与 capabilities](09-errors-cancellation-capabilities.md)，
统一理解结构化失败和 capability 派生。
