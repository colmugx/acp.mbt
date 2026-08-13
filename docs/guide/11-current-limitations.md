# 11 当前限制与发布边界

## 定位

本章是集成前的事实清单。它防止把当前已验证的 protocol/endpoint 切片误读成
完整 ACP v1 runtime 或发布承诺。

## 前置

建议先读完 [00 指南索引](00-index.md) 至 [10 Advanced](10-advanced.md)。

## 当前可使用的切片

- JSON-RPC envelope、string/number/null ID、error codec 和 typed ACP data codec；
- Agent/Client service、spec、endpoint 的 immutable composition；
- AgentContext typed broker seam 与 ClientConnection typed broker facade；
- newline framing 的纯状态 API；
- Runtime options/reader/writer/handler/trace port 的数据结构和 validation seam；
- native target 下已有的 package tests。

## 当前不可宣称完成的能力

- `serve_stdio`、真实 stdout-only stdio server 生命周期；
- 完整 connection owner runner、typed adapter 到 I/O 的闭环；
- process spawn/reap、session persistence/replay/resume 和真实 FS/terminal 资源；
- TypeScript/Rust 四向 interoperability；
- 稳定 v1 release gate；
- ACP v2/experimental 实现。

```mbt nocheck
// 以下不是当前可调用的用户 API，只是未完成能力的名称记录：
// serve_stdio / connection owner runner / process lifecycle
```

## 错误边界

如果产品需要上述未完成能力，应在自己的 composition root 暂时保留明确的适配
边界，并把缺失能力报告为阻塞项；不要把 fake transport、空 handler 或 no-op
fallback 发布成 ACP 成功路径。

## 下一步

回到 [00 指南索引](00-index.md) 选择已完成切片，或等待对应 runtime/interop
能力正式落地后再扩展集成。
