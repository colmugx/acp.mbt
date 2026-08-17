# MoonBit ACP SDK

Type-safe [Agent Client Protocol](https://agentclientprotocol.com/) (ACP) v1 SDK for MoonBit.

**Version**: 0.1.0 · **Protocol**: ACP v1 · **Target**: native · **License**: Apache-2.0

Implement the agent side, the client side, or both. Peers exchange
newline-delimited JSON-RPC frames over stdio: every v1 type has a strict
codec, endpoints are composed from immutable typed services, and a single
engine-owned runtime drives requests, streamed session updates, and reverse
requests (permissions, filesystem, terminals, elicitation) across real pipes.

## Installation

```bash
moon add colmugx/acp
```

Then declare the root facade in your package's `moon.pkg`:

```text
import {
  "colmugx/acp"
}
```

## Quick Start

### Agent

Compose the services once, derive the endpoint and its initial state, then
serve this process's real stdio. Handlers stream `session/update`
notifications and ask permissions through the typed `AgentContext`; ids,
correlation, and the serial writer queue stay engine-owned.

```moonbit nocheck
///|
fn agent_endpoint() -> @acp.AgentEndpoint {
  let spec = @acp.agent_spec(
    info={
      name: "my-agent",
      title: @acp.ProtocolNullable::Omitted,
      version: "0.1.0",
      meta: @acp.ProtocolNullable::Omitted,
    },
    sessions=@acp.agent_session_service(new_session~, prompt~, cancel~),
    support=@acp.agent_support(),
  ).unwrap()
  @acp.agent_endpoint_from_spec(spec)
}

///|
fn agent_initial_state(endpoint : @acp.AgentEndpoint) -> @acp.AgentAdapterState {
  let config : @acp.AgentProtocolConfig = {
    agent_capabilities: @acp.ProtocolNullable::Value(endpoint.capabilities()),
    auth_methods: endpoint.auth_methods(),
    agent_info: @acp.ProtocolNullable::Omitted,
  }
  @acp.agent_adapter_state_new(protocol=@acp.agent_protocol_state_new(config~))
}

///|
async fn new_session(
  _context : @acp.AgentContext,
  _params : @acp.NewSessionParams,
) -> @acp.NewSessionResult {
  {
    session_id: "session-1",
    modes: @acp.ProtocolNullable::Omitted,
    config_options: @acp.ProtocolNullable::Omitted,
    meta: @acp.ProtocolNullable::Omitted,
  }
}

///|
async fn prompt(
  context : @acp.AgentContext,
  _params : @acp.PromptParams,
) -> @acp.PromptResult {
  context.session_update({
    session_id: "session-1",
    update: @acp.SessionUpdate::AgentMessageChunk({
      content: @acp.ContentBlock::Text({
        annotations: @acp.ProtocolNullable::Omitted,
        text: "Working on it...",
        meta: @acp.ProtocolNullable::Omitted,
      }),
      message_id: @acp.ProtocolNullable::Value("message-1"),
      meta: @acp.ProtocolNullable::Omitted,
    }),
    meta: @acp.ProtocolNullable::Omitted,
  })
  let permission = context.request_permission(permission_request())
  let _selected = match permission.outcome {
    @acp.RequestPermissionOutcome::Selected(outcome) => outcome.option_id
    @acp.RequestPermissionOutcome::Cancelled => "cancelled"
  }
  {
    stop_reason: @acp.StopReason::EndTurn,
    meta: @acp.ProtocolNullable::Omitted,
  }
}

///|
async fn cancel(
  _context : @acp.AgentContext,
  _params : @acp.CancelParams,
) -> Unit {
  ()
}

///|
async fn main {
  let endpoint = agent_endpoint()
  @acp.agent_serve_stdio_with_outbound(
    endpoint~,
    context_factory=channel => @acp.agent_context_over_channel(channel~),
    initial_state=agent_initial_state(endpoint),
  )
}
```

This example mirrors the compiling fixture
[`tests/interop/agent-fixture/main.mbt`](tests/interop/agent-fixture/main.mbt).
`permission_request()` is elided above: build the `RequestPermissionRequest`
from the session id, the tracked tool call, and one `PermissionOption` per
choice — see `interop_fixture_permission_request` in the same file.

The loop ends at stdin EOF. Stdout carries only ACP frames. Advertise
authentication with `auth=@acp.agent_auth_service(methods=~, authenticate=~)`.
When handlers never issue reverse requests or stream updates,
`agent_serve_stdio(endpoint~, context~, initial_state~)` takes a pre-built
`AgentContext` instead of the channel factory.

### Client

Spawn any ACP v1 agent binary as a child process, drive it with typed forward
requests, and consume its session updates and permission requests as typed
values. This example mirrors the compiling end-to-end proof
[`tests/interop/interop_test.mbt`](tests/interop/interop_test.mbt).

The client side needs the async and JSON dependencies alongside the facade:

```text
import {
  "colmugx/acp"
  "colmugx/reader"
  "moonbitlang/async"
  "moonbitlang/async/aqueue" @aqueue
  "moonbitlang/core/json" @json
}
```

```moonbit nocheck
///|
fn client_endpoint(
  updates : Array[@acp.SessionUpdateParams],
) -> @acp.ClientEndpoint {
  let spec = @acp.client_spec(
    info={
      name: "my-client",
      title: @acp.ProtocolNullable::Omitted,
      version: "0.1.0",
      meta: @acp.ProtocolNullable::Omitted,
    },
    session=@acp.client_session_service(
      session_update=async fn(params : @acp.SessionUpdateParams) {
        updates.push(params) // typed update, in wire order
      },
      request_permission=async fn(
        request : @acp.RequestPermissionRequest,
      ) -> @acp.RequestPermissionResponse {
        {
          outcome: @acp.RequestPermissionOutcome::Selected({
            option_id: request.options[0].option_id,
            meta: @acp.ProtocolNullable::Omitted,
          }),
          meta: @acp.ProtocolNullable::Omitted,
        }
      },
    ),
  ).unwrap()
  @reader.Reader::run(@acp.client_program(@reader.Reader::pure(spec)), ()).unwrap()
}

///|
async fn main {
  let updates : Array[@acp.SessionUpdateParams] = []
  let endpoint = client_endpoint(updates)
  let connections : @aqueue.Queue[@acp.ClientConnection] = Queue(kind=Unbounded)
  @async.with_task_group(group => {
    let driver = group.spawn(() => {
      let connection = connections.get()
      connection.initialize({
        protocol_version: 1,
        client_capabilities: @acp.ProtocolNullable::Omitted,
        client_info: @acp.ProtocolNullable::Omitted,
        meta: @acp.ProtocolNullable::Omitted,
      })
      let session = connection.new_session({
        cwd: "/",
        additional_directories: @acp.ProtocolNullable::Omitted,
        mcp_servers: [],
        meta: @acp.ProtocolNullable::Omitted,
      })
      let result = connection.prompt({
        session_id: session.session_id,
        prompt: [],
        meta: @acp.ProtocolNullable::Omitted,
      })
      ignore(result) // result.stop_reason / result.meta carry the typed outcome
    })
    @acp.client_connect_process(
      endpoint_factory=channel => {
        let _ = connections.try_put(
          @acp.client_connection_over_channel(channel~),
        ) catch {
          _ => false
        }
        endpoint
      },
      initial_state=@acp.client_adapter_state_new(
        protocol=@acp.client_protocol_state_ready(
          capabilities=@acp.ProtocolNullable::Value(endpoint.capabilities()),
        ),
      ),
      handlers={
        request: _ => {
          @acp.RuntimeHandlerResult::HandlerSuccess(@json.Json::null())
        },
        notification: _ => (),
        response: _ => (),
        outbound_failure: None,
      },
      command="path/to/agent-binary",
    )
    driver.wait()
  })
  // Fold the recorded updates with the pure consumer fold: chunks sharing
  // one messageId aggregate into one message and tool-call updates patch
  // the tracked call (used end to end in tests/interop/interop_test.mbt).
  let folded = @acp.session_update_fold(known_modes=[])
  println("messages: \{folded.agent_messages.length()}")
}
```

Connection scope equals child scope: the child is spawned and reaped inside
the `client_connect_process` call. Pass `spawned=ports => ...` to capture
`ports.child_stdin`; closing it sends the ACP stdio shutdown signal (EOF) to
the child, which is how a live interactive session ends.

## Capabilities by Service Presence

There is no builder, no registration phase, and no manually maintained
capability map. You compose immutable service values once, and each endpoint
derives its capabilities from which services are present:

- `AgentEndpoint::capabilities()` comes from the handlers in
  `agent_session_service`, the flags in `agent_support()`, and
  `agent_auth_service` when supplied.
- `ClientEndpoint::capabilities()` comes from `client_session_service` plus
  whichever of `client_file_system_service`, `client_terminal_service`, and
  `client_elicitation_service` you passed to `client_spec`.

Omit a service and its capability is simply not advertised; call an operation
you did not wire and the endpoint raises `UnavailableOperation` instead of
failing silently.

## API Map

| Concern | Facade exports |
|---------|----------------|
| JSON-RPC envelope & framing | `JsonRpcRequest`, `JsonRpcMessage`, `jsonrpc_encode`, `jsonrpc_decode`, `framing_feed`, `framing_finish` |
| ACP v1 models & codecs | typed `*_from_json` / `*_to_json` per model, `decode_agent_request`, `decode_client_request`, `acp_v1_method_manifest` |
| Agent composition | `agent_spec`, `agent_session_service`, `agent_support`, `agent_auth_service`, `agent_endpoint_from_spec`, `AgentContext` |
| Client composition | `client_spec`, `client_session_service`, `client_file_system_service`, `client_terminal_service`, `client_elicitation_service`, `client_program` |
| Connections & outbound | `ClientConnection`, `client_connection_over_channel`, `agent_context_over_channel` |
| Runners | `agent_serve_stdio(_with_outbound)`, `client_connect_process`, `agent_runtime_run`, `client_runtime_run`, `connection_runtime_run_owner(_with_outbound)` |
| Initial state & fold | `agent_protocol_state_new`, `agent_adapter_state_new`, `client_protocol_state_new`, `client_protocol_state_ready`, `client_adapter_state_new`, `session_update_fold` |
| Ports & trace | `runtime_stdio_ports`, `runtime_process_ports`, `RuntimeHandlerPort`, `runtime_default_options`, `runtime_stderr_trace` |
| Errors | `HandlerError`, `AgentCompositionError`, `ClientCompositionError`, `AgentContextError`, `ClientConnectionError`, `RuntimeError` |

## Trace and Diagnostics

Stdout carries only newline-delimited ACP JSON-RPC frames. Diagnostics are
sanitized single-line traces — direction, phase, request id, method, and error
kind only, never payloads — written to stderr by default; every runner accepts
a `trace~` sink so you can capture them yourself.

## License

Apache-2.0
