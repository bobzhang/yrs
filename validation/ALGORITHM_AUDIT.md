# Algorithm audit against Rust Yrs

Audit date: 2026-10-17. Reference: unchanged Yrs 0.28.0 with `weak`, commit
[`ac339600c712642e556895426113c3f9c117de39`](https://github.com/y-crdt/y-crdt/tree/ac339600c712642e556895426113c3f9c117de39).
Starting port: `5836bae`; implementation changes: `ea2f455`, `34521b5`, `21049c8`.

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
| Transaction compaction | `transaction.rs`: `commit`; `id_set.rs`: `try_squash_with` | Replaced a full scan of every changed client's history with normalized inserted/deleted/split/GC/unlinked clock ranges, including both boundary pairs. Work selects affected blocks with binary search. Array shifts and content copies still cost extra; see below. |
| Merge eligibility | `block.rs`: `ItemPtr::try_squash` | Item checks agree on clock adjacency, origin, right-origin, sequence adjacency, deletion status, redone status, and weak-link exclusion. Keep marks and map heads survive merges. GC block packing is more conservative in the port. |
| Update events | `store.rs`: `emit_update_v1`, `emit_update_v2` | Removed unconditional serialization of both formats at every captured commit. Each format now encodes only on demand. A frozen owned payload preserves MoonBit's retained-transaction API after later edits and GC. Live transactions are never cached prematurely. |
| Sequence length | `branch.rs`: `content_len`; `types/text.rs`: `Text::len` | Replaced O(blocks) scans with maintained branch lengths and O(1) reads. Insertion/deletion update the count; splitting accounts for UTF-16 surrogate replacement in byte-offset documents. Arrays use the same cache. |
| Deletion accumulation | `ids.rs`: `IdRanges::insert_with` | Replaced copy/sort/rebuild of all prior ranges with a tail fast path, binary search, coalescing the overlap, and one suffix shift. Duplicate contained deletions no longer rebuild history. |
| Public range sets | `ids.rs`: insertion, union, exclusion, intersection | `IdSet::insert` now maintains canonical order, `contains` uses binary search, and union/difference/intersection use linear ordered walks instead of re-sorting unions or nested range scans. Flat global storage still differs from Rust's per-client tree. |
| Undo materialization | `id_set.rs`: block iteration; `transaction.rs`: clean block boundaries | `Doc::materialize_ranges` now binary-searches each affected range and snapshots only its intersecting blocks before splitting, instead of copying/scanning the full client history per range. Undo retention ownership remains a documented implementation difference. |
| Pending batches | `update.rs`: `BlockPicker`, `missing_dependency` | Removed re-sorting on each retry pass: filtering an ordered batch preserves its order. The fixed-point scheduler itself still differs; see below. |
| Position search | `types/text.rs`: `find_position` | Rust scans from the branch head. The port additionally uses one local-edit hint for plain text and falls back to the head for formatted text. This is an optimization in the port, not a missing Rust search-marker tree. Both retain linear worst-case traversal. |
| Deletion application and GC | `transaction.rs`: `apply_delete`; `gc.rs` | Both split boundaries, visit covered blocks, retain early deletes, and collect nested deleted content while respecting undo retention. The port already restricts ordinary deletion replay to incoming/overlapping ranges. Retention refresh and weak unlinking still scan more broadly. |
| Update encoding | `updates/encoder.rs`, `update.rs`, block-store encoding | Both encode client/clock blocks, origins, content tags, and deletion ranges with v1/v2 codecs. Typed-v2 and bidirectional wire oracles test this. The port's generic encoder normalizes/sorts copied items; Rust can stream ordered store blocks more directly. |

The relevant MoonBit sources are [compaction](../compaction.mbt),
[transactions](../transaction.mbt), [store/integration](../text_store.mbt),
[clock ranges](../clock_ranges.mbt), [range sets](../id_set.mbt),
[undo](../undo.mbt), and [GC](../gc.mbt).

## Remaining algorithm and representation differences

These are open performance gaps, not claims of Rust algorithm parity:

1. **Pending dependencies:** Rust follows dependency clients with `BlockPicker`;
   the port retries unresolved batches to a fixed point. Adversarial chains
   spanning clients can cause quadratic retry work. A replacement must preserve
   eager independent integration, sparse-clock relay, and the scheduling
   regressions in `pending_scheduling.py`; copying Rust's observed stalls would
   undo intentional correctness fixes.
2. **Content storage:** merging strings/read-only value arrays copies both sides
   in the port. Rust appends into mutable `String`/`Vec` storage. Long append-only
   histories can therefore have different amortized costs even when block counts
   and wire bytes are identical. `utf16_slice` also walks a string to preserve
   valid surrogate replacement. A chunked or mutable content representation
   needs its own design and compatibility tests.
3. **Block and GC storage:** neighbors are IDs resolved through a map instead of
   direct Rust item pointers. Client arrays shift on insertion/removal. Rust
   additionally packs consecutive GC blocks without item-origin constraints;
   the port's conservative item-shaped GC representation can retain more blocks.
   This audit did not replace the store with an arena or rewrite GC topology.
4. **Retention and weak links:** refreshing undo keep marks can scan retained
   history; unlinking a weak reference scans items/branches. Rust has different
   ownership/indexing machinery. The port's multi-manager retention fixes must
   survive any future index-based replacement.
5. **Serialization:** sorting/copying a generic block batch and freezing retained
   transaction payloads add work that Rust's borrowed transactions/ordered store
   can avoid. Lazy encoding removes the unused format, not all this overhead.

Consequently, the earlier slowdown cannot be attributed to MoonBit versus Rust
as languages. These are different data layouts and, in these remaining paths,
different operational algorithms implementing compatible CRDT behavior.

## Verification

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

Full reference-suite and post-change benchmark results are recorded after the
stable implementation is validated. See `release-*-results.json` and the trace
reports; the source hashes identify exactly which implementation was measured.
