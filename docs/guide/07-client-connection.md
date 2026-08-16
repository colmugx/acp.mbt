# 07 ClientConnection：typed broker facade

## 定位

`ClientConnection` 是一个 caller-injected typed request/notification broker
facade。它负责把每个稳定 method 映射到正确的 typed `ClientReply`，检查
initialize v1 和 reply variant；它不是 socket、stdio 或 connection runtime
runner，也不保存 request-id table、queue 或 task。

## 前置

完成 [03 ACP codecs 与 method manifest](03-acp-codecs-and-methods.md) 和
[06 Reader 与 context](06-reader-and-context.md)。准备一个由 composition root
拥有的 `ClientRequestBroker` 与 `ClientNotificationBroker`。

当前 module version 是 `0.1.0`，但尚未发布稳定 release；请按根
[README](../../README.mbt.md) 的依赖说明准备 package。仓库内开发直接引用本
module，并在使用方 package 的 `moon.pkg` 中写：

```text
import {
  "colmugx/acp"
}
```

源码使用默认 alias `@acp`。

## 可复制用法

```mbt nocheck
async fn request_broker(
  request : @acp.AgentRequest,
) -> Result[@acp.ClientReply, @acp.ClientConnectionError] {
  match request {
    @acp.AgentRequest::Initialize(_) => Ok(@acp.ClientReply::ClientReplyInitialize({
      protocol_version: 1,
      agent_capabilities: @acp.ProtocolNullable::Omitted,
      auth_methods: @acp.ProtocolNullable::Omitted,
      agent_info: @acp.ProtocolNullable::Omitted,
      meta: @acp.ProtocolNullable::Omitted,
    }))
    _ => Err(@acp.ClientConnectionError::ClientConnectionUnavailable(
      method_name=request.method_name(),
    ))
  }
}

fn notification_broker(
  _notification : @acp.AgentNotification,
) -> Result[Unit, @acp.ClientConnectionError] {
  Ok(())
}

fn make_connection() {
  @acp.client_connection(request_broker~, notification_broker~)
}
```

逐个 stable request 的 typed reply 证据见
[`client/connection_test.mbt`](../../client/connection_test.mbt) 第 248-284 行；
mismatch、unavailable、cancellation 和 broker failure 见第 295-444 行。

## 错误边界

`ClientConnectionReplyMismatch`、`ClientConnectionUnsupportedVersion`、
`ClientConnectionUnavailable`、`ClientConnectionCancelled` 和
`ClientConnectionBrokerFailure` 都必须显式向调用者传播。成功返回只表示
typed broker 返回了匹配值，不表示任何 bytes 已写入 peer。

`cancel` 与 `cancel_request` 只发出 typed notification intent；真正的取消、
相关 task 和 transport 仍由外层 runtime 决定。

## 下一篇

继续阅读 [08 Runtime ports 与真实运行入口](08-runtime-ports.md)，了解
`client_connection_over_channel` 如何把该 facade 接到真实 engine，以及 stdio/process
运行入口的边界。
