# 10 Advanced：functional core 与 imperative shell

## 定位

高级集成应把纯协议模型/codec/reducer 与 native async effects 分开：functional
core 负责验证、状态转移和 command；imperative shell 才负责 reader、writer、
task、queue、取消和 trace。用户可以组合 root facade 的 immutable service/port，
但不应直接依赖内部 reducer、broker 或 adapter state。

## 前置

完成 [01-09](00-index.md) 的全部章节，并能区分 typed endpoint、typed broker
facade 和 transport seam。

当前 module version 是 `0.1.0`，但尚未发布稳定 release；请按根
[README](../../README.mbt.md) 的依赖说明准备 package。仓库内开发直接引用本
module，并在使用方 package 的 `moon.pkg` 中写：

```text
import {
  "colmugx/acp"
}
```

源码使用默认 alias `@acp`。

## 推荐的组合边界

```text
caller-owned environment
        │
        ▼
immutable AgentSpec / ClientSpec / typed broker
        │
        ▼
root facade endpoint and protocol values
        │
        ▼
injected RuntimePorts (native shell)
        │
        ▼
transport frames and redacted trace
```

```mbt nocheck
fn compose_once(spec : @acp.ClientSpec) {
  // 只构造一个 immutable composition value；不要注册到 global。
  @acp.client_program_from(fn(_env : Unit) { Ok(spec) })
}
```

目录职责也应保持清晰：root facade 负责稳定 re-export，`agent`/`client` 负责
领域 endpoint，`protocol`/`jsonrpc` 负责纯 wire data，`transport` 负责 framing，
`runtime` 负责 ports/config。文档级用户代码只依赖 root facade。

## Posoco 集成边界

`colmugx/acp` 不内置 Posoco model、session store、真实 filesystem、terminal 或
UI 策略。未来 `posoco-ext-acp` 可以依赖本项目，并在 composition root 注入
typed handlers/context brokers；ACP SDK 本身不反向依赖 Posoco。

## 错误边界

不要通过第二套 connection loop、Ref/Mutex bridge、shadow pending map 或隐式
global 来“补齐”未完成 runtime。若需要一个目前不存在的生命周期 API，应先把
需求作为实现工作，而不是在用户指南中发明调用方式。

## 下一篇

最后阅读 [11 当前限制](11-current-limitations.md)，按已完成/未完成事实评估是否
适合接入你的产品。
