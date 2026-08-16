# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` generates the package interface artifact. The generated `.mbti`
  files are automatic outputs, not hand-maintained specifications; do not
  manually inspect, compare, or edit their contents. Public API behavior is
  established by source, `moon ide` queries, and black-box consumer tests.

- In the last step, run `rtk moon info --target native` and then `rtk moon fmt`.
  Treat any `moon info` failure as a blocking error; successful generation is
  the interface gate, and no manual `.mbti` content/diff review is required.

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.

## ACP implementation direction

- The implementation plan is rooted at
  `docs/implementation-plan/README.md`; update it together with material scope,
  protocol pin, package, target, or release-gate changes.
- The module has two release facades:
  `colmugx/acp` for stable ACP wire v1 and
  `colmugx/acp/experimental` for the ACP v2 Draft baseline. The implementation
  is recursively split into responsibility subpackages such as `agent/`,
  `client/`, `connection/`, `jsonrpc/`, `method/`, `protocol/`, `runtime/`,
  and `transport/`; each package directory has its own `moon.pkg`. These
  implementation packages are not additional release/version facades.
- Express responsibility with package directories, not filename prefixes. Do
  not create files such as `connection_runtime.mbt`; put the leaf file under
  the responsible package directory. Only `_test.mbt` and `_wbtest.mbt`
  suffixes are allowed for test files. Do not create `v1/` or `v2/`
  implementation directories; retain `experimental/` as the experimental
  facade.
- The root facade file `top.mbt` uses `pub using` to re-export all user-facing
  public types, enums, errors, functions, and methods. Internal reducer,
  broker, and runtime state must remain unexported.
- The current supported target is native only. Protocol stdout must contain
  newline-delimited ACP JSON-RPC frames only; diagnostics go to stderr or an
  explicitly injected trace sink.
- Keep a pure protocol reducer separated from native async effects. Runtime
  code interprets reducer commands and reports success/failure back as events;
  it must not duplicate lifecycle state.
- Do not use builder/fluent-registration APIs. Compose immutable typed service
  values, derive capabilities from service presence, and construct each
  endpoint once with labeled arguments and fail-fast validation.
- Do not use global mutable state, singletons, or a service locator. Use
  `colmugx/reader` at the composition root for caller-owned immutable
  dependency environments. Keep connection/session state explicit in the
  reducer, runtime scope, or application store rather than Reader `Env`.
- Stable v1 must pass its complete schema/method matrix plus the pinned-schema
  drift gate and the in-repo stdio interop evidence before v2 implementation
  begins; cross-SDK interop validation is downstream consumer work.
- `colmugx/acp` must remain independent from Posoco. Future
  `posoco-ext-acp` owns the Posoco adapter and depends on both projects.
