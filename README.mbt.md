# colmugx/acp

MoonBit native SDK for the Agent Client Protocol (ACP).

V1 implementation is in progress and is not yet a publishable SDK. The current
baseline includes:

- strict typed JSON-RPC/ACP models and codecs;
- pure protocol reducers and lifecycle/capability checks;
- immutable Reader-composed Agent/Client endpoints;
- two-phase typed dispatch adapters;
- a native framing/runtime foundation.

The module is native-only and remains a pure protocol SDK. Responsibility is
organized recursively into MoonBit subpackages; every responsibility directory
has its own `moon.pkg`, and source filenames do not carry responsibility
prefixes (only `_test.mbt` and `_wbtest.mbt` suffixes are allowed). There are no
`v1/` or `v2/` implementation directories. The release facades are
`colmugx/acp` and the retained `colmugx/acp/experimental`. The root `top.mbt`
facade uses `pub using` for user-facing public types, enums, errors, functions,
and methods, while reducer, broker, and runtime state remain unexported.

`serve_stdio`, the public `ClientConnection`/outbound connection API,
TypeScript/Rust interoperability, and the v1 release gate are not complete.
The experimental package intentionally remains empty until the v1 gate passes;
no v2 code is included.

See the reviewed implementation plan in
[docs/implementation-plan/README.md](docs/implementation-plan/README.md).

The SDK remains independent from Posoco so it can later be integrated by
`posoco-ext-acp`.
