# colmugx/acp

`colmugx/acp` 是面向 Agent Client Protocol (ACP) v1 的 MoonBit native SDK。
当前版本仍在实现中，适合学习协议模型、构造 typed Agent/Client endpoint 和接入
自有 transport seam；还不是可发布的完整 v1 SDK。

## 当前状态

- 稳定 v1 wire：严格 JSON-RPC envelope、ACP 数据模型、typed codecs、newline framing。
- immutable composition：Agent/Client service、spec、endpoint 和 Reader/DI seam。
- 目标平台：`native` only。
- v2/`experimental` 尚未实现。
- 许可证：Apache-2.0。

尚未完成的能力包括 `serve_stdio`、完整 connection runtime runner、真实
process/host-resource 集成、TypeScript/Rust interoperability，以及 v1 release
gate。因此本项目不应被描述为已经提供可直接运行的 ACP server/client。

## 安装与导入

当前 module 的 `version` 字段是 `0.1.0`，但尚未发布稳定 release。仓库内开发
直接引用本 module 的 package，不应把安装命令当作当前可用性证明。待发布到
Mooncakes 后，使用方才执行：

```text
moon add colmugx/acp@0.1.0
```

然后在使用方 package 的 `moon.pkg` 中声明 root facade：

```text
import {
  "colmugx/acp"
}
```

该 package 的 MoonBit 源码使用默认 alias `@acp` 访问 ACP API；如需构造 JSON
值，再在同一个 `moon.pkg` 中加入 `"moonbitlang/core/json" @json`。

## Quickstart

从 [01-quickstart](docs/guide/01-quickstart.md) 开始。它展示 JSON-RPC request
的构造、encode/decode 和 newline framing。示例依据根黑盒测试
[`facade_test.mbt`](facade_test.mbt) 第 2 行的已验证片段整理。

最小 source 形状如下（`moon.pkg` 声明见上文）：

```mbt nocheck
///|
fn quickstart_message() {
  let request = @acp.JsonRpcRequest::new(
    id=@acp.RequestId::String("quickstart"),
    method_name="initialize",
  )
  let message = @acp.JsonRpcMessage::request(request)
  @acp.jsonrpc_decode(@acp.jsonrpc_encode(message))
}
```

该片段对应 [`facade_test.mbt`](facade_test.mbt) 第 3 行附近的 request round-trip 证据；
完整 framing 示例见 [01-quickstart](docs/guide/01-quickstart.md)。

## 指南

完整学习路径见 [00-index](docs/guide/00-index.md)，依次覆盖 wire、codec、Agent、
Client、Reader/context、typed broker、runtime ports、错误语义和高级边界。

## 重要限制

`RuntimePorts` 和 `RuntimeOptions` 是可注入的配置/端口 seam，不等于一个已经完成
的 server runner。`ClientConnection` 是 caller-supplied typed broker facade，不是
transport 实现。真实 stdio 生命周期、connection owner runner、process 管理、
interop 和 release gate 仍待完成。

项目保持独立于 Posoco；未来由 `posoco-ext-acp` 负责 Posoco 侧适配。
