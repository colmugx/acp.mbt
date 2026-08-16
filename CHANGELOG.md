# Changelog

All notable changes to the `colmugx/acp` MoonBit module. Entries are
commit-anchored: each cites the commit hash (short form, resolvable via
`git log`) or a named test that verifies it. This file records what has
landed on `main`; it is not a release announcement.

## [Unreleased] — v1-pending

`colmugx/acp` is a native-only MoonBit SDK for Agent Client Protocol (ACP)
v1. The v1 SDK scope is implemented and locally gated, but this is **not a
release**. Open items before any v1 release claim (per
`docs/implementation-plan/09-posoco-and-release-boundary.md`):
TypeScript/Rust four-way interoperation replays, CI reproducibility of the
release gates, the service-owned composition rows of the v1 matrix (C05
full session-replay e2e, G01 root assembly execution, G06 real terminal
truncation execution, G07 complete trace dimensions), and the final human
release review. The `experimental` package (ACP v2 Draft facade) contains
no implementation yet.

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
  --check`, `rtk git diff --check`), except that whole-module
  `rtk moon coverage analyze` is blocked by a toolchain quirk
  (`Sys_error("<module-root>/acp.mbt: No such file or directory")` inside
  `moon_cove_report.combine_coverages`); per-package coverage is recorded
  locally instead.

### Documentation

- Numbered user guide under `docs/guide/` plus README refresh. `8a08bd9`
- Protocol project baseline notes and repo hygiene (ignored generated
  interfaces, agent work files). `cf15295`, `00429b0`, `7f25f53`
- Guide/runtime coverage sync. `3a697e5`

### Compatibility commitments

Per `docs/implementation-plan/09-posoco-and-release-boundary.md`:

- Stable `colmugx/acp` targets ACP wire v1 only, on the native target
  only. The v1 method set and schema are locked to the pinned upstream
  commit recorded in `spec/LOCK.md`; the stable facade will not gain
  breaking changes without a new version, and no unstable or v2 name is
  vendored or exposed by the stable package.
- `colmugx/acp/experimental` is the future ACP v2 Draft facade. It is
  currently an empty placeholder; when implemented it is Draft-only,
  breaking changes may occur at any time, it must be imported explicitly
  and will never change root v1 behavior or goldens.
