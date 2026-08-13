# 06 Reader 与 context

## 定位

composition root 负责把 caller-owned environment 投影成一次性 immutable
`AgentSpec`/`ClientSpec`。`client_program` 和 `client_program_from` 提供 Reader
组合 seam；`AgentContext` 则把 typed request/notification broker 作为闭包传给
一次 Agent invocation。它们都不保存 connection state。

## 前置

完成 [04 Agent endpoint](04-agent-endpoint.md) 和 [05 Client endpoint](05-client-endpoint.md)。
理解 async callback、`Result` 和依赖注入即可。

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
struct Environment {
  client_spec : @acp.ClientSpec
}

fn client_program_for(environment : Environment) {
  @acp.client_program_from(fn(env : Environment) {
    Ok(env.client_spec)
  })
}

async fn request_broker(
  request : @acp.ClientRequest,
) -> Result[@acp.AgentOutboundReply, @acp.AgentContextError] {
  // 在 composition root 注入 caller-owned typed transport。
  Err(@acp.AgentContextError::AgentContextUnavailable(
    method_name=request.method_name(),
  ))
}

async fn notification_broker(
  _notification : @acp.ClientNotification,
) -> Result[Unit, @acp.AgentContextError] {
  Ok(())
}

fn context_for_invocation() {
  @acp.agent_context(
    request_broker~,
    notification_broker~,
  )
}
```

`AgentContext` 的 request/notification 方法和 typed reply mismatch 证据见
[`agent/context_test.mbt`](../../agent/context_test.mbt) 第 184-244 行；其错误
归一和 cancellation 证据见第 279-420 行。Reader endpoint 隔离见
[`client/endpoint_test.mbt`](../../client/endpoint_test.mbt) 第 107-140 行。

实际 `Reader::run` 属于调用方使用的 Reader 依赖；本指南不把它伪装成 ACP
connection runner。每次 composition 应产生独立 endpoint，不使用 Ref、global
或 service locator。

## 错误边界

broker 应返回 `AgentContextError`；错误包括 unavailable、cancelled、broker
failure 和 typed reply mismatch。普通异常不能把秘密 payload 穿过 facade，
也不能被吞成 `Ok(())`。

## 下一篇

继续阅读 [07 ClientConnection](07-client-connection.md)，看 typed broker 如何
包住 Client-to-Agent 请求，但不拥有 transport 生命周期。
