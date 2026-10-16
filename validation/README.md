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

`.github/workflows/ci.yml` runs units on Linux/macOS and these oracle groups on
macOS using pinned GitHub action revisions. The lifecycle job also runs the
smallest real editing trace on native. The workflow has been prepared locally;
it has not yet run in GitHub because the public repository is not created.

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
