# 09 错误、取消与 capabilities

## 定位

ACP 应把错误保留在正确边界：composition 错误在构造时失败，handler 错误在
endpoint 边界归一，typed broker 错误返回给调用者，runtime/transport 错误进入
显式错误和 redacted trace。capability 由实际 service presence 派生。

## 前置

完成 [04 Agent endpoint](04-agent-endpoint.md)、[05 Client endpoint](05-client-endpoint.md)
和 [08 Runtime ports](08-runtime-ports.md)。

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
fn classify(error : @acp.ClientCompositionError) {
  match error {
    @acp.ClientCompositionError::MissingRequiredService(service_name~) => service_name
    @acp.ClientCompositionError::ConflictingSupport(reason~) => reason
    @acp.ClientCompositionError::InvalidImplementation(reason~) => reason
    _ => "other composition failure"
  }
}

fn observe_capabilities(endpoint : @acp.ClientEndpoint) {
  let capabilities = endpoint.capabilities()
  // capabilities.fs/terminal/elicitation 反映已组合的 service。
  capabilities
}
```

Agent service 的空/重复 auth method、invalid implementation 和 capability
派生见 [`agent/service_test.mbt`](../../agent/service_test.mbt) 第 134-237 行；
Client optional service 失败见 [`client/service_test.mbt`](../../client/service_test.mbt)
第 151-187 行；endpoint handler failure/cancellation 见
[`agent/endpoint_test.mbt`](../../agent/endpoint_test.mbt) 第 74-150 行和
[`client/endpoint_test.mbt`](../../client/endpoint_test.mbt) 第 223-253 行。

## 错误边界

不要用默认 service、空 reply 或假的 capability 做 fallback。缺失 operation 应
是 `UnavailableOperation`；context/broker mismatch 应是结构化 mismatch；真实
task cancellation 应保持 cancellation 语义。runtime trace 不得泄露 peer payload、
prompt、文件内容或环境值。

## 下一篇

继续阅读 [10 Advanced](10-advanced.md)，理解这些 API 如何落在 functional core
与 imperative shell 的边界上。
