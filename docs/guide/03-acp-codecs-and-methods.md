# 03 ACP codecs 与 method manifest

## 定位

本章从通用 JSON-RPC envelope 进入 ACP v1 typed message。Agent 和 Client 的
method 方向不同，应该使用对应的 decoder，而不是在业务代码中手写字符串分支。

## 前置

完成 [02 JSON-RPC 与 framing](02-jsonrpc-and-framing.md)。本章只使用 root facade
导出的 `decode_agent_request`、`decode_agent_notification`、
`decode_client_request`、`decode_client_notification`、message error types 和
`acp_v1_method_manifest`。

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

## 可复制示例

```mbt nocheck
fn decode_known_messages() {
  let initialize = @acp.decode_agent_request(
    "initialize",
    Some(@json.Json::object({
      "protocolVersion": @json.Json::number(1.0, repr="1"),
    })),
  )
  let cancel = @acp.decode_client_notification(
    "$/cancel_request",
    Some(@json.Json::object({
      "requestId": @json.Json::string("request-1"),
    })),
  )
  let manifest = @acp.acp_v1_method_manifest()
  (initialize, cancel, manifest.length())
}
```

上述输入和 variant 断言已经在
[`facade_test.mbt`](../../facade_test.mbt) 第 24-37 行验证；method manifest 的
方向、kind 和固定集合测试在 [`method/manifest_test.mbt`](../../method/manifest_test.mbt)。

decoder 的失败应保留为 `AgentMessageError` 或 `ClientMessageError`，不要把未知
method 当成某个已知 method，也不要把 request decoder 和 notification decoder
互换。具体字段 codec（例如 initialize/session/content）由 root facade 的
`*_from_json`/`*_to_json` 函数组负责。

## 错误边界

缺少 params、错误字段类型、未知 method、方向不匹配和非法 request 都是结构化
decode failure。成功 decode 只说明消息符合该 typed surface，不说明 endpoint
已经接受它或 handler 一定存在。

## 下一篇

继续阅读 [04 Agent endpoint](04-agent-endpoint.md)，把 typed handler 组合成一个
immutable Agent endpoint。
