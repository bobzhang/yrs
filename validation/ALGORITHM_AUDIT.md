# Algorithm audit against Rust Yrs

Audit date: 2026-10-17. Reference: unchanged Yrs 0.28.0 with `weak`, commit
[`ac339600c712642e556895426113c3f9c117de39`](https://github.com/y-crdt/y-crdt/tree/ac339600c712642e556895426113c3f9c117de39).
Starting port: `5836bae`; first-pass changes: `ea2f455`, `34521b5`, `21049c8`.
Dependency/content follow-up: `835be98`, `dd4578a`; scaling harness: `7dfa455`.

The sequence CRDT uses the same origin/right-origin conflict rules and client-ID
ordering as Rust. The old port did **not** match Rust's operational algorithms
in several important paths. This audit corrects several avoidable complexity
differences; it does not certify identical algorithms, allocations, or costs
throughout the library. Passing compatibility tests establishes their stated
behavioral coverage, not an asymptotic proof or universal performance parity.

## Source comparison and changes

| Path | Pinned Rust implementation | Port finding and action |
| --- | --- | --- |
| Sequence integration | `block.rs`: `detect_conflict`, `resolve_conflict`, transaction `integrate` | Compared origin equality, right-origin equality, client-ID tie-break, before-origin/conflicting sets, and neighbor reconnection against `Doc::integrate_missing`. These core ordering rules match. Sparse dependency scheduling is separately described below. |
| Block identity lookup | `block_store.rs`: `ClientBlockList::find_index` | Both use sorted per-client block arrays and binary search. Added a recent-tail fast path to `Doc::find` and `first_block_after`, retaining explicit gap handling. |
| Transaction compaction | `transaction.rs`: `commit`; `id_set.rs`: `try_squash_with` | Replaced a full scan of every changed client's history with normalized inserted/deleted/split/GC/unlinked clock ranges, including both boundary pairs. Work selects affected blocks with binary search. Array shifts still cost extra; content append storage is described below. |
| Merge eligibility | `block.rs`: `ItemPtr::try_squash` | Item checks agree on clock adjacency, origin, right-origin, sequence adjacency, deletion status, redone status, and weak-link exclusion. Keep marks and map heads survive merges. GC block packing is more conservative in the port. |
| Update events | `store.rs`: `emit_update_v1`, `emit_update_v2` | Removed unconditional serialization of both formats at every captured commit. Each format now encodes only on demand. A frozen owned payload preserves MoonBit's retained-transaction API after later edits and GC. Live transactions are never cached prematurely. |
| Sequence length | `branch.rs`: `content_len`; `types/text.rs`: `Text::len` | Replaced O(blocks) scans with maintained branch lengths and O(1) reads. Insertion/deletion update the count; splitting accounts for UTF-16 surrogate replacement in byte-offset documents. Arrays use the same cache. |
| Deletion accumulation | `ids.rs`: `IdRanges::insert_with` | Replaced copy/sort/rebuild of all prior ranges with a tail fast path, binary search, coalescing the overlap, and one suffix shift. Duplicate contained deletions no longer rebuild history. |
| Public range sets | `ids.rs`: insertion, union, exclusion, intersection | `IdSet::insert` now maintains canonical order, `contains` uses binary search, and union/difference/intersection use linear ordered walks instead of re-sorting unions or nested range scans. Flat global storage still differs from Rust's per-client tree. |
| Undo materialization | `id_set.rs`: block iteration; `transaction.rs`: clean block boundaries | `Doc::materialize_ranges` now binary-searches each affected range and snapshots only its intersecting blocks before splitting, instead of copying/scanning the full client history per range. Undo retention ownership remains a documented implementation difference. |
| Pending batches | `update.rs`: `BlockPicker`, `missing_dependency` | Replaced repeated fixed-point scans with exact-clock dependency waiters and a priority queue that preserves the former round/order. Each blocked block wakes only when its dependency is integrated; sparse ready blocks remain independent. This is not a literal copy of Rust BlockPicker. |
| Position search | `types/text.rs`: `find_position` | Rust scans from the branch head. The port additionally uses one local-edit hint for plain text and falls back to the head for formatted text. This is an optimization in the port, not a missing Rust search-marker tree. Both retain linear worst-case traversal. |
| Deletion application and GC | `transaction.rs`: `apply_delete`; `gc.rs` | Both split boundaries, visit covered blocks, retain early deletes, and collect nested deleted content while respecting undo retention. The port already restricts ordinary deletion replay to incoming/overlapping ranges. Retention refresh and weak unlinking still scan more broadly. |
| Update encoding | `updates/encoder.rs`, `update.rs`, block-store encoding | Both encode client/clock blocks, origins, content tags, and deletion ranges with v1/v2 codecs. Typed-v2 and bidirectional wire oracles test this. The port's generic encoder normalizes/sorts copied items; Rust can stream ordered store blocks more directly. |

The relevant MoonBit sources are [compaction](../compaction.mbt),
[transactions](../transaction.mbt), [store/integration](../text_store.mbt),
[clock ranges](../clock_ranges.mbt), [range sets](../id_set.mbt),
[undo](../undo.mbt), and [GC](../gc.mbt).

## Dependency and content corrections

`dependency_scheduler.mbt` indexes each missing clock to its provider in the
normalized batch. A blocked block registers one waiter; integration (including
partial integration) wakes waiters whose exact clocks now exist. Missing external
providers and cycles terminate without retry loops. A `(round, position)` priority
queue preserves the old deterministic scan order and its observer side effects.
An 8,192-client reversed dependency chain takes exactly 16,383 integration attempts,
versus 33,558,528 visits under the old repeated scans. The queue and provider index
add logarithmic overhead; this is dependency-driven scheduling, not a claim of
Rust's exact stack algorithm or constant factors. The existing two-phase handling
of incoming versus retained pending updates is unchanged.

`content_buffer.mbt` replaces immutable concatenation with append-only backing
arrays and bounded immutable views. Ordinary successive appends copy only the new
suffix, using the core array's amortized growth. Appending from an older fork copies
its prefix. Freezing an owned update seals the shared allocation so the next append
forks it: old retained transactions and decoded updates neither change nor pin
an allocation that continues growing forever. Public `Any` values remain immutable.

Text uses UTF-16 units with cached byte length and a lazily rendered string. Slices
copy only the selected range rather than walking the entire source text; copying
also keeps tiny surviving slices from pinning large deleted allocations. Orphaned
surrogate halves become U+FFFD permanently, even if rejoined. Full-range slices
reuse the immutable view. This removes the growing-prefix append penalty; it does
not make splitting, rendering, or captured whole-block forks free. UTF-16 storage
and cached rendered strings also differ from Rust's UTF-8 `String` memory layout.

The scaling probe also exposed `ArrayRef::get` materializing every value in a
packed block for a single lookup. It now indexes primitive/legacy content directly;
other single-value content keeps its existing conversion. Reading all N values
of one packed block therefore no longer performs N full-block copies. A 50,000
value indexed-read regression covers shuffled indices, boundaries and deletion.

Tests cover backing reuse across 10,000 appends, self-aliasing joins, old-view forks,
Unicode slices including empty slices and every surrogate boundary, retained
text/array transaction updates in both wire formats, and frozen-allocation lifetime.
The [scaling harness](algorithm_bench.py) compares append-only text, append-only
arrays and reversed dependency chains with unchanged Rust on native and JavaScript.

## Remaining algorithm and representation differences

These are open performance gaps, not claims of Rust algorithm parity:

1. **Block and GC storage:** neighbors are IDs resolved through a map instead of
   direct Rust item pointers. Client arrays shift on insertion/removal. Rust
   additionally packs consecutive GC blocks without item-origin constraints;
   the port's conservative item-shaped GC representation can retain more blocks.
   This audit did not replace the store with an arena or rewrite GC topology.
2. **Retention and weak links:** refreshing undo keep marks can scan retained
   history; unlinking a weak reference scans items/branches. Rust has different
   ownership/indexing machinery. The port's multi-manager retention fixes must
   survive any future index-based replacement.
3. **Serialization:** sorting/copying a generic block batch and freezing retained
   transaction payloads add work that Rust's borrowed transactions/ordered store
   can avoid. Lazy encoding removes the unused format, not all this overhead.

Consequently, the earlier slowdown cannot be attributed to MoonBit versus Rust
as languages. These are different data layouts and, in these remaining paths,
different operational algorithms implementing compatible CRDT behavior.

## First-pass verification

- 203 unit tests passed on native, JavaScript, wasm, and wasm-gc.
- Warnings-as-errors checks passed for all targets; generated public API is
  unchanged (225 declarations, 802 members, 23 capability/adaptation groups).
- New compaction checks run 1,440 seeded mixed edits across GC modes, plus
  remote/duplicate updates, sparse histories, and split-only transactions.
  A full-history sweep must find no extra merge and change no wire bytes.
  This oracle is the old port sweep, **not** a proof of Rust-identical packing.
- Length caches are checked against independent linked-block scans during mixed
  edits and 6,400 Unicode/offset/GC position scenarios.
- 3,000 range insertions agree with batch normalization, including extreme
  clocks and empty-client metadata. Set algebra is checked against independent
  point sets, including overlapping ranges, holes, and multiple clients.
- Retained transactions are first encoded only after subsequent edits, child
  load/destroy, and GC; tests also cover live transaction reads and typed v2
  values that cannot be faithfully projected through JSON.

All 13 reference suites (44 oracle commands) passed for library source hash
`2514c18182551c55aaf2bd57351df48c86e630b368089efeb2a8c7ff8fea0c09`.
The core matrix covers 641 scenarios, 364,568 independent-operation snapshots,
546,816 wire-replay snapshots, and 109,400 same-state local operations. The
reference corrections remain explicitly asserted; see
[REFERENCE_LIMITATIONS.md](REFERENCE_LIMITATIONS.md). The post-change trace
reports additionally identify the exact source and executable hashes measured.


## First-pass measured effect

All 20 final trace/GC/backend comparisons passed, including 80 bidirectional
v1/v2 imports. On the largest GC-enabled trace (259,778 transactions), native
fell from 115.760 s before the audit to 23.779 s, versus 13.977 s for fresh Rust:
about 4.9 times faster than the previous port, with the Rust gap reduced from
8.43 times to 1.70 times. Native peak RSS was 117.6 MiB versus 93.9 MiB for Rust,
roughly unchanged from the port's earlier 116.8 MiB.

JavaScript fell from 168.716 s to 37.819 s; fresh Rust measured 13.273 s in that
matrix. The complete first JavaScript attempt is retained with a host-contention
note. The reported matrix is a complete repeat after the observed Git CPU burst
subsided, not a selection of the fastest cases.

These single-run whole-process measurements support a substantial improvement,
not an isolated attribution to each change or a language-speed conclusion. Rust
still performs full-state catchups that the port's corrected dependency handling
avoids. See the [full tables and methodology](README.md#performance-after-the-algorithm-audit)
for all traces, memory measurements, provenance and limitations.
