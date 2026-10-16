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

Current limitations: full compatibility is not yet established for sparse intermediate states, weak-reference queries/events, and independently allocated concurrent undo histories. Real editing traces now pass on JavaScript and native, with a substantial speed gap versus Rust; results are below. The core shared types, undo, transactions and protocols described below are implemented. This is not a production release or a completed port.

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
when a later message is invalid. `Protocol` and `AsyncProtocol` allow overriding individual handlers;
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

**Undo compatibility still has open audit items.** `YRS_UNDO_CONCURRENT=1 python3
validation/undo.py` exercises independently generated editing/undo histories;
this still finds differences after restored identities affect conflict ordering. A retained
case is `validation/fixtures/undo-concurrent-identity-history.json`. Saved stack import/export and changed-parent event metadata are implemented;
exact concurrent undo observer parity remains under audit.
See `validation/REFERENCE_LIMITATIONS.md` for reference nondeterminism evidence.

The full 641-scenario core interoperability suite passed again after block
compaction and the map-head split correction. Unit regressions cover compaction,
remote-edit preservation, repeated nested restoration, cursor tracking and
multiple documents. Remaining major milestones are closing the documented behavioral differences,
completing the public API audit, and resolving the performance gap on large editing traces. A public release and repository
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
the wire. Subdocument data providers and globally unique GUID generation are
host responsibilities.


`Doc(client_id=..., offset_kind=Bytes)` supports UTF-8 byte offsets for text
editing and events. The default remains `Utf16` for Yjs interoperability;
replicas may use different offset modes while exchanging identical updates.
Insert, remove and format offsets in byte mode must fall on Unicode character
boundaries. CRDT state-vector clocks always remain UTF-16 code units.
`python3 validation/offsets.py` validates 96 randomized mixed-mode histories,
34,176 snapshots, 28,242 text events and 1,152 wire replay cases across v1/v2.
These cover Chinese, astral characters, combining accents and ZWJ emoji. This
matrix does not yet establish Unicode sticky-position parity.


Automatic garbage collection is available with `skip_gc=false`; the existing
constructor default retains deleted content for historical snapshots. `Doc::gc`
and `Transaction::gc` explicitly collect deleted content even with retention
mode enabled. Undo managers protect their own active histories; clearing one
manager does not discard another manager's history. Snapshot encoding rejects
automatic-GC documents, matching Rust's API contract.

With GC enabled in both runtimes, all 641 core scenarios passed in v1/v2:
182,284 independent operation snapshots, 273,408 identical-wire replay snapshots,
54,700 local rich-text operations from identical state, and 7,692 cross-runtime
document transfers. See `validation/gc-results.json`. This establishes the core
GC interoperability matrix. Concurrent undo remains a separate audit item;
long-run editing and memory observations are recorded below.


`In` describes detached nested inputs for `ArrayRef::insert` and
`MapRef::insert_input`. `Out::to_input` captures an independent copy of shared
arrays, maps, rich text and XML trees. `Text::apply_delta` accepts `TextDelta`
insert/delete/retain operations, including attributed text and shared-type
embeds, in a single transaction. The mixed-offset Rust matrix includes these
delta edits and checks observer output as well as rendered text and clocks.


`python3 validation/undo_mixed.py` tests live networks with both Rust and MoonBit
editing owners. Every replica has a mirror in the other runtime that receives
identical wire history, and every generated cleanup deletion is synchronized
before asserting convergence. Both wire formats pass 96 histories: 102,528
replica comparisons, 7,562 undo/redo actions and 3,264 duplicate deliveries.
The run required 404 formatting-cleanup reconciliation rounds. Results are in
`validation/undo-mixed-results.json`. This validates live concurrent undo
interoperability without assuming independent HashSet restoration orders must
allocate identical identities. Exact undo observer parity is not checked by this
matrix, and the independent-history mismatch fixture remains retained.


Legacy JSON content and opaque shared-type references are preserved on the wire.
`UndefinedRef` exposes retained compatibility branches through map, array and
text views. `python3 validation/legacy.py` checks 1,728 Rust comparison snapshots
and 1,152 replay documents for opaque references, plus 64 legacy JSON cases
against Yjs 13.6.27 in both wire formats. Install the pinned JavaScript reference
with `npm ci --ignore-scripts --prefix validation/yjs` first. A retained fixture
demonstrates the pinned Rust legacy decoder's off-by-one error; the port follows
Yjs for that obsolete format. See `validation/REFERENCE_LIMITATIONS.md`.


Saved undo stacks can be restored with `StackItem::from_json` and the
`init_undo_stack` / `init_redo_stack` constructor arguments. Stack JSON uses the
Rust serde schema, including v1-encoded `IdSet` byte arrays; metadata encoding is
caller-defined. Load the matching document state with retained tombstones before
restoring its stacks. `IdSet` also exposes union, difference, intersection and
v1/v2 codecs. `Out::branch_id` and `BranchId::get` resolve collection identities
across replicas; `Doc::root_refs` enumerates root collections.

Undo events expose `changed_parent_types` and `has_changed`, including changed
collections' ancestors. Destroying a tracked document removes its scopes and
stacks while preserving history for other documents. The contract oracle
(`python3 validation/contracts.py`) checks 256 randomized set cases and 4,416
undo/redo operations from identical saved Rust state, sampled from 96 histories
with 17,280 source snapshots. It compares stack JSON, metadata, results and
changed-parent multisets. Independent undo allocations remain subject to the
reference restoration-order limitation; this matrix does not assert that those
independently generated identities are equal.


`Text::diff_range` and `XmlText::diff_range` reconstruct rich text at an optional
upper snapshot and annotate additions/removals against an optional lower
snapshot. `Diff[M]` carries caller-defined change metadata computed from
`YChange { kind, id }`. The query reads retained history without modifying the
document. `diff` returns current rich text through the same interface.

`cleanup_formatting=false` disables automatic remote formatting-marker cleanup.
The default is enabled, matching Yjs and Rust's explicit-client constructor;
Rust's generic default options disable it. Configure this option consistently
when comparing retained history. Decoded subdocuments use Rust's disabled
cleanup default because this option is not transmitted on the wire.

`python3 validation/diffs.py` passes 30,720 historical queries across 96 histories
and both cleanup settings. Both runtimes load identical wire state and snapshot
metadata; comparisons preserve text, embeds, attributes and every annotated
character's CRDT identity. Only equivalent adjacent chunk boundaries are
normalized. A separate pinned Yjs regression covers formatting inside a surrogate
pair, where pinned Rust panics; see `validation/REFERENCE_LIMITATIONS.md`.


`JsonPath::parse` supports the Yrs query subset: root/current selectors, Unicode
member names, negative indices, wildcards, recursive descent, slices and unions.
Use `Any::json_path` for immutable values or `Doc::json_path` for live CRDT
handles, including imported roots and XML attributes/children. Predicates are
unsupported upstream. The parser rejects unclosed brackets and zero-step slices
rather than accepting malformed input or reaching upstream's iterator panic.

`python3 validation/queries.py` compares 3,840 queries on 64 documents in both
immutable and shared form (7,680 evaluations). Map traversal order is unspecified;
only wildcard/recursive results are compared as multisets. Ordered index unions
and slices retain their order. Unicode classes are generated from the pinned
Rust 1.97.1 toolchain's Unicode 17.0 tables by
`validation/generate_path_unicode.py`. Unit tests also exercise live-handle edits,
untyped imported roots, XML queries and a 1,000-level recursive traversal.


`Update::decode_v1` / `decode_v2` expose state-vector bounds, insertion identities,
delete sets and whether a packet extends a replica's state. Updates can be merged,
differenced against a state vector, re-encoded and applied with `Doc::apply_update`.
Decoded deleted-content items count as insertions until integration; GC blocks
are included only when requested. State vectors support causal partial ordering,
and state vectors and sticky indices support both metadata encoding versions.

`python3 validation/update_info.py` compares 5,122 distinct Rust-produced packets
from 64 histories with garbage collection enabled and disabled, plus a retained
deleted-content regression. Another 96 cases compare exact v2 state-vector and
sticky-index bytes, including Unicode root names and both cursor associations.


`IdMap[A]` associates named `ContentAttribute[A]` values with identity intervals.
Insertion and union combine overlapping metadata; intersection keeps shared
identities and combines both sides' metadata, while subtraction removes identities
regardless of their values. `attributions` covers a requested `BlockRange`, filling
gaps with empty attributes. Maps support filtering, conversion to `IdSet`, snapshot
iteration and v1/v2 codecs with caller-supplied value conversion through `Any`.

`python3 validation/attribution.py` passes 20,680 snapshots from 128 randomized
histories and two retained regressions, plus 10,344 cross-runtime imports. It checks
range algebra, Unicode attribute dictionaries and both encoding formats. 17,561
snapshots also have identical bytes. Rust dictionaries can contain multiple entries
for equal attributes after merging separately allocated maps; MoonBit encodes a
single dictionary entry per equal value. Both runtimes decode either representation
to the same ranges and metadata. Attribute list order and duplicate-input behavior
follow upstream; callers can provide unique attributes for ordinary set semantics.


Weak references are available through `MapRef::link` and `quote` on sequences.
Insert a `WeakPrelim` with `In::WeakLink`; retrieve the resulting `WeakRef` through
`Out::WeakLink`. `QuoteBound` supports included, excluded and unbounded ends.
A link follows CRDT identities, so edits within its quoted range remain visible.
Map links follow replacement values without owning them. Removing a weak link
does not delete its target. Weak references support plain/rich text queries,
array unquoting, both wire formats, typed observers and deep observers through
chains and cycles. `LinkSource` exposes the encoded boundary metadata.

Weak-reference compatibility is still being audited. The port preserves observer
subscriptions when a referenced item splits; the pinned Rust implementation can
lose those subscriptions. Its weak plain-text and XML readers also disagree on
some imported boundaries. These differences are tracked separately from passing
core document and wire checks; this feature is not yet a claim of full Yrs parity.

`python3 validation/weak.py` records 37,120 weak-link snapshots and 6,656 binary
imports in v1/v2 with GC enabled and disabled. Document values, identities and
quotations agree apart from 48 queries where Rust's plain/XML readers contradict
each other. The same run records 7,306 observer mismatches (14,072 additional
MoonBit notifications, zero missing reference notifications); it explicitly reports
partial compatibility. Retained reference-crash fixtures are tested separately.
See `validation/REFERENCE_LIMITATIONS.md` before relying on exact weak event parity.


`Doc::get` and typed `get_*` methods look up existing roots without creating them.
`encode_diff_v1/v2` encodes integrated state only; full-state encoding also forwards
pending updates. `prune_pending` returns unresolved blocks and deletions for saving
and later reapplication. `has_pending_updates` matches the pending-store concept;
`has_missing_updates` additionally detects clock gaps in integrated sparse state.
Explicit GC accepts an optional `IdSet` scope and follows upstream whole-block
selection. Transaction metadata includes `insert_set`, `delete_set`, `cleanups`
and `has_changes`. Array events expose inserted/removed block-start IDs.

The expanded transaction matrix checks cleanup ranges and array identity coverage
across 44,160 snapshots. Raw event block-start sets differ in 166 cases because
internal splitting differs; logical ranges, deltas and document values still match.
`python3 validation/pending.py` checks 512 sparse delivery cases and 320 scoped-GC
cases (4,160 snapshots). MoonBit preserves every source insertion identity and its
exact state across prune/reapply; all complete histories and GC-retained content
agree with Rust. Intermediate sparse integration remains a compatibility gap:
44 cases differ, including 30 resolved by explicitly retrying Rust's pending data.
Pinned Rust also shifts identities in 101 full encodings and retains redundant
pending deletions in 50 cases. These are recorded as partial compatibility, not
removed from the test population; see `validation/pending-results.json`.

Unicode sticky positions now convert between user offsets and UTF-16 item clocks.
A cursor created at a UTF-8 character boundary has the same binary identity as
one created at the corresponding UTF-16 position. Resolving a UTF-16 cursor inside
a surrogate pair in byte mode returns `None`, as no UTF-8 boundary exists there.
The UTF-16 path retains upstream boundary behavior. `validation/cursor_offsets.py`
checks 12,864 snapshots from 3,216 cursor cases on 128 multilingual documents,
including block splitting and v2 replication. Rust's UTF-16 results agree; its byte
mode uses mixed units and differs in 11,016 snapshots. The port corrects that defect
rather than copying invalid cursor clocks; see the retained reference fixture.

Long-session validation uses the real Unicode editing traces bundled with the
pinned upstream checkout (originally from Seph Gentle's editing-traces project).
Run `python3 validation/traces.py` for JavaScript or add `--target native` for the
native backend. Each run checks the independently reconstructed final text,
reversed and duplicated delivery at reconnects, v1/v2 restarts, and bidirectional
Rust/MoonBit wire imports. Full-state catchups needed after pending replay are
counted separately. Both retention and GC modes are tested.

The recorded wall time and peak RSS cover the entire process: JSON input, two
live replicas, packet generation/delivery, restart replicas and result encoding.
These are single-run stress measurements, not isolated local-edit microbenchmarks;
other validation work may be running concurrently. The native file-reading shim
is confined to the validation runner and is not a library dependency.


Weak sequence subscriptions now survive unbounded endpoint insertions, an empty
quoted sequence, and anchors arriving after the weak reference. Deep observation
also follows children inserted into a previously empty quotation. Map links retain
the upstream deletion-detachment behavior described in the focused tests.
`python3 validation/weak_network.py` checks three concurrent editing replicas with
both Rust and MoonBit authors: 8,192 edits, 11,264 deliveries and 15,360 compared
snapshots in v1/v2 with GC enabled and disabled. All values, weak boundaries,
causal clocks and final convergence agree. There are 1,650 observer mismatch
snapshots with 2,282 additional MoonBit notifications and zero missing Rust events;
there are no query exceptions in this network matrix. Exact observer parity is
still intentionally different from the pinned reference's lost subscriptions.

Observer dispatch now honors cancellation by an earlier callback in the same
batch. `observer_test.mbt` covers 27 collection, deep, transaction, subdocument,
undo and awareness notification paths, plus generic observer replacement and
pending removal. The typed behavior agrees with Rust. Pinned Rust's document
callbacks temporarily lose access to their registry during dispatch; the port
keeps cancellation effective there too (see `REFERENCE_LIMITATIONS.md`).

Real-trace results are saved in `validation/trace-results.json` and
`validation/trace-native-results.json`. Both backends passed all five traces with
and without GC: 907,542 transactions, 923,962 patches, 1,815,084 packet deliveries
and 7,094 reconnect checkpoints per backend. Every final document also passed
v1/v2 restarts and bidirectional Rust imports. MoonBit required zero full-state
catchups; the Rust runs required 4,454, tracked separately from normal replay.

For the largest trace (259,778 transactions, GC enabled), the recorded process
measurements were (native at `82c8a94`; JavaScript at `e0542e9`):

| Runtime | Seconds | Peak RSS (MiB) |
| --- | ---: | ---: |
| MoonBit native | 145.56 | 117.22 |
| Rust paired with native | 13.23 | 94.17 |
| MoonBit JavaScript | 184.77 | 434.06 |
| Rust paired with JavaScript | 12.51 | 92.92 |

These runs demonstrate recovery and interoperability under long editing
histories, but also a major performance limitation. They are not throughput
promises or evidence of full compatibility. The files record the tested revision
and measurement boundaries; timings were collected alongside other validation
work.

The pending-update audit additionally replays each original packet to a fixed
point, discarding unresolved buffering between packets. This isolates item
integration from pending-store merge and retry decisions. Rust and MoonBit agree
exactly on all 512 cases, including text, identities, deletions, serialized wire
and pass counts (up to nine passes). Normal buffered delivery still has the
44 intermediate-state differences reported above; the new check does not count
those as compatible or change the production scheduler.

Typed logical references are available as `Root[T]`, `Nested[T]` and `Hook[T]`.
They store collection identity without retaining a document. A hook resolves on
any replica, returns `None` for an absent or deleted child, and never silently
redirects to a replacement under the same map key. `BranchId::get` remains the
lower-level lookup that can inspect retained deleted collections. Hook JSON
matches Rust serde, including its `_tag: null` field. `validation/handles.py`
checks 256 cases with 53-bit client IDs, Unicode names and both GC modes.

```mbt check
///|
test "resolve a typed collection on another replica" {
  let source = @yrs.Doc(client_id=1UL)
  let root : @yrs.Root[@yrs.MapRef] = Root("workspace")
  let map = root.get_or_create(source)
  let text = map.insert_text("title")
  text.insert(0, "Hello")
  let handle = text.hook()
  let peer = @yrs.Doc(client_id=2UL)
  peer.apply_update_v2(source.encode_state_as_update_v2())
  assert_eq(handle.get(peer).unwrap().get_string(), "Hello")
  map.remove("title")
  peer.apply_update_v1(source.encode_state_as_update_v1())
  assert_true(handle.get(peer) is None)
}
```

`Protocol` and `AsyncProtocol` expose the upstream extension points for startup,
message dispatch, sync steps, continuous updates, authentication, awareness and
custom messages. `DefaultProtocol()` implements both; use
`AsyncProtocol::handle(protocol, awareness, packet)` from an async host. Update
bytes are decoded before the application handler runs. Packet processing remains
ordered across suspension and retains prior successful messages if a later one
fails. No network transport or async runtime is imposed on the library.

Tests exercise custom authentication, network transaction origins, delegated
update handlers, malformed later messages, and authorization that suspends before
allowing or rejecting edits. The existing Rust sync/presence comparison still
passes all 33,024 snapshots and 768 cross-runtime transfers.

The current API inventory and release gates are in
[`COMPATIBILITY.md`](COMPATIBILITY.md). It accounts for all 83 pinned Rust root
exports and distinguishes implemented operations, MoonBit adaptations, missing
low-level APIs, and behavioral work still open. It is not a full-compatibility
claim.

`python3 validation/sparse_wire.py` checks sparse v1/v2 utility interoperability
against Yjs 13.6.27 (install the pinned `validation/yjs` dependencies first). It
covers 64 concurrent Unicode/rich-text, array and nested-map histories, 512
merge/diff cases, and 4,096 completed receiver comparisons with GC on/off.
Insertion identities, deletion coverage and contiguous state vectors agree.
Observed receiver vectors converge exactly; 32 artificial surrogate-splitting
vector cases expose a recorded Yjs text-loss difference, where Rust and MoonBit
preserve the original character. This closes the sparse-v2 wire validation gap
without claiming identical intermediate pending behavior.

`IdSet` preserves clients with no ranges, including zero-length insertion and
v1/v2 decoding. Lookup distinguishes an absent client from an empty client;
union preserves these entries, while subtraction/intersection remove them as
Rust does. Updates and snapshots retain this metadata too. Use
`Snapshot(delete_set=...)` and `snapshot.delete_set()` for owned copies. The
expanded contracts oracle passes 256 set cases (128 exercising empty clients),
including update/snapshot codecs, and 4,416 saved undo-stack operations.

`uuid_v4_from(bytes)` formats exactly 16 network-order bytes with the same
version/variant bits as Rust's `uuid_v4_from(u128)`. `uuid_v4(entropy)` calls the
host's 16-byte entropy provider once, without a hidden deterministic fallback.
The identity oracle compares 512 UUID inputs against unchanged Rust.

`MapRef.get_or_init[T : DefaultPrelim](key)` reuses a matching collection and
replaces a missing or differently typed value with an empty one. It supports
text, arrays, maps, XML fragments and XML text, with concrete convenience methods
for each. `SharedRef`, `RootRef`, and `DefaultPrelim` are open traits, so an
application can wrap a shared collection in its own type and still initialize,
save a typed hook, and resolve it on another replica.

`get_as[T : FromAny]` on maps and arrays decodes values directly into typed
application data. Integers, binary buffers and nested shared collections retain
their representations; missing entries decode as null. Implement `FromAny` for
application records, or use `get_json_as[T : @json.FromJson]` for MoonBit's JSON
conventions (which represent `Int64` as a string). `Out.to_any()` and `from_any`
are also public. The Rust serde oracle checks 7,250 conversions, including
lossless numeric boundaries, nonfinite floats, signed zero, options and arrays.

`Doc.get_type_from_path` resolves root-key paths through nested shared maps and
sequences. Like Rust's store lookup, map-key traversal can inspect retained
deleted branches; sequence indices refer to visible values. `pending_update()`
and `pending_delete_set()` return owned snapshots of unresolved blocks and early
deletions without draining them, retrying integration, or notifying observers.

The refreshed trace matrices include clock-indexed block lookups and a nearby
text-position cache. Each case records its revision, source hash, clean/dirty
source status and toolchain. The JavaScript run also records hashes of the frozen
MoonBit and Rust executables used throughout the matrix. Both backends pass all
ten cases. The previous largest GC-enabled measurements were 168.15 seconds
(native) and 481.76 seconds (JavaScript); these are separate whole-process runs,
not controlled speedup estimates. The remaining gap versus Rust is substantial.
