# colmugx/acp

`colmugx/acp` 是面向 Agent Client Protocol (ACP) v1 的 MoonBit native SDK。
当前版本已覆盖稳定 v1 wire、typed Agent/Client endpoint 组合与真实
stdio/process runtime；还不是可发布的完整 v1 SDK（见下方剩余边界）。

## 当前状态

- 稳定 v1 wire：严格 JSON-RPC envelope、ACP 数据模型、typed codecs、newline framing。
- immutable composition：Agent/Client service、spec、endpoint 和 Reader/DI seam。
- 单一 owner-loop runtime：`connection_runtime_run_owner(_with_outbound)` 引擎、
  typed outbound channel 与 `agent_context_over_channel` /
  `client_connection_over_channel` typed brokers。
- 真实 stdio/process：`agent_serve_stdio(_with_outbound)`、
  `client_connect_process`、`runtime_stdio_ports`、`runtime_process_ports`。
- 目标平台：`native` only。
- v2/`experimental` 尚未实现。
- 许可证：Apache-2.0。

尚未完成的能力包括 TypeScript/Rust 四向 interoperability、v1 release gate，
以及由调用方组合的 service-owned 执行边界（session 持久化/replay 执行、
terminal/process registries、截断执行、root assembly）。SDK 侧 matrix 测试与
MoonBit↔MoonBit 真实子进程 stdio e2e（`tests/interop/`）已通过；在四向
interop 与 release gate 闭环前，本项目不应被描述为完整 v1 release。

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

`RuntimePorts`/`RuntimeOptions` 仍是可注入的配置/端口 seam；`runtime_stdio_ports`
与 `runtime_process_ports` 是两个真实 I/O 构造器，owner runner 与
`agent_serve_stdio(_with_outbound)`/`client_connect_process` 在其上闭环。
`ClientConnection` 本身保持 caller-supplied typed broker facade 语义；
`client_connection_over_channel` 把它接到真实 engine。session 持久化/replay
执行、terminal/process registries、截断执行、root assembly、TS/Rust interop
和 release gate 仍待调用方组合或后续批次完成。

项目保持独立于 Posoco；未来由 `posoco-ext-acp` 负责 Posoco 侧适配。
