# Changelog

All notable changes to the `colmugx/acp` MoonBit module. Entries are
commit-anchored: each cites the commit hash (short form, resolvable via
`git log`) or a named test that verifies it. This file records what has
landed on `main`; it is not a release announcement.

## [Unreleased] — v1-pending

### Error forwarding (behavior change)

- Adapter errors no longer collapse onto payload-free standard messages.
  Every handler-, message-, and protocol-level failure now carries its
  host-authored, already-sanitized detail onto the wire on both JSON-RPC
  channels: `message` (what editors render) and `data` (the field
  Zed-style error builders surface). A user seeing "Internal error" with no
  cause can now read — and paste to a developer — what actually happened.
  Verified by `agent/adapter_wbtest.mbt` ("handler errors forward their
  message and data onto the wire", "protocol errors forward their payload
  as the wire message") and the mirrored `client/adapter_wbtest.mbt`.
- `HandlerError` gained `InvalidParams(message~ : String)`, mapped to
  JSON-RPC `-32602`, so clients distinguish user mistakes (unknown id,
  wrong value shape) from internal failures. Handlers must keep payloads
  sanitized: the adapter forwards them verbatim by design.
- An unexpected (non-`HandlerError`) handler exception is reported as
  `"agent handler failed: <display text>"` / `"client handler failed:
  <display text>"` instead of the bare category, naming the defect for bug
  reports. Encoder failures likewise report the decode path.
- Closed-static client/agent facade error types (`AgentContextError`,
  `ClientConnectionError`) are unchanged: they are the local typed
  boundary, not the wire; the wire now carries the full detail for any
  JSON-RPC peer.

`colmugx/acp` is a native-only MoonBit SDK for Agent Client Protocol (ACP)
v1. The v1 SDK scope is complete and locally gated (2026-08-17 scope
decisions recorded in `docs/implementation-plan/10-progress-ledger.md`),
but this is **not a release**. Open items before any v1 release claim
(per `docs/implementation-plan/09-posoco-and-release-boundary.md`): the
final human release review and the version/publish decision. The SDK's
conformance evidence set is the pinned schema/meta drift gate
(`method/manifest_test.mbt`) plus the MoonBit-to-MoonBit real-process
stdio e2e (`tests/interop/`); real-world client integration validation
belongs to downstream consumers of the SDK. The `experimental`
package (ACP v2 Draft facade) now carries the ACP v2 Draft stable-baseline
implementation; see the *Experimental: ACP v2 Draft baseline* section below.

### Toolchain baseline

- Froze the native package/toolchain baseline: root and `experimental`
  package import graphs, `colmugx/reader` as the composition-root dependency
  environment, native-only target. `d7b48a5` (following the initial
  baseline freeze `050d361`).

### JSON-RPC / framing

- Strict JSON-RPC 2.0 wire codec: exact signed-Int64 request-id boundaries,
  integer/null id distinction from notifications, malformed-number
  rejection, and an ACP single-frame profile that rejects JSON-RPC batches.
  `5377867` (`jsonrpc/codec_test.mbt`: "request ids preserve exact signed
  int64 boundaries and large values", "ACP single-frame profile rejects
  JSON-RPC batches").
- Newline-delimited framing transport: chunk/CRLF/noise tolerance, UTF-8
  code points split across chunks, rejection of empty lines / invalid
  UTF-8 / oversized frames, partial-EOF reporting. `40df6c4`
  (`transport/framing_wbtest.mbt`: "framing preserves chunks, multiple
  lines, CRLF, and noise").

### Protocol codecs and session-update fold

- Stable v1 wire models and typed agent/client protocol messages with
  strict, fail-fast validation. `de78734`, `8fc6123`
- Exact-integer semantics preserved end to end: UInt64 tool-call usage
  values, exact resource sizes, elicitation integers. `7306912`, `20a62b2`,
  `9f733fc`, `8c88e83`
- Embedded-resource blob round-trip coverage. `214cf49`
- Pure `SessionUpdateFold` consumer fold over the update variants
  (message-chunk aggregation by message id, session info, modes, config)
  with patch-omission vs null kept distinct and exact-UInt64 usage
  preservation. `c3fe204` (`protocol/update_test.mbt`: "e01 fold user
  message chunks aggregate by message id", "all stable session update
  variants round trip").
- Protocol-level matrix gap closure: A07/A08, B01/B02/B06/B09, F-series
  gates and G-series observability rows, non-empty `terminalId` validated
  in both directions, auth-bypass negative, cancel-to-cancelled permission
  ordering, structural stdout purity of traces. `e7b96e2`

### Agent/Client adapters and matrix semantics

- Validated, immutable endpoint services: fail-fast construction, no
  builder or fluent-registration API. `6a24b05`
- Agent method semantics for the C-series matrix rows (initialize,
  authenticate/logout, session lifecycle, modes, config options, prompt)
  with bidirectional `sessionId`/`currentModeId` invariants. `96610c2`
  (`agent/matrix_test.mbt`: "matrix C01 initialize response shape version
  auth and info are exact", "matrix C05 session load is gated typed and
  never aliases resume").
- Client host-method semantics for the D-series matrix rows, including the
  pinned-schema accept-only `content` field of `ElicitationCreateResult`
  and typed decline/cancel payloads. `c03a079` (`client/matrix_test.mbt`:
  "matrix D02 session update delivers every variant typed without
  responses").
- Permission completion validates the selected option against the original
  request: unknown option is `InvalidParams`, a handler `Cancelled` return
  settles as a cancelled outcome. `6f3b344`
- Client cancellation-command forwarding and elicitation-completion
  gating. `9a681db`, `4bd74df`
- Explicit-`false` capability gates reject the gated method with unchanged
  state: agent load/image/audio/embedded-context/MCP-HTTP+SSE gates,
  client fs read/write and terminal gates, boolean config-option gate.
  `3e98b53`, `888612b`, `3b99016`
- Unknown notifications produce a side-effect-free trace intent with no
  response and unchanged state. `b6639d7`
- Agent workspace-root gates. `87bc0df`

### Connection owner engine (typed cancel/close, outbound channel)

- Typed owner seams and runtime-engine extraction with atomic admission
  and atomic completion, generalized runtime events, injected and isolated
  legacy dispatch, owner-owned dispatch state. `e2b0d0c`, `a21c872`,
  `40eb608`, `49cf865`, `de46de0`, `70d37e3`, `94e1cd2`, `dc52d50`,
  `c886bb4`, `b09b415`
- Immediate (in-loop) and async-task owner actions with typed completions
  and reverse-order exactly-once request/notification semantics. `d8e155c`,
  `5b805b9`
- Typed cancellation/close: owner close consumed on every path,
  committed-state settle on admission, token+RequestId cancel checks,
  ignored cancels fail fast. `d744b5a`, `96274fb`
  (`connection/reducer_wbtest.mbt`: "close fails every pending direction
  and late responses stay visible").
- Outbound submit channel `RuntimeOutboundChannel`: opaque
  `submit_request`/`submit_notification`, engine-assigned numeric ids,
  waiter-before-send ordering, typed fail/cancel settle. `1dd9859`
- Agent and Client endpoints bridged onto the single owner engine
  (`agent_runtime_run(_with_outbound)`, `client_runtime_run(_with_outbound)`).
  `badbd03`, `77e5a41`
- Synchronous notification submit for fire-and-forget events:
  `session/cancel` and `$/cancel_request` reach the wire;
  closed channel maps to `Unavailable`, backpressure to `BrokerFailure`.
  `543dcc4`
- Benign wire-cancel tolerance: a well-formed inbound `$/cancel_request`
  for a non-live id (unknown request, already settled, or already
  cancelled) is a traced no-op (`TraceCancelIgnored` with the matching
  reason) and the connection keeps serving; live-cancel semantics, local
  cancel events, and genuine invariant divergences still fail fast.
  `c9eea23` (`tests/interop/interop_test.mbt`: "moonbit client late cancel
  keeps the agent connection serving").

### Brokers

- Typed outbound brokers `agent_context_over_channel` /
  `client_connection_over_channel` with full typed error mapping (encode
  failure to `BrokerFailure`, parked and `-32800` cancellations to
  `Cancelled`, undecodable replies to `ReplyMismatch`), enabling
  mid-handler streaming `session/update` and permission round-trips.
  `6be7dbb` (`connection/broker/channel_test.mbt`: "client connection over
  channel submits forward requests with distinct engine ids").

### Runtime stdio/process

- Native connection core: pure protocol reducer plus owner-loop runtime
  engine over injectable `runtime/ports.mbt` seams. `40df6c4`
- Real stdio and process ports: stdout carries ACP frames only with
  flush-per-write; traces are sanitized single lines on stderr via libc
  `write(2)` and never parse as protocol frames; no-wait process spawn
  with typed failure cleanup and kill/reap. `24c6e59`
  (`runtime/stdio_test.mbt`: "trace lines carry routing fields but never
  parse as protocol frames"; `runtime/process_test.mbt`: "process ports
  round-trip one frame through /bin/cat and reap the child").
- `agent_serve_stdio(_with_outbound)` and `client_connect_process` close
  the loop over real processes. `24c6e59` (`agent/stdio_test.mbt`:
  "agent_serve_stdio validates options before binding stdio";
  `client/runtime_process_test.mbt`: "client_connect_process surfaces a
  spawn rejection as a typed error").

### Facade

- Stable public surface re-exported from `top.mbt` via `pub using`.
  `2682fb6`
- Exported initial runner states on the facade. `11ca6c0`
  (`facade_test.mbt`: "root facade exposes initial runner states and the
  session-update fold").

### Conformance

- Vendored the pinned upstream v1 artifacts at immutable commit
  `b8dd9b24050f5d4882711656f30b1dbde0087d75`
  (`spec/schema/v1/schema.json`, `spec/schema/v1/meta.json`, byte-identical
  to the audited hashes in `spec/LOCK.md`) and gated the handwritten
  method manifest to those exact bytes: 25-entry exact-set match,
  direction/kind cross-checks, rejection of any unstable or v2 name, and a
  structural release-boundary drift gate (no Posoco dependency anywhere,
  no experimental import in the root facade). `7f6e4c4`
  (`method/manifest_test.mbt`: "stable v1 manifest is the exact method set
  of the pinned v1 schema and meta bytes", "release boundary: no posoco
  dependency anywhere and no experimental import in the root facade").
- MoonBit-to-MoonBit full-stack stdio end-to-end test: a real client
  process drives a real agent-fixture process over stdio, driven by frames
  and EOF rather than timing, including mid-prompt agent death settling
  exactly one typed failure. `1ed4b36` (`tests/interop/interop_test.mbt`:
  "moonbit client drives a moonbit agent process end to end over stdio").
- Local verification only (not CI-reproducible yet): the
  `docs/implementation-plan/09` gate commands pass at the current HEAD
  (`rtk moon check --target native --warn-list +73`, `rtk moon test
  --target native`, `rtk moon info --target native`, `rtk moon fmt
  --check`, `rtk git diff --check`, `rtk moon coverage analyze`). The
  earlier whole-module coverage toolchain quirk (a crash inside
  `moon_cove_report.combine_coverages`) is resolved; the canonical
  whole-module run is recorded in `uncovered.log` (711 uncovered lines
  in 39 files at `c9eea23`).

### Documentation

- Numbered user guide under `docs/guide/` plus README refresh. `8a08bd9`
- Protocol project baseline notes and repo hygiene (ignored generated
  interfaces, agent work files). `cf15295`, `00429b0`, `7f25f53`
- Guide/runtime coverage sync. `3a697e5`

### Experimental: ACP v2 Draft baseline (colmugx/acp/experimental)

The ACP v2 Draft stable baseline is implemented behind the explicit
`colmugx/acp/experimental` facade. This is Draft quality: breaking changes
may occur at any time. The unstable overlay is not implemented and never
vendored — `schema/v2/meta.unstable.json` is hash-recorded in `spec/LOCK.md`
as an exclusion reference only, and `schema/v2/schema.unstable.json` was
never retrieved. Version negotiation is v2-only with no downgrade: the
client always offers `protocolVersion: 2` and fails terminally
(`UnsupportedVersion` plus close) on any other negotiated version, while
the agent answers a version-1 offer with `2` and stays un-initialized until
the peer retries with version 2 — a v1 peer is rejected, never served v1.
The root v1 surface is unchanged: every commit below touches only
`experimental/`, the pinned `spec/schema/v2/` inputs, and
`tests/interop/v2/`, and the root boundary test stays green
(`method/manifest_test.mbt`: "release boundary: no posoco dependency
anywhere and no experimental import in the root facade").

- Baseline pin and manifest drift gate: vendored the pinned v2 schema/meta
  bytes (`spec/schema/v2/`, SHA-256 in `spec/LOCK.md`), a 16-entry v2
  method manifest, and the exact-set drift test deriving that manifest
  from the pinned bytes. `662253f` (`experimental/manifest_test.mbt`:
  "v2 manifest is the exact method set of the pinned v2 schema and meta
  bytes", "v1-only and unstable overlay names are outside the v2
  manifest").
- Protocol core: an explicit tri-state patch ADT (omitted = unchanged,
  `null` = clear, value = replace), open unions separating `Known`,
  `_`-prefixed extension, and future-raw tags with unknown payloads
  preserved, and strict decode that rejects unknown fields with the
  offending key and path and known-tag illegal payloads as typed errors.
  `cfd17ea` (`experimental/core_test.mbt`: "v2 patch decode distinguishes
  omitted null and value", "v2 open union keeps underscore tags as
  extension with raw payload", "v2 reject unknown reports the offending
  key and path").
- Full v2 model codecs: initialize (role-agnostic `info` plus
  `capabilities` with object-presence support markers), auth methods,
  MCP server configs, session lifecycle models, and config options
  (`66ecd5f`, 45 tests); content blocks, tool calls with per-id upsert
  content chunks, diffs as `changes` file operations with optional
  `git_patch`, the agent-owned terminal surface, and the restructured
  permission title/subject shapes (`041bd7b`, 29 tests).
- `session/update` envelope covering all 16 arms — user/agent/thought
  message upserts and chunks, `state_update`
  running/requires_action/idle, tool-call update and content chunk,
  terminal upsert and output chunk, plan replacement, available commands,
  config options, session info, usage — with unknown discriminators
  preserved raw, plus the elicitation property DSL. `28f4bca`, 20 tests
  (`experimental/session_update_test.mbt`: "v2 message upsert arms
  round-trip tri-state content"; `experimental/elicitation_test.mbt`:
  "v2 elicitation create form round-trips the property DSL").
- Endpoint state machines with v2-only negotiation and no downgrade:
  the agent and client reducers reject repetition, gate traffic on
  initialization/readiness, and classify unknown and v1-only method names
  as typed rejections. `9aeee04`, 18 tests
  (`experimental/agent_state_test.mbt`: "v2 agent negotiation accepts
  only version two and rejects repetition"; `experimental/client_state_test.mbt`:
  "v2 client fails terminally on a mismatched negotiate result").
- Pure session fold over the update stream: prompt-accept to
  running/requires_action/idle lifecycle with stop reasons recorded only
  on idle, message/tool/plan/terminal upsert and chunk aggregation with
  tri-state patches, unknown updates preserved raw and re-emittable, and
  replay from start reproducing the live folded state. `bf73987`, 14
  tests (`experimental/session_fold_test.mbt`: "v2 fold lifecycle matrix
  records stop reason on idle only", "v2 fold replay from start
  reproduces the live folded state").
- JSON-RPC batch: a total batch codec (mixed and notification-only
  entries, empty array mapped to one `-32600` id-null reply, invalid JSON
  to one `-32700`, per-entry error tagging with siblings kept) while the
  v1 codec still rejects array input; frame expansion wired into the
  runners so inbound batch frames expand into single-object frames before
  the shared engine's object-only decode and replies go out per frame,
  which the v2 transport rules allow (lone frames pass byte-exact; a
  reply-batching helper is provided for peers that want one line).
  `ec19c4b`, 12 tests (`experimental/batch_test.mbt`: "v2 batch decode
  maps an empty array to one -32600 id-null response", "v1
  jsonrpc_decode_json still rejects array input"); `cb2abc8` + `e807c9b`
  (`experimental/batch_frame_test.mbt`: "v2 wire split expands a valid
  batch into ordered object frames"; `experimental/batch_expand_test.mbt`:
  "v2 agent runner over batch expanding ports processes batched
  entries").
- Agent and client adaptation stacks on the shared single-engine runtime:
  the typed agent adapter (admit/execute/complete, capability-marked
  gates, auth reservation), the typed client adapter (permission before
  initialize, elicitation mode gates), typed outbound brokers, and the
  `experimental_v2_agent_serve_stdio(_with_outbound)` /
  `experimental_v2_client_connect_process` runners. `480dad4`, 36 tests
  (`experimental/agent_adapter_test.mbt`: "v2 agent adapter completes
  every baseline session method"); `83cbf59`, 26 tests
  (`experimental/client_connection_test.mbt`: "v2 client connection
  forwards initialize and pins version 2"; `experimental/runtime_run_test.mbt`:
  "v2 agent runtime run with outbound streams a full turn with
  permission").
- Real-process end-to-end proof: a real MoonBit v2 client runtime drives a
  real MoonBit v2 agent-fixture process over stdio with frame/EOF-gated
  assertions — a live turn streamed through updates and a permission
  round-trip folded by the consumer, mid-prompt agent death settling
  exactly one typed failure, late wire-cancel tolerance, and a two-entry
  batch frame processed end to end. `7601ea5`
  (`tests/interop/v2/interop_test.mbt`: "v2 moonbit client drives a v2
  moonbit agent process end to end over stdio", "v2 moonbit client
  settles one typed failure when the agent dies mid-prompt", "v2 agent
  tolerates a late wire cancel and keeps serving", "v2 agent processes a
  two-entry batch frame").

### Compatibility commitments

Per `docs/implementation-plan/09-posoco-and-release-boundary.md`:

- Stable `colmugx/acp` targets ACP wire v1 only, on the native target
  only. The v1 method set and schema are locked to the pinned upstream
  commit recorded in `spec/LOCK.md`; the stable facade will not gain
  breaking changes without a new version, and no unstable or v2 name is
  vendored or exposed by the stable package.
- `colmugx/acp/experimental` is the ACP v2 Draft facade implementing the
  pinned stable baseline (see the *Experimental: ACP v2 Draft baseline*
  section above). It is Draft-only, breaking changes may occur at any
  time, it must be imported explicitly and will never change root v1
  behavior or goldens.
