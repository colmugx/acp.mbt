# 04 Agent endpoint

## 定位

本章面向 Agent 实现者：用一次性 constructor 组合 required/optional service，
从 `AgentSpec` 派生 capability，再得到不携带 connection state 的 `AgentEndpoint`。
这里的 endpoint 是 typed application surface，不是监听中的网络 server。

## 前置

完成 [03 ACP codecs 与 method manifest](03-acp-codecs-and-methods.md)。准备
`Implementation`、`AgentContext` 和 session handler。所有 handler 都是 immutable
async function；没有 builder、注册表、global 或 service locator。

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
async fn new_session(
  _context : @acp.AgentContext,
  _params : @acp.NewSessionParams,
) -> @acp.NewSessionResult {
  {
    session_id: "session-1",
    modes: @acp.ProtocolNullable::Omitted,
    config_options: @acp.ProtocolNullable::Omitted,
    meta: @acp.ProtocolNullable::Omitted,
  }
}

async fn prompt(
  _context : @acp.AgentContext,
  _params : @acp.PromptParams,
) -> @acp.PromptResult {
  {
    stop_reason: @acp.StopReason::EndTurn,
    meta: @acp.ProtocolNullable::Omitted,
  }
}

async fn cancel(
  _context : @acp.AgentContext,
  _params : @acp.CancelParams,
) -> Unit {
  ()
}

fn make_agent() {
  let sessions = @acp.agent_session_service(
    new_session=new_session,
    prompt=prompt,
    cancel=cancel,
  )
  let spec = @acp.agent_spec(
    info={
      name: "example-agent",
      title: @acp.ProtocolNullable::Omitted,
      version: "0.1.0",
      meta: @acp.ProtocolNullable::Omitted,
    },
    sessions=sessions,
    support=@acp.agent_support(),
  ).unwrap()
  @acp.agent_endpoint_from_spec(spec)
}
```

required callbacks 的组合和 capability 派生已有测试证据：
[`agent/service_test.mbt`](../../agent/service_test.mbt) 第 102-130、134-237 行；
endpoint handler/error 边界见 [`agent/endpoint_test.mbt`](../../agent/endpoint_test.mbt)
第 28-150 行。真实应用应将自己的 immutable context broker 传给 handler，见
[06 Reader 与 context](06-reader-and-context.md)。

## 错误边界

`agent_spec` 会拒绝空 implementation；`agent_auth_service` 会拒绝空或重复 auth
method；缺少 optional handler 时 endpoint 抛出 `UnavailableOperation`，不会静默
降级。handler 的普通异常在 endpoint 边界归一为 `HandlerError`。

## 下一篇

继续阅读 [05 Client endpoint](05-client-endpoint.md)，了解对称的 Client service
和 capability 组合。
