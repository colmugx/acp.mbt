# 05 Client endpoint

## 定位

本章面向 Client 实现者：组合 baseline session service 与可选 filesystem、
terminal、elicitation service。`ClientEndpoint.capabilities()` 由 service
presence 派生，不再额外维护一份可能失真的 capability map。

## 前置

完成 [04 Agent endpoint](04-agent-endpoint.md)。需要提供
`ClientSessionService` 的两个 baseline callbacks；optional service 要么完整
构造，要么不传入。

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
async fn session_update(_params : @acp.SessionUpdateParams) -> Unit { () }

async fn request_permission(
  _request : @acp.RequestPermissionRequest,
) -> @acp.RequestPermissionResponse {
  {
    outcome: @acp.RequestPermissionOutcome::Cancelled,
    meta: @acp.ProtocolNullable::Omitted,
  }
}

fn make_client() {
  let session = @acp.client_session_service(
    session_update=session_update,
    request_permission=request_permission,
  )
  let spec = @acp.client_spec(
    info={
      name: "example-client",
      title: @acp.ProtocolNullable::Omitted,
      version: "0.1.0",
      meta: @acp.ProtocolNullable::Omitted,
    },
    session=session,
  ).unwrap()
  @acp.client_program_from(fn(_env : Unit) { Ok(spec) })
}
```

完整 optional services 的 constructor 和 capability 断言见
[`client/service_test.mbt`](../../client/service_test.mbt) 第 110-187 行、
[`client/endpoint_test.mbt`](../../client/endpoint_test.mbt) 第 107-161 行；所有
typed endpoint invocation 的调用形状见同文件第 163-253 行。

## 错误边界

空 filesystem service、缺少 elicitation completion、空 implementation 都是
结构化 `ClientCompositionError`。调用未配置的 optional operation 会抛出
`UnavailableOperation`；handler failure 会在 endpoint 边界归一为 `HandlerError`。

## 下一篇

继续阅读 [06 Reader 与 context](06-reader-and-context.md)，把 endpoint 组合和
caller-owned environment、Agent outbound context 连接起来。
