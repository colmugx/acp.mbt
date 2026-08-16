# 11 当前限制与发布边界

## 定位

本章是集成前的事实清单。它防止把当前已验证的 SDK 切片误读成完整 ACP v1
runtime 或发布承诺。

## 前置

建议先读完 [00 指南索引](00-index.md) 至 [10 Advanced](10-advanced.md)。

## 当前可使用的切片

- JSON-RPC envelope、string/number/null ID、error codec 和 typed ACP data codec；
- Agent/Client service、spec、endpoint 的 immutable composition；
- AgentContext typed broker seam 与 ClientConnection typed broker facade；
- newline framing 的纯状态 API；
- 单一 owner-loop runtime：`connection_runtime_run_owner(_with_outbound)`、
  engine 级 `RuntimeOutboundChannel` 与 `agent_context_over_channel` /
  `client_connection_over_channel` typed brokers；
- 真实 stdio/process 运行入口：`runtime_stdio_ports`、`runtime_process_ports`、
  `agent_serve_stdio(_with_outbound)`、`client_connect_process`（含 `spawned`
  回调）；
- MoonBit↔MoonBit 真实子进程 stdio 端到端证据（`tests/interop/`，2 tests）；
- pinned v1 schema/meta（`spec/schema/v1/`）与 method manifest exact-set drift、
  release-boundary 测试；
- native target 下已有的 package tests（全仓 394/394）。

## 当前不可宣称完成的能力

- TypeScript/Rust 四向 interoperability 与其 CI 可复现性（固定 pin 的官方
  SDK 真实 stdio 矩阵未执行）；
- v1 release gate：矩阵中 C05/G01/G05/G06/G07 仍 `In progress`（缺口分别是
  service-owned replay 组合、root assembly 执行、四向 interop、真实输出截断
  执行、trace 维度），详见
  [implementation-plan/04](../implementation-plan/04-v1-completeness-matrix.md)；
- service-owned 执行边界由调用方组合：session 持久化/replay 执行、
  terminal/process registries、截断执行、root assembly（SDK 不内置真实
  FS/terminal/存储策略）；
- 两个未决策略：malformed-frame 的 continue/close 行为、active-session
  registry 的所有权归属（见 implementation-plan/10 的 Questions backlog）；
- root facade 尚未导出 stdio 运行入口必需的 adapter 初始状态构造器
  （`agent_adapter_state_new`/`client_adapter_state_new` 及其 protocol state
  构造器）与 protocol 包的 `session_update_fold` 纯 consumer fold；
- ACP v2/`experimental` 实现。

```mbt nocheck
// 以上未完成项是能力边界记录，不是可调用的用户 API；
// 不要用 fake transport、空 handler 或 no-op fallback 把它们伪装成成功路径。
```

## 错误边界

如果产品需要上述未完成能力，应在自己的 composition root 暂时保留明确的适配
边界，并把缺失能力报告为阻塞项；不要把 fake transport、空 handler 或 no-op
fallback 发布成 ACP 成功路径。

## 下一步

回到 [00 指南索引](00-index.md) 选择已完成切片，或等待对应 interop/release
能力正式落地后再扩展集成。
