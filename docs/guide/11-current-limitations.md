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
- MoonBit↔MoonBit 真实子进程 stdio 端到端证据（`tests/interop/`，3 tests）；
- pinned v1 schema/meta（`spec/schema/v1/`）与 method manifest exact-set drift、
  release-boundary 测试；
- native target 下已有的 package tests（全仓 398/398）。

## 当前不可宣称完成的能力

- v1 release gate：SDK 范围矩阵行已 `Proven`，剩余 gate 事项为最终人工
  release review 与版本/发布决策；service-owned 组合维度（replay 持久化执行、
  root assembly 执行、真实输出截断执行）由调用方组合闭环，详见
  [implementation-plan/04](../implementation-plan/04-v1-completeness-matrix.md)；
- service-owned 执行边界由调用方组合：session 持久化/replay 执行、
  terminal/process registries、截断执行、root assembly（SDK 不内置真实
  FS/terminal/存储策略）；
- 既有策略决定：malformed-frame 采用 trace + fail-close（协议未规定，SDK
  选定并记录）；active-session registry 归 application store（SDK 保持
  registry-free）；
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

回到 [00 指南索引](00-index.md) 选择已完成切片，或等待 v1 release 正式落地
后再扩展集成。
