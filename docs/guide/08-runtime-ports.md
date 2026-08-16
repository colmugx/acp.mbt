# 08 Runtime ports 与真实运行入口

## 定位

`RuntimeReaderPort`、`RuntimeWriterPort`、`RuntimeHandlerPort`、`RuntimePorts` 和
`RuntimeOptions` 描述调用方提供给 native runtime 的 immutable ports/config。它们
用于依赖注入、测试 fault/backpressure 和 trace。在此之上，root facade 已导出
两个真实 I/O 构造器和一组运行入口：

- `runtime_stdio_ports`：把本进程的真实 stdin/stdout 绑定为 engine 的
  reader/writer（每帧一次写出，无用户态缓冲；诊断走 trace sink，默认 stderr）；
- `runtime_process_ports`：为被驱动的 agent 子进程构造 reader/writer ports
  （spawn/reap、管道失败按 closed `RuntimeError` 集合 typed 映射）；
- `connection_runtime_run_owner(_with_outbound)`：通用 owner-loop 引擎入口；
- `agent_runtime_run` / `agent_runtime_owner_port`：Agent endpoint 接入同一 engine；
- `agent_serve_stdio(_with_outbound)`：用真实 stdio 服务一个 Agent 连接；
- `client_runtime_run` / `client_runtime_owner_port` / `client_connect_process`：
  Client 侧运行入口；`client_connect_process` 驱动一个 agent 子进程，
  可选 `spawned` 回调在 spawn 成功后、engine 启动前交出真实的
  `RuntimeProcessPorts`（用于主动关闭子进程 stdin、等待退出或取消）。

## 前置

完成 [01 Quickstart](01-quickstart.md) 和 [07 ClientConnection](07-client-connection.md)。
需要理解 `async` callback、`Bytes` 和结构化 `RuntimeError`。

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

## 可复制用法（ports/config seam）

```mbt nocheck
fn make_ports() -> @acp.RuntimePorts raise @acp.RuntimeError {
  let handlers : @acp.RuntimeHandlerPort = {
    request: async fn(_request) {
      @acp.RuntimeHandlerResult::HandlerSuccess(@json.Json::null())
    },
    notification: async fn(_notification) { () },
    response: async fn(_response) { () },
    outbound_failure: None,
  }
  let options = @acp.runtime_default_options()
  @acp.runtime_validate_options(options)
  let reader : @acp.RuntimeReaderPort = {
    read: async fn(_max_len) { None },
  }
  let writer : @acp.RuntimeWriterPort = {
    write: async fn(_frame) { () },
  }
  {
    reader,
    writer,
    handlers,
    cancel_outbound: None,
    trace: _event => (),
  }
}
```

`runtime_default_options` 与 option validation 的根 facade 证据见
[`facade_test.mbt`](../../facade_test.mbt) 第 39-40 行；端口和错误类别的公开
定义见 [`runtime/ports.mbt`](../../runtime/ports.mbt) 第 19-168 行。

## 运行入口与 typed outbound broker

engine 级 outbound 提交通道 `RuntimeOutboundChannel`（`submit_request`、
`submit_notification`、`submit_notification_sync`）只在
`connection_runtime_run_owner_with_outbound` 内部构造；root facade 导出两个
typed broker 把它接到用户 surface：

- `agent_context_over_channel`：构造 Agent handler 执行中可用的
  `AgentContext`（反向 request 与 `session/update` 流式 notification 走真实
  engine）；
- `client_connection_over_channel`：构造 Client 的 `ClientConnection` facade
  （正向 request 走 submit_request，`session/cancel` 等 notification 走同步
  提交通道）。

Agent stdio 服务端的组合形状如下（镜像 [`tests/interop/agent-fixture/main.mbt`](../../tests/interop/agent-fixture/main.mbt)
的在库证据）：

```mbt nocheck
async fn serve() {
  @acp.agent_serve_stdio_with_outbound(
    endpoint~,
    context_factory=channel => @acp.agent_context_over_channel(channel~),
    initial_state~,
  )
}
```

`endpoint` 来自 [04 Agent endpoint](04-agent-endpoint.md) 的一次性组合；
`initial_state` 是 engine 拥有的 adapter 初始状态。**当前 facade 缺口**：
`agent_serve_stdio*`/`client_connect_process` 已从 root facade 导出，但它们
必需的 `initial_state`（`AgentAdapterState`/`ClientAdapterState`）及其构造器
（`agent_adapter_state_new`、`agent_protocol_state_new`、
`client_adapter_state_new`、`client_protocol_state_new`/`client_protocol_state_ready`）
尚未从 root facade re-export。因此仅依赖 root facade 的调用方目前无法完整
构造该调用；在库消费者（如 `tests/interop/`）通过实现包构造 initial state。
这是待补的 facade surface，不是可以绕过或猜测的 API。

Client 驱动子进程的组合形状（同样镜像
[`tests/interop/interop_test.mbt`](../../tests/interop/interop_test.mbt)）：

```mbt nocheck
async fn drive(endpoint : @acp.ClientEndpoint) {
  @acp.client_connect_process(
    endpoint_factory=channel => {
      // 组合 root 可把 client_connection_over_channel(channel~) 闭包进
      // endpoint 的 service handler；此处直接复用 endpoint。
      endpoint
    },
    initial_state~,
    handlers~,
    command="path/to/agent-binary",
    spawned=ports => {
      // 需要主动结束会话时在此保存 ports.child_stdin；
      // 关闭它即向子进程发送 ACP stdio shutdown 信号（EOF）。
    },
  )
}
```

`client_connect_process` 的 child 生命周期在调用内收束：无 detached child、
无后台 reaper；`spawned` 默认 no-op，默认行为不变。

## 错误边界

无效 bounds、reader/writer 关闭或 backpressure、framing/codec/reducer/task
失败都应成为 `RuntimeError` 或 trace；trace 只能使用 redacted routing metadata
（direction/phase/request_id/method/error kind，不携带 payload）。
`RuntimePorts.trace` 不应写 stdout，协议 stdout 只能承载 ACP JSON-RPC frames；
`runtime_stdio_ports` 已按此实现（frames→stdout，trace→stderr/注入 sink）。

transport package 中的 `stdio_transport` 仍未从 root facade 导出；真实 stdio
生命周期应使用上文 `runtime_stdio_ports` + `agent_serve_stdio*` /
`client_connect_process` 组合，而不是自行封装 transport adapter。

## 下一篇

继续阅读 [09 错误、取消与 capabilities](09-errors-cancellation-capabilities.md)，
统一理解结构化失败和 capability 派生。
