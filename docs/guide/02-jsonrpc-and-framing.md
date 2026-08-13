# 02 JSON-RPC 与 framing

## 定位

本章说明 envelope 的构造边界：request、notification、success/error response
以及 request/response ID。JSON-RPC codec 只处理一个完整 JSON 值，不负责网络
读写和换行。

## 前置

完成 [01 Quickstart](01-quickstart.md)，并使用 root facade 的
`JsonRpcRequest`、`JsonRpcNotification`、`JsonRpcResponse`、`JsonRpcMessage`、
`JsonRpcId`、`jsonrpc_encode` 和 `jsonrpc_decode`。

当前 module version 是 `0.1.0`，但尚未发布稳定 release；请按根
[README](../../README.mbt.md) 的依赖说明准备 package。仓库内开发直接引用本
module，并在使用方 package 的 `moon.pkg` 中写：

```text
import {
  "colmugx/acp"
}
```

源码使用默认 alias `@acp`。

## 可复制示例

```mbt nocheck
fn make_messages() {
  let request = @acp.JsonRpcRequest::new(
    id=@acp.RequestId::String("request-1"),
    method_name="session/new",
  )
  let notification = @acp.JsonRpcNotification::new(
    method_name="session/cancel",
  )
  let error = @acp.JsonRpcError::auth_required()
  let response_id : @acp.ResponseId = @acp.JsonRpcId::String("request-1")
  let response = @acp.JsonRpcResponse::error(id=response_id, error~)

  let request_text = @acp.jsonrpc_encode(@acp.JsonRpcMessage::request(request))
  let notification_text = @acp.jsonrpc_encode(
    @acp.JsonRpcMessage::notification(notification),
  )
  let response_text = @acp.jsonrpc_encode(
    @acp.JsonRpcMessage::response(response),
  )
  (request_text, notification_text, response_text)
}
```

根 facade 的同类 response/error 断言见
[`facade_test.mbt`](../../facade_test.mbt) 第 47-50 行；完整 envelope round
trip 见第 3-11 行。

`JsonRpcId` 的 string、number、null 是不同语义。notification 没有 ID，也不应
被伪造为带 null ID 的 request；响应的 ID 必须与对应 request 相关联。

## 错误边界

codec 会拒绝非 object envelope、冲突字段、非法 params、缺失 result/error
等情况。`JsonRpcResponse::error` 表示协议层失败，不代表 transport 已经成功
写出；写出仍需由上层端口报告。

## 下一篇

继续阅读 [03 ACP codecs 与 method manifest](03-acp-codecs-and-methods.md)，把
JSON-RPC method 映射到 typed ACP request/notification。
