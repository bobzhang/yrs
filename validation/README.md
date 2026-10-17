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

Both full matrices were rerun on 2026-10-17 against port commit `f6f0c467f3c55abbf07de6f98988fe523ee21ae8`
and unchanged Rust Yrs `ac339600c712642e556895426113c3f9c117de39`.
All 20 trace/GC/backend comparisons passed, including final content, state vectors,
two restart formats, and 80 bidirectional v1/v2 full-state imports. Release-mode
executables were frozen before each matrix; source and artifact hashes are in
every case. The [algorithm audit](ALGORITHM_AUDIT.md) explains the dependency and
content changes, ownership guarantees, and remaining implementation differences.

Host: Apple M2 Ultra, 24 CPU cores, 192 GiB RAM; macOS 26.4.1 arm64.
MoonBit 0.10.15+943464bfa / moon 0.1.20261012, Rust 1.97.1 and Node v25.8.2.
Matrices ran sequentially after the reference suites, with one measured run per
case. RSS is whole-process peak memory from macOS `/usr/bin/time -l`, in MiB.
Time includes startup, JSON parsing, two replicas, reverse/duplicate packet
transport, reconnects, encoding and restarts. Cross-import checks run separately
and are excluded from replay time. JavaScript includes Node/V8 overhead.
These are not retained-document-memory measures; no confidence intervals or
language-wide speed claims are inferred. The shared host is not isolated.

The previous audit's contended JavaScript batch remains available as
[historical diagnostic data](trace-js-contention-results.json). It is not part
of the new matrix below. The earlier complete reported matrices are in
[revision 573e3c8](https://github.com/bobzhang/yrs/tree/573e3c8/validation).

### MoonBit native versus Rust

| Trace | GC | Rust s | MoonBit s | Time ratio | Rust MiB | MoonBit MiB | RSS ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| friendsforever_flat | off | 0.507 | 0.543 | 1.07× | 7.0 | 9.8 | 1.40× |
| friendsforever_flat | on | 0.053 | 0.137 | 2.57× | 6.8 | 9.9 | 1.46× |
| sveltecomponent | off | 0.397 | 0.697 | 1.76× | 14.3 | 19.4 | 1.35× |
| sveltecomponent | on | 0.370 | 0.687 | 1.86× | 13.4 | 17.9 | 1.34× |
| rustcode | off | 1.887 | 2.120 | 1.12× | 32.1 | 59.0 | 1.84× |
| rustcode | on | 1.744 | 2.071 | 1.19× | 25.0 | 35.1 | 1.40× |
| seph-blog1 | off | 8.078 | 7.364 | 0.91× | 60.6 | 80.4 | 1.33× |
| seph-blog1 | on | 7.793 | 7.308 | 0.94× | 58.6 | 77.1 | 1.31× |
| automerge-paper | off | 12.578 | 21.661 | 1.72× | 94.3 | 121.3 | 1.29× |
| automerge-paper | on | 12.507 | 21.498 | 1.72× | 93.3 | 118.8 | 1.27× |

### MoonBit JavaScript versus Rust

| Trace | GC | Rust s | MoonBit s | Time ratio | Rust MiB | MoonBit MiB | RSS ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| friendsforever_flat | off | 0.263 | 0.421 | 1.60× | 6.9 | 113.7 | 16.50× |
| friendsforever_flat | on | 0.053 | 0.428 | 8.13× | 6.7 | 111.4 | 16.58× |
| sveltecomponent | off | 0.394 | 1.400 | 3.55× | 14.5 | 163.2 | 11.27× |
| sveltecomponent | on | 0.372 | 1.373 | 3.69× | 13.4 | 151.7 | 11.35× |
| rustcode | off | 1.909 | 4.326 | 2.27× | 33.0 | 328.3 | 9.95× |
| rustcode | on | 1.742 | 4.072 | 2.34× | 24.7 | 265.1 | 10.74× |
| seph-blog1 | off | 8.095 | 13.463 | 1.66× | 60.7 | 363.8 | 6.00× |
| seph-blog1 | on | 7.798 | 13.368 | 1.71× | 59.0 | 343.4 | 5.82× |
| automerge-paper | off | 12.772 | 38.267 | 3.00× | 95.3 | 428.1 | 4.49× |
| automerge-paper | on | 12.561 | 38.261 | 3.05× | 93.1 | 411.0 | 4.41× |

Rust was measured freshly alongside each target. Ratios greater than one mean
MoonBit used more time or peak memory. Rust used full-state catchups at some
checkpoints; MoonBit used none, reflecting the documented pending-integration
correction. This measures the same end-to-end scenario, not identical internal
work. Catchup counts, wire sizes, and state checks remain in the raw reports.

### Compared with the previous algorithm audit

The largest trace contains 259,778 transactions. These are separate single runs;
the change combines dependency scheduling, content storage and indexed-array reads.
It does not isolate individual contributions or eliminate system variation. Previous
measured code: `ef2d287`; reports committed in `573e3c8`.

| Backend | GC | Before MoonBit s | After MoonBit s | Time change | Before MiB | After MiB | RSS change |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| native | off | 24.457 | 21.661 | -11.4% | 118.0 | 121.3 | +2.8% |
| native | on | 23.779 | 21.498 | -9.6% | 117.6 | 118.8 | +1.1% |
| js | off | 37.677 | 38.267 | +1.6% | 422.0 | 428.1 | +1.5% |
| js | on | 37.819 | 38.261 | +1.2% | 407.8 | 411.0 | +0.8% |

For the largest GC-enabled case, the native MoonBit/Rust time ratio is 1.72×
(previously 1.70×); the JavaScript ratio is 3.05× (previously 2.85×). Rust also
ran faster in this batch. The lower native wall time therefore does not establish
an isolated speedup from these changes, and the JavaScript time is slightly higher.
The demonstrated algorithm improvements are the bounded dependency retries,
amortized append storage, and direct packed-array reads; ordinary trace costs
still include the remaining representation and retention differences.

Raw data: [native](trace-native-results.json), [JavaScript](trace-results.json).

### Append and dependency scaling probes

Run `python3 validation/algorithm_bench.py`. Text/array workloads commit each
single-element append separately. The dependency workload applies a reversed
cross-client chain in one update. No observers or replicas are involved. Timings
include process startup, input construction, final value checks and both wire
encodings. Encoded sizes must agree with Rust; complete compatibility evidence
comes from the reference suites and trace cross-imports, not byte lengths alone.
Each cell below is the median of three fresh processes, with runtime order rotated.
Startup overhead matters for the shortest cases. Samples, executable hashes and
source provenance are in [algorithm-bench-results.json](algorithm-bench-results.json).

| Workload | Operations | Rust s | Native s | JS s | Rust MiB | Native MiB | JS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| text | 20,000 | 0.2331 | 0.0498 | 0.1551 | 2.6 | 3.2 | 74.8 |
| text | 40,000 | 0.8985 | 0.0943 | 0.2129 | 2.6 | 3.5 | 76.7 |
| text | 80,000 | 3.5679 | 0.1805 | 0.3280 | 2.8 | 4.0 | 91.7 |
| array | 20,000 | 0.0153 | 0.0501 | 0.1723 | 3.2 | 4.1 | 82.2 |
| array | 40,000 | 0.0256 | 0.0957 | 0.2380 | 3.9 | 5.1 | 91.8 |
| array | 80,000 | 0.0450 | 0.1872 | 0.3595 | 5.9 | 7.3 | 121.6 |
| dependencies | 2,000 | 0.0077 | 0.0082 | 0.1122 | 4.1 | 5.0 | 78.0 |
| dependencies | 4,000 | 0.0137 | 0.0115 | 0.1339 | 5.7 | 7.3 | 89.2 |
| dependencies | 8,000 | 0.0379 | 0.0187 | 0.1724 | 9.0 | 11.6 | 111.8 |

The deterministic scheduler test additionally bounds attempts: 8,192 reversed
clients require 16,383 attempts instead of the former 33,558,528 visits. Content
storage tests verify prefix reuse across 10,000 appends and separate ownership
for frozen snapshots. Timings do not themselves prove asymptotic complexity. The text probe also
exercises a known implementation difference: pinned Rust's [`SplittableString::len`](https://github.com/y-crdt/y-crdt/blob/ac339600c712642e556895426113c3f9c117de39/yrs/src/block.rs#L1576)
recomputes UTF-16 length by scanning text during position lookup, whereas the port
keeps UTF-16/byte lengths and a local-position hint. That helps explain this
particular text-append result; it is not evidence of a generally faster language.
