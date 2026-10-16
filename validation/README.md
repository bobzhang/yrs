# Reproducing the compatibility checks

Use MoonBit `0.10.15+943464bfa`, Node.js 24, Python 3, and Rust 1.97.1.
The tested Moon CLI version is `0.1.20261012`. The Rust oracle is Yrs 0.28.0
with `weak` enabled at the exact commit below; its source must stay unchanged.

From the repository root, if the reference checkout does not already exist:

```sh
git clone https://github.com/y-crdt/y-crdt.git .repos/y-crdt
git -C .repos/y-crdt checkout --detach ac339600c712642e556895426113c3f9c117de39
rustup toolchain install 1.97.1 --profile minimal
npm ci --ignore-scripts --prefix validation/yjs
```

The Yjs lockfile pins 13.6.27. Each Python runner builds its MoonBit and Rust
bridges as needed. Do not update dependencies or patch the reference to make an
oracle pass.

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target all
moon info
python3 validation/typed_v2.py
python3 validation/compare.py
python3 validation/contracts.py
python3 validation/handles.py
python3 validation/value_decode.py
python3 validation/protocol_codec.py
python3 validation/sparse_wire.py
python3 validation/pending.py
python3 validation/pending_scheduling.py
python3 validation/transactions.py
python3 validation/presence.py
```

The complete release gate is split into 13 suites, shared by local validation
and `.github/workflows/ci.yml`. Run one with:

```sh
python3 validation/release.py --suite weak
python3 validation/api_contract.py
```

Available suites: `core`, `values`, `contracts`, `wire`, `history`, `lifecycle`,
`weak`, `undo`, `undo-yjs`, `undo-yjs-native`, `undo-high-clocks`, `undo-observer`,
and `undo-observer-native`. After all suites finish,
`python3 validation/release.py --verify` rejects missing/failed runs or library
source hashes different from the current checkout. Per-command logs are saved
under `_build/release-logs/`. CI retains these logs and the detailed JSON reports.
Unit tests run on both Linux and macOS, across all four MoonBit targets.

The core JavaScript bridge reads scenarios incrementally and writes results
synchronously so pipe backpressure bounds queued output. The original buffered
`console.log` loop exhausted the hosted Node heap on the full oracle run. To
repeat the release check with the same 2 GiB heap bound:

```sh
NODE_OPTIONS=--max-old-space-size=2048 python3 validation/release.py --suite core
```

The Rust-owned GC failure is asserted by `undo_gc.py`; the ordinary Rust gate
uses mixed authors with GC disabled and MoonBit authors with GC enabled. Mixed
Yjs authors are checked in both GC modes on JS and native. These choices are
explicit in the runner; unchanged strict Rust diagnostics remain available.


For longer editing and memory checks on macOS:

```sh
python3 validation/traces.py --target native
python3 validation/traces.py --target js
```

These commands replay all five bundled reference traces with GC enabled and
disabled. The RSS measurement currently uses macOS `/usr/bin/time -l`; its
numbers include the whole process and are not microbenchmarks.

The other runners cover focused history, cursor, attribution, weak reference,
subdocument, JSONPath, and concurrent undo scenarios. Their matching
`*-results.json` files record scope and counts. A runner may exit successfully
while reporting an explicitly expected reference exception or partial parity:
that verifies the stated invariants, not full compatibility. Consult
[`REFERENCE_LIMITATIONS.md`](REFERENCE_LIMITATIONS.md) and
[`../COMPATIBILITY.md`](../COMPATIBILITY.md) before interpreting a green CI run.

`python3 validation/embeds.py` exercises inherited and explicit embed formatting,
shared map/array/text embeds, concurrent edits, identical-wire replay and
bidirectional v1/v2 imports through the main three-replica bridge.

`python3 validation/prelims.py` checks XML copies, typed attribute stringification
and concurrent insertion around tombstones, using independent replicas and
bidirectional v1/v2 imports.

`python3 validation/public_api.py --check` regenerates the public declaration
inventory using the pinned Rust compiler's rustdoc JSON (with `RUSTC_BOOTSTRAP=1`
limited to that documentation subprocess). It follows public modules and
reexports and records inherent methods, trait members, public fields and enum
variants. External/blanket trait implementations are not counted. The inventory
is a checklist for the API audit, not a compatibility score. `--cached --check`
uses the previously generated rustdoc JSON.

`python3 validation/value_encode.py` compares the `ToAny` application adapter
with Rust serde serialization, retaining exact numeric variants and float bits.
It covers custom records, nested unsigned overflow, byte buffers, optional values
and the recursive Undefined-to-Null normalization performed by serde.

`python3 validation/any_stream.py` checks that generic lib0 value readers consume
exactly one value, preserve application frame bytes, reject truncations, and
that unchanged Rust decodes every port generic-writer output without loss.
Large integer encoding may differ in size from Rust; it preserves all bits.

The sparse relay oracle has an explicit `--eager-reference` harness mode. Pinned
Yjs decodes and splits original updates into complete struct packets; unchanged
Rust applies those original operations repeatedly with pending buffers pruned
until its integrated state stops changing. It does not patch Rust's integration
code or replace values with MoonBit results. Every MoonBit intermediate snapshot
must equal that causal fixed point. Ordinary Rust scheduling remains exercised
in the core suite, producer histories and the retained pending witnesses.

The weak oracle separates construction from reads: new quotations must equal
independently computed visible slices, while Rust- and MoonBit-authored wire
histories are replayed into both engines for query/observer comparisons. This
prevents corrected starting identities from concealing a query or event defect.

The 0.1.1 review adds `typed_v2.py` to the values release gate, bringing the matrix
to 13 suites and 44 commands. Its unchanged Rust and MoonBit bridges independently
assert Buffer, Undefined and exact Int64 embeds and attributes, exchange both
authors' packets, and re-export them across both runtimes again. Public API tests
add pending, generic, historical and retained-transaction coverage. The review
record and associated GitHub issues are in [reviews/2026-10-16-ultra.md](reviews/2026-10-16-ultra.md).
