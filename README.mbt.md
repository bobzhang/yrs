# Yrs for MoonBit

A MoonBit port of Yrs, the Rust implementation of the Yjs CRDT. Work in progress; full upstream compatibility is the target, not a current claim.

The reference is Yrs 0.28.0 at `ac339600c712642e556895426113c3f9c117de39`, checked out in `.repos/y-crdt`. The implementation preserves Yjs item identities, conflict ordering, deletion semantics and binary updates. Public APIs use MoonBit constructors.

Implementation sequence:

1. Collaborative text and binary v1 update exchange against Rust, including concurrent and out-of-order edits.
2. Arrays, maps, nested types, rich text and XML on the same item store.
3. Binary v2, update utilities, sync and awareness protocols.
4. Transactions, observers, undo, snapshots, relative positions, subdocuments and the remaining pinned upstream surface.

Every milestone needs real Rust interoperability tests, rather than only MoonBit-to-MoonBit convergence tests. Validation evidence and remaining limitations will be recorded as each milestone lands.

## Implemented and checked

Collaborative plain text uses the upstream YATA conflict-ordering algorithm, UTF-16 clocks, state vectors, binary v1 and v2 updates, deletion ranges, duplicate suppression and pending dependency integration. Deleted content is retained. Shared arrays and maps use the same store, with immutable lib0 values (including binary, signed 64-bit integers, floating point, arrays and objects). The Rust oracle covers 641 scenarios in four wire-version/GC configurations: 364,568 independent operation comparisons, 546,816 binary replay snapshots, 109,400 local rich-text operations from identical starting states and 15,384 bidirectional document transfers. These include nested maps/arrays/text, parent replacement, concurrent child edits and rich text.

```mbt check
///|
test "two replicas exchange concurrent edits" {
  let a = @yrs.Doc(client_id=1UL)
  let b = @yrs.Doc(client_id=2UL)
  let left = a.get_or_insert_text("note")
  let right = b.get_or_insert_text("note")
  left.insert(0, "Hello")
  b.apply_update_v1(a.encode_state_as_update_v1())
  left.insert(5, " Moon")
  right.insert(5, " Rust")
  a.apply_update_v1(b.encode_state_as_update_v1(remote=a.state_vector()))
  b.apply_update_v1(a.encode_state_as_update_v1(remote=b.state_vector()))
  assert_eq(left.get_string(), "Hello Moon Rust")
  assert_eq(left.get_string(), right.get_string())
}
```

Rich text supports attributed insertion, formatting, JSON embeds and formatted deltas. A further 128 randomized histories exercise overlapping formatting, delayed/duplicate delivery and local edits from identical serialized states. The oracle replays identical binary histories in both implementations because upstream Rust attribute-map iteration makes independently generated rich-text histories nondeterministic. Adjacent string delta chunks with equal attributes are compared as one chunk; values, attributes, embeds and imported state vectors remain checked.

XML fragments, elements, attributes, formatted XML text and parent navigation now share the CRDT store. A further 128 randomized XML histories pass in v1/v2 with Rust GC both enabled and disabled (91,136 operation snapshots and 3,072 cross-runtime document transfers). XML insertion preserves upstream tombstone boundary choices.

Current limitations: unsupported content is rejected before applying an update. The remaining shared types, undo and some transaction/event APIs are still outstanding. Adjacent CRDT blocks are compacted; upstream garbage collection and indexing work remain. This is not a production release or a completed port.

Run `moon test --target all` and `python3 validation/compare.py`. The oracle uses the installed Rust 1.97.1 toolchain and the exact reference checkout under `.repos/y-crdt`; its Cargo dependencies are locked. Clone `https://github.com/y-crdt/y-crdt.git` there and check out `ac339600c712642e556895426113c3f9c117de39` before running it.

Binary v2 currently uses a checked conversion layer around the common v1 integration path. It implements unsigned, difference and byte RLE columns, UTF-16 string lengths, key dictionaries and delta delete sets. This favors one integration implementation over minimum intermediate allocation. `convert_update_v2_to_v1` defaults to a configurable 1,000,000-item expansion budget; lib0 nesting is bounded at 256.

Sparse updates can integrate beyond missing clock ranges when their dependencies are available. State vectors report only contiguous prefixes; `has_missing_updates()` reports holes, pending dependencies and early deletions. Full-state encoding forwards pending blocks. Stateless `merge_updates_v1/v2`, `diff_updates_v1/v2` and `encode_state_vector_from_update_v1/v2` preserve item identities and gaps without integrating a document.

`python3 validation/updates.py` checks partial-history relays and stateless utilities against Rust: 4,416 independent snapshots, 36,432 identical-wire replay snapshots and 352 merge/diff cases passed. The pinned reference has GC and sparse-v2 defects; explicit failures and reproduction instructions are recorded in [validation/REFERENCE_LIMITATIONS.md](validation/REFERENCE_LIMITATIONS.md) and [validation/update-results.json](validation/update-results.json). These results do not establish compatibility for reference cases that crash or emit overflowing clocks.

Sync and presence: `Awareness(doc, clock=...)` implements Yjs presence clocks,
raw JSON state, change/update observers, disconnect notices and local-state
protection. The explicit millisecond clock keeps the API portable and testable.
`start_sync`, `handle_sync`, `Message`, and `encode_messages` implement the default
y-sync handshake, incremental updates, awareness queries and authorization
responses. A packet is processed in order, matching upstream partial application
when a later message is invalid. Custom protocol dispatch can use decoded messages;
the default handler rejects unsupported custom tags.

`python3 validation/presence.py` checks 128 randomized scenarios against pinned
Rust Yrs: 33,024 operation snapshots (including presence metadata and observer
events) and 768 cross-runtime awareness transfers. The wire codec also has fixed
byte fixtures and malformed-packet tests. Presence observers are implemented;
document transaction and collection observers are described below.

Persistent positions: sequence `sticky_index` methods track item identities through
concurrent insertion and deletion; `sticky_boundary` tracks a type's start/end.
`StickyIndex` supports Yjs binary and cursor JSON interchange, including exact
64-bit client IDs. `get_offset` resolves a position in another document replica.

Historical states: `snapshot()` captures insert clocks and observed deletions.
Snapshots support v1/v2 codecs and `encode_state_from_snapshot_v1/v2` reconstructs
historical documents from retained content. Snapshot metadata is owned and cannot
be changed through a returned state-vector handle. Remote garbage collection can
still discard content needed for older snapshots.

`python3 validation/history.py` checks 64 randomized histories in both wire formats:
847,002 resolved cursor offsets, 116,976 historical reconstructions and 12,724
cross-runtime payloads. Historical content is checked against Rust state captured
at snapshot creation because of the pinned encoder defect documented in
`validation/REFERENCE_LIMITATIONS.md`; snapshot metadata is independently decoded
and compared in both runtimes. Persistent positions now follow local undo/restoration identities.

Transactions: `doc.transact(action, origin=...)` groups edits into one commit.
Existing mutation methods open an implicit transaction when needed. Document
observers cover before-observer, after-transaction, cleanup and v1/v2 update
phases. Transaction handles expose origin, locality, insertion/deletion ranges,
and stable committed state vectors and updates. Raising from the action commits
the edits already made. Observer callbacks can read their document. The after-transaction hook can
append edits to the current commit; other observer phases reject mutations of
the observed document.

`python3 validation/transactions.py` compares 160 randomized grouped-edit histories
in both wire formats with Rust: 44,160 transaction snapshots, 193,988 lifecycle
events and 61,508 emitted updates replayed into independent replicas. Map, text
and array observers report transaction-level changes; 10,718 map events, 16,782
rich-text events and 12,182 array events match Rust. The suite caught and fixed
rich-text positioning before tombstones and formatting transitions in event
deltas. Equivalent adjacent delta operations are consolidated for comparison;
sibling collection-event order is unspecified upstream. Newly created or deleted
nested types do not produce their own events. Undo validation and its current limits are described below. The full 641-scenario interoperability suite also passed again after
the transaction foundation landed.

Deep observation: every shared collection supports `observe_deep` and
`unobserve_deep`. Batches contain typed `Event` values, sorted by path depth;
`path()` is relative to the subscribed collection and uses final sequence indexes.
Event paths and deltas remain owned after the callback. XML element/fragment and
XML text observers combine attribute changes with child or rich-text deltas.
Imported root types acquire their event kind when a typed root handle is obtained.

`python3 validation/events.py` checks 96 randomized nested/XML histories in both
wire formats: 32,256 transaction snapshots, 55,344 notification batches and 71,910
deep events. It covers grouped changes, shifted paths, parent replacement,
deleted/new descendant suppression and concurrent remote updates. Events of equal
path depth and independent subscription batches have unspecified upstream order;
the oracle compares their contents after sorting, while checking depth order.

Selective undo: `UndoManager[M](clock=...)` tracks scoped collections across
transactions and documents. Use `expand_scope` with a shared `Out` handle, then
`undo`, `redo`, `reset`, origin filters and stack-clearing methods. Metadata has a
`Default` value and can be changed by stack observers. Restored content receives
new CRDT identities; persistent positions follow local restoration chains.

`python3 validation/undo.py` validates one editing replica with remote followers:
96 randomized histories, 34,176 transaction snapshots across v1/v2, and 1,152
bidirectional Rust/MoonBit full-state transfers. It compares rendered structures,
rich-text attributes, stack depths and undo/redo return values. Rust's unordered
restoration can produce several outcomes; each accepted alternative must match
an entire MoonBit history prefix in a fresh reference run. These runs are
recorded in `validation/undo-results.json`. No mismatching history is silently
excluded. Exact observer events during independently generated undo histories
are outside this comparison.

**Undo is not fully compatible yet.** `YRS_UNDO_CONCURRENT=1 python3
validation/undo.py` exercises multiple independently editing/undoing replicas;
this currently finds differences in concurrent restoration histories. A retained
case is `validation/fixtures/undo-concurrent-identity-history.json`. Initial
stack import/export and the rest of the upstream undo event surface also remain.
See `validation/REFERENCE_LIMITATIONS.md` for reference nondeterminism evidence.

The full 641-scenario core interoperability suite passed again after block
compaction and the map-head split correction. Unit regressions cover compaction,
remote-edit preservation, repeated nested restoration, cursor tracking and
multiple documents. Remaining major milestones are concurrent undo compatibility,
document/offset options, remaining shared types and APIs, garbage
collection, and performance/stress validation. A public release and repository
completion claim are still pending those milestones.

Subdocuments can be inserted into maps and arrays using `insert_doc`. Supply an
explicit globally unique `guid` when creating a child. Parent updates carry the
child's identity and options; exchange the child's updates separately to sync
its content. `observe_subdocs` reports added, removed and loaded handles;
`load`, `destroy`, `parent_doc`, `subdocs` and `subdoc_guids` expose the lifecycle.
Children inherit the parent's client ID and, unless set, collection ID.

`python3 validation/subdocs.py` compares 96 randomized three-replica histories
against Rust in both wire formats: 30,336 snapshots, 17,104 lifecycle events and
1,152 cross-runtime wire replay cases. Another 10,112 snapshots exercise explicit
destroy/reload. That matrix excludes the reference's stale destroyed-handle
registry while checking the port's live-registration invariant; see
`validation/REFERENCE_LIMITATIONS.md`. Decoded GC/offset options are preserved on
the wire; actual garbage collection remains outstanding. Subdocument data providers and globally unique GUID generation are
host responsibilities.


`Doc(client_id=..., offset_kind=Bytes)` supports UTF-8 byte offsets for text
editing and events. The default remains `Utf16` for Yjs interoperability;
replicas may use different offset modes while exchanging identical updates.
Insert, remove and format offsets in byte mode must fall on Unicode character
boundaries. CRDT state-vector clocks always remain UTF-16 code units.
`python3 validation/offsets.py` validates 96 randomized mixed-mode histories,
34,176 snapshots, 27,770 text events and 1,152 wire replay cases across v1/v2.
These cover Chinese, astral characters, combining accents and ZWJ emoji. This
matrix does not yet establish Unicode sticky-position parity.
