# ACP 使用指南

## 定位

这是一套从 Quickstart 到 Advanced 的 `colmugx/acp` 用户指南。项目是
MoonBit native-only SDK，面向稳定 ACP v1 wire；当前仍在实现中，不是完整的
可发布 v1 产品，也不包含 v2 实现。

示例只依赖 root facade `"colmugx/acp"`。指南不会把 adapter、reducer、broker
或 owner runtime state 当作普通用户 API。

## 前置

需要 MoonBit native toolchain，以及能编辑 `moon.mod`/`moon.pkg` 的基本经验。
当前 module version 是 `0.1.0`，但尚未发布稳定 release。请先按根
[README](../../README.mbt.md) 的依赖说明准备 package；仓库内开发直接引用本
module。然后在使用方 package 的 `moon.pkg` 中写：

```text
import {
  "colmugx/acp"
}
```

MoonBit 源码使用默认 alias `@acp`；需要 core JSON 时，在同一个 `moon.pkg`
中另加 `"moonbitlang/core/json" @json`。

普通指南代码块标记为 `mbt nocheck`：它们用于复制和解释，不会因为本目录没有
`moon.pkg` 而被误认为自动测试。Quickstart 的核心片段有根黑盒测试证据。

## 学习路径

1. [01 Quickstart](01-quickstart.md)：构造 JSON-RPC、编码/解码、newline framing。
2. [02 JSON-RPC 与 framing](02-jsonrpc-and-framing.md)：ID、response、错误和边界。
3. [03 ACP codecs 与 method manifest](03-acp-codecs-and-methods.md)：typed message 解码。
4. [04 Agent endpoint](04-agent-endpoint.md)：一次性 immutable Agent 组合。
5. [05 Client endpoint](05-client-endpoint.md)：服务能力和 Client 组合。
6. [06 Reader 与 context](06-reader-and-context.md)：composition root 和 typed DI。
7. [07 ClientConnection](07-client-connection.md)：注入 broker 的 typed facade。
8. [08 Runtime ports](08-runtime-ports.md)：native ports/config seam 的边界。
9. [09 错误、取消与 capabilities](09-errors-cancellation-capabilities.md)：结构化失败。
10. [10 Advanced](10-advanced.md)：functional core、imperative shell 和集成边界。
11. [11 当前限制](11-current-limitations.md)：已完成与未完成能力清单。

## 错误边界

协议 codec、framing、composition、handler 和 broker 错误都应显式处理或向上
传播；不要把失败吞成成功。没有公开的 server runner 时，不要自行猜测一个
生命周期 API。

## 下一篇

从 [01 Quickstart](01-quickstart.md) 开始。
