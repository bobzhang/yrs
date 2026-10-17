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

## Performance after the algorithm audit

Both full matrices were rerun on 2026-10-17 against port commit `ef2d287bf296e78888e0710cd6c90da4b9121c4a`
and unchanged Rust Yrs `ac339600c712642e556895426113c3f9c117de39`.
All 20 trace/GC/backend comparisons passed, including final content, state vectors,
two restart formats, and 80 bidirectional v1/v2 full-state imports. Release-mode
executables were frozen before each matrix; source and artifact hashes are in
every case. The [algorithm audit](ALGORITHM_AUDIT.md) explains the changes and
remaining implementation differences.

Host: Apple M2 Ultra, 24 CPU cores, 192 GiB RAM; macOS 26.4.1 arm64.
MoonBit 0.10.15+943464bfa / moon 0.1.20261012, Rust 1.97.1 and Node v25.8.2.
Matrices ran sequentially after the reference suites, with one measured run per
case. RSS is whole-process peak memory from macOS `/usr/bin/time -l`, in MiB.
Time includes startup, JSON parsing, two replicas, reverse/duplicate packet
transport, reconnects, encoding and restarts. Cross-import checks run separately
and are excluded from replay time. JavaScript includes Node/V8 overhead.
These are not local-edit microbenchmarks or retained-document-memory measures;
no confidence intervals or language-wide speed claims are inferred.

The first post-audit JavaScript matrix encountered a burst of unrelated CPU-heavy
Git processes. Its complete measurements are retained in
[trace-js-contention-results.json](trace-js-contention-results.json). The table
below uses one complete repeat after that burst subsided, not selected best cases.
The shared host is not an isolated benchmark machine; residual variation remains.

### MoonBit native versus Rust

| Trace | GC | Rust s | MoonBit s | Time ratio | Rust MiB | MoonBit MiB | RSS ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| friendsforever_flat | off | 0.491 | 0.537 | 1.09× | 7.3 | 9.7 | 1.33× |
| friendsforever_flat | on | 0.058 | 0.133 | 2.29× | 6.9 | 9.6 | 1.40× |
| sveltecomponent | off | 0.419 | 0.704 | 1.68× | 14.5 | 18.2 | 1.26× |
| sveltecomponent | on | 0.398 | 0.715 | 1.80× | 13.5 | 17.4 | 1.29× |
| rustcode | off | 2.054 | 2.185 | 1.06× | 32.7 | 54.8 | 1.68× |
| rustcode | on | 1.931 | 2.164 | 1.12× | 25.8 | 34.4 | 1.33× |
| seph-blog1 | off | 8.419 | 7.441 | 0.88× | 61.8 | 76.9 | 1.24× |
| seph-blog1 | on | 8.092 | 7.962 | 0.98× | 58.7 | 75.8 | 1.29× |
| automerge-paper | off | 13.583 | 24.457 | 1.80× | 95.3 | 118.0 | 1.24× |
| automerge-paper | on | 13.977 | 23.779 | 1.70× | 93.9 | 117.6 | 1.25× |

### MoonBit JavaScript versus Rust

| Trace | GC | Rust s | MoonBit s | Time ratio | Rust MiB | MoonBit MiB | RSS ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| friendsforever_flat | off | 0.465 | 0.431 | 0.93× | 7.1 | 107.3 | 15.13× |
| friendsforever_flat | on | 0.061 | 0.441 | 7.18× | 7.0 | 107.0 | 15.32× |
| sveltecomponent | off | 0.455 | 1.511 | 3.32× | 15.1 | 172.5 | 11.40× |
| sveltecomponent | on | 0.412 | 1.448 | 3.51× | 13.6 | 158.8 | 11.69× |
| rustcode | off | 2.144 | 5.218 | 2.43× | 34.9 | 351.7 | 10.08× |
| rustcode | on | 1.999 | 4.193 | 2.10× | 26.9 | 289.2 | 10.75× |
| seph-blog1 | off | 8.566 | 12.991 | 1.52× | 61.2 | 350.9 | 5.73× |
| seph-blog1 | on | 8.229 | 12.849 | 1.56× | 58.7 | 343.1 | 5.85× |
| automerge-paper | off | 13.636 | 37.677 | 2.76× | 95.0 | 422.0 | 4.44× |
| automerge-paper | on | 13.273 | 37.819 | 2.85× | 93.4 | 407.8 | 4.37× |

Rust was measured freshly alongside each target. Ratios greater than one mean
MoonBit used more time or peak memory. Rust used full-state catchups at some
checkpoints; MoonBit used none, reflecting the documented pending-integration
correction. This measures the same end-to-end scenario, not identical internal
work. Catchup counts, wire sizes, and state checks remain in the raw reports.

### Compared with the pre-audit measurements

The largest trace contains 259,778 transactions. These are separate single runs;
the change combines several algorithm fixes and does not isolate individual
contributions or eliminate system variation. The previous measured code was
`8342642`, with reports committed in `5836bae`.

| Backend | GC | Before MoonBit s | After MoonBit s | Time change | Before MiB | After MiB | RSS change |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| native | off | 117.067 | 24.457 | -79.1% | 117.8 | 118.0 | +0.2% |
| native | on | 115.760 | 23.779 | -79.5% | 116.8 | 117.6 | +0.7% |
| js | off | 165.873 | 37.677 | -77.3% | 440.2 | 422.0 | -4.1% |
| js | on | 168.716 | 37.819 | -77.6% | 436.3 | 407.8 | -6.5% |

Previous reports: [pre-audit revision](https://github.com/bobzhang/yrs/tree/5836bae/validation). Current raw data: [native](trace-native-results.json), [JavaScript](trace-results.json).
