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

## Performance after the 0.1.1 review fixes

Both full trace matrices were rerun on 2026-10-16 against port commit
`8342642d255fcf223762cc106984e773b048661f` and unchanged Rust Yrs
`ac339600c712642e556895426113c3f9c117de39`. All 20 trace/GC/backend
comparisons passed, including final content, state-vector checks, two restart
formats, and 80 bidirectional v1/v2 full-state imports. Both runtimes were rebuilt
in release mode and their executables frozen before each matrix. Every case
records the source revision/hash, executable hashes and trace checksum.

Host: Apple M2 Ultra, 24 CPU cores, 192 GiB RAM; macOS 26.4.1 arm64.
MoonBit 0.10.15+943464bfa / moon 0.1.20261012, Rust 1.97.1 and Node v25.8.2.
Native and JavaScript matrices ran sequentially, with one measured run per case.
RSS is whole-process peak resident memory from macOS `/usr/bin/time -l`, in MiB.
Elapsed time includes startup, JSON parsing, two replicas, reverse/duplicate
packet delivery, reconnects, serialization and restarts; cross-import checks run
in separate processes and are excluded from the tabulated replay times.
JavaScript RSS includes Node/V8. These are not local-edit microbenchmarks or
retained-document-memory measurements. No confidence intervals are inferred.

### MoonBit native versus Rust

| Trace | GC | Rust s | MoonBit s | Time ratio | Rust MiB | MoonBit MiB | RSS ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| friendsforever_flat | off | 0.495 | 0.666 | 1.34× | 7.0 | 9.5 | 1.35× |
| friendsforever_flat | on | 0.057 | 0.309 | 5.43× | 7.0 | 9.6 | 1.37× |
| sveltecomponent | off | 0.437 | 2.353 | 5.38× | 14.5 | 18.4 | 1.27× |
| sveltecomponent | on | 0.414 | 2.372 | 5.73× | 13.5 | 17.5 | 1.30× |
| rustcode | off | 2.112 | 8.778 | 4.16× | 31.4 | 46.5 | 1.48× |
| rustcode | on | 1.935 | 8.056 | 4.16× | 25.0 | 34.8 | 1.39× |
| seph-blog1 | off | 8.844 | 37.757 | 4.27× | 62.5 | 76.8 | 1.23× |
| seph-blog1 | on | 8.427 | 43.794 | 5.20× | 58.7 | 75.3 | 1.28× |
| automerge-paper | off | 13.862 | 117.067 | 8.45× | 96.0 | 117.8 | 1.23× |
| automerge-paper | on | 13.726 | 115.760 | 8.43× | 93.2 | 116.8 | 1.25× |

### MoonBit JavaScript versus Rust

| Trace | GC | Rust s | MoonBit s | Time ratio | Rust MiB | MoonBit MiB | RSS ratio |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| friendsforever_flat | off | 0.453 | 0.707 | 1.56× | 7.1 | 108.3 | 15.30× |
| friendsforever_flat | on | 0.057 | 0.709 | 12.35× | 6.8 | 108.2 | 15.82× |
| sveltecomponent | off | 0.431 | 3.511 | 8.14× | 14.8 | 231.2 | 15.67× |
| sveltecomponent | on | 0.403 | 3.543 | 8.78× | 13.7 | 195.4 | 14.31× |
| rustcode | off | 2.099 | 12.634 | 6.02× | 32.2 | 344.4 | 10.68× |
| rustcode | on | 1.886 | 12.855 | 6.82× | 25.6 | 289.6 | 11.33× |
| seph-blog1 | off | 8.696 | 53.334 | 6.13× | 60.8 | 359.4 | 5.91× |
| seph-blog1 | on | 8.736 | 54.682 | 6.26× | 59.3 | 346.1 | 5.84× |
| automerge-paper | off | 14.381 | 165.873 | 11.53× | 95.1 | 440.2 | 4.63× |
| automerge-paper | on | 13.395 | 168.716 | 12.60× | 94.9 | 436.3 | 4.60× |

The Rust measurements in each table are fresh runs made alongside that target.
Ratios greater than one mean MoonBit took more time or peak memory. Rust used
full-state catchups at some reconnects; the port used none, reflecting the
documented pending-integration correction. Catchup counts are retained per case.
The comparison measures completion of the same end-to-end scenario, not identical
internal work. Encoded v1/v2 byte lengths and final state checks also remain in
the JSON reports.

### Comparison with the previous saved measurements

The largest trace (`automerge-paper`, 259,778 transactions) compares as follows.
These are separate single runs; differences are descriptive and cannot isolate
which fixes or system variation caused a change. The previous native revision
was `43342d397e56802d083eeee9c6d860b673799fac`; JavaScript was
`e0542e95f2f5d526d6d0e328f8497dca065c10d5`.

| Backend | GC | Previous MoonBit s | Current MoonBit s | Time change | Previous MiB | Current MiB | RSS change |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| native | off | 117.239 | 117.067 | -0.1% | 117.9 | 117.8 | -0.1% |
| native | on | 119.912 | 115.760 | -3.5% | 116.7 | 116.8 | +0.0% |
| js | off | 155.068 | 165.873 | +7.0% | 442.2 | 440.2 | -0.4% |
| js | on | 184.774 | 168.716 | -8.7% | 434.1 | 436.3 | +0.5% |

Previous complete reports remain available in [the pre-rerun revision](https://github.com/bobzhang/yrs/tree/8342642d255fcf223762cc106984e773b048661f/validation).
Current raw data: [native](trace-native-results.json), [JavaScript](trace-results.json).
