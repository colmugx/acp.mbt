# ACP protocol input lock

This lock names the only upstream input accepted by the v1 method manifest and
by the v2 stable-baseline experimental manifest.  The
upstream revision is immutable; `main`, a release branch, an SDK version, or a
schema package version is not an input.

Pinned repository commit:

`b8dd9b24050f5d4882711656f30b1dbde0087d75`

The v1 schema and v1 stable method metadata were retrieved at this exact
commit and hashed locally during the 2026-08-11 audit.  The v2 stable-baseline
pair was retrieved, verified, and landed on 2026-08-18 (see below).  The v1
unstable artifacts remain unretrieved: their recorded IDs are retained only as
unverified candidates and must not be used as reproducibility evidence.

| artifact | role | fixed raw URL | Git blob ID | local SHA-256 |
| --- | --- | --- | --- | --- |
| `schema/v1/schema.json` | v1 stable schema | <https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/b8dd9b24050f5d4882711656f30b1dbde0087d75/schema/v1/schema.json> | `a01db8187e2684a5583b36dbdf938362a4ed10e5` | `7f1fba1561163729115247df75b67aeed02085115fbc7ef0131fb01d456c08f9` |
| `schema/v1/meta.json` | v1 stable method metadata | <https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/b8dd9b24050f5d4882711656f30b1dbde0087d75/schema/v1/meta.json> | `b9c67caa417dd2285a31d07309a215a6110bbfaf` | `061edb6efa8fb2aa2792459a86ec7268de5fe665bba48b2ffe7939df01481f88` |
| `schema/v1/meta.unstable.json` | v1 unstable exclusion metadata | <https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/b8dd9b24050f5d4882711656f30b1dbde0087d75/schema/v1/meta.unstable.json> | candidate `d8937f3841efd05d7e39f163c3ee87599906d6e0` (unverified) | not retrieved |
| `schema/v2/schema.json` | v2 stable-baseline Draft schema | <https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/b8dd9b24050f5d4882711656f30b1dbde0087d75/schema/v2/schema.json> | `de043e9ff03396e691df9e78a0da32746d3352ef` | `9480f7224002f60725e2bd509725c40cd76bd391627a95d62d08d1b2e948e43c` |
| `schema/v2/meta.json` | v2 stable-baseline Draft method metadata | <https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/b8dd9b24050f5d4882711656f30b1dbde0087d75/schema/v2/meta.json> | `ad2cfd937a0722893fa577e4ff96df5c79cdc23c` | `ad94c01f2736416776fd53d66e3aaf89242ab72d99832664f39d6ab41e049736` |
| `schema/v2/meta.unstable.json` | v2 unstable exclusion metadata | <https://raw.githubusercontent.com/agentclientprotocol/agent-client-protocol/b8dd9b24050f5d4882711656f30b1dbde0087d75/schema/v2/meta.unstable.json> | `47d7973cb4323875069b53447797b6be86cc1d1e` (verified 2026-08-18) | `2c274308d2a773628bf6316b7f6c535cf87d2c1ceb495d02be9ee899dce0f0bc` |

Their Git blob IDs came from `git hash-object`; their SHA-256 values came from
`shasum -a 256`.

On 2026-08-16 the two verified artifacts were re-fetched from their fixed raw
URLs at the pinned commit and landed in-repo, byte-identical to the audited
hashes above: `spec/schema/v1/schema.json` (Git blob `a01db8187e2684a5583b36dbdf938362a4ed10e5`,
SHA-256 `7f1fba1561163729115247df75b67aeed02085115fbc7ef0131fb01d456c08f9`) and
`spec/schema/v1/meta.json` (Git blob `b9c67caa417dd2285a31d07309a215a6110bbfaf`,
SHA-256 `061edb6efa8fb2aa2792459a86ec7268de5fe665bba48b2ffe7939df01481f88`).
Only these two v1 stable artifacts are vendored for the stable v1 surface; no
unstable artifact is vendored.

On 2026-08-18 the two v2 stable-baseline artifacts were fetched from their
fixed raw URLs at the same pinned commit and landed in-repo, byte-identical to
the hashes above: `spec/schema/v2/schema.json` (Git blob `de043e9ff03396e691df9e78a0da32746d3352ef`,
SHA-256 `9480f7224002f60725e2bd509725c40cd76bd391627a95d62d08d1b2e948e43c`) and
`spec/schema/v2/meta.json` (Git blob `ad2cfd937a0722893fa577e4ff96df5c79cdc23c`,
SHA-256 `ad94c01f2736416776fd53d66e3aaf89242ab72d99832664f39d6ab41e049736`).
They are vendored only as the input for the `colmugx/acp/experimental` v2
stable-baseline Draft facade (plan 08) and are never consumed by the stable v1
packages.  `schema/v2/meta.unstable.json` was fetched read-only on the same
date and verified (blob and SHA-256 above) but is deliberately not vendored:
it is an exclusion reference, never an input.  `schema/v2/schema.unstable.json`
is not listed by this lock and was not retrieved; any unstable overlay is an
exclusion reference by plan 08, never an implementation input.

## Reproduction gate

The manifest is handwritten from the stable v1 method table in
`docs/implementation-plan/01-protocol-baseline.md` and its exact-set matrix in
`docs/implementation-plan/04-v1-completeness-matrix.md`.  It is not generated
from an unverified download.  Before calling this lock reproducible, fetch each
raw URL above at the pinned commit, calculate:

```text
git hash-object <file>
shasum -a 256 <file>
```

and replace only the corresponding `not retrieved` cells after independently
checking the bytes.  Until the remaining v1 unstable exclusion artifact is
retrieved and hashed, this lock is a reproducible v1 and v2 stable-baseline
input lock but not a complete offline v1/v2 comparison lock.  No unstable
overlay is vendored; the vendored v2 stable-baseline pair is consumed only by
the experimental facade, never by the stable v1 packages.

## Method-count note

The fixed tables in plans 01 and 04 enumerate 12 Client→Agent requests
(`C01`–`C12`), one Client→Agent notification (`C13`), nine Agent→Client
requests (`D01`, `D03`–`D10`), two Agent→Client notifications (`D02`, `D11`),
and one bidirectional notification (`$/cancel_request`).  The task shorthand
“13/2 and 11/3” does not match those tables' request/kind rows; the typed
manifest follows the table's explicit wire kinds and directions, not the
shorthand.  The manifest's exact-set test is therefore 25 entries and rejects
any extra v2 or unstable name.
