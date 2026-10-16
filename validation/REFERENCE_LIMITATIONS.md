# Pinned reference limitations

The oracle uses Yrs 0.28.0 at `ac339600c712642e556895426113c3f9c117de39` without modifying its source.

## Sparse updates and garbage collection

`fixtures/upstream-sparse-gc-crash.json` is a reduced 15-operation reproducer for a bus error in the Rust reference when GC is enabled. It combines nested map replacement, queued updates and differential updates with missing history. On macOS, the process exits with SIGBUS; it does not return a Rust error. The reference completes with GC disabled.

After building the validation binary, reproduce with:

```sh
validation/rust/target/release/yrs-reference v1 --gc < validation/fixtures/upstream-sparse-gc-crash.json
```

The randomized relay oracle records this reference failure explicitly. It rejects unrecognized reference crashes. The matching scenario remains checked with GC disabled; the other GC-enabled histories are checked normally. This is a limitation of the reference comparison, not evidence of a passing GC comparison for the crashing case.

A second GC-enabled history, `fixtures/upstream-overflowing-skip-history.json`, makes the reference emit a skip block of length `UINT32_MAX` at a nonzero clock. The captured binary update is in `fixtures/upstream-overflowing-skip.json`. Adding that length overflows Yjs's 32-bit clock domain. The port rejects it before mutating the document; the relay oracle records this malformed-reference-output case separately instead of weakening overflow validation.

Garbage collection changes the dependency metadata of deleted blocks. Two independent producers with different GC policies can therefore expose different intermediate states when history is missing. The relay oracle compares every intermediate state using identical binary histories, and checks that each producer converges after full synchronization. Independent histories are compared operation by operation only when both producers retain tombstones; otherwise different intermediate states change later position-based edits.

## Rich-text attribute order

Rust attributes use hash maps. Their iteration order can change formatting-marker allocation, and in some concurrent histories the resulting formatting, even between two runs of the same Rust commands. Rich-text validation therefore compares identical binary histories in both runtimes and local operations starting from identical serialized documents. Cross-runtime imports must preserve exact state vectors. Adjacent strings with identical attributes are normalized only for delta chunk-boundary comparisons.

## Sparse v2 encoding

The pinned reference also panics in `transaction.rs:408` when merging its own pending v2 updates (`UnexpectedValue`). Its `BlockSlice::Skip` encoder writes the length through the v2 length column, while its update decoder reads skip lengths from the raw stream. The port uses the raw stream, matching the decoder and Yjs wire format. `validation/updates.py` currently records v1 relay/utility comparisons; the regular collection/rich-text suite still checks both v1 and v2. Sparse v2 is also checked against pinned Yjs by `validation/sparse_wire.py`: 512 v1/v2 utility cases and 4,096 complete-history receiver comparisons. This validates the wire utilities, not equivalence of intermediate pending-store scheduling.

## Historical snapshot clipping

The pinned snapshot encoder can emit a right-origin flag without the corresponding
ID when clipping a compacted text block. Reproduction: insert `ab`, insert `X` at
index 1, take a snapshot, then insert `Y` at index 2. Encoding the earlier snapshot
produces `010301000401046e6f746501618401000162c4010002585900`, which Rust itself rejects
with `EndOfBuffer(89)`. The relevant path is `ItemSlice::encode` in `slice.rs`:
`item.info()` retains `HAS_RIGHT_ORIGIN`, but the ID is written only when
`adjacent_right()` is true.

Reproduce without modifying upstream:

```sh
cargo +1.97.1 run --release --locked --manifest-path validation/rust/Cargo.toml --bin history -- --reference-snapshot-regression
```

The history oracle captures actual Rust text at snapshot creation, then requires
MoonBit to reconstruct that content after every subsequent operation. It compares
snapshot state vectors and deletion ranges independently, exchanges snapshot and
cursor encodings in both directions, and records this reference failure in the
results. No historical reconstruction cases are excluded because of this defect.

## Undo restoration order

The unchanged pinned Rust implementation restores an unordered set of items.
Fresh processes can therefore produce different item identities and, in some
histories, different rendered results. This is not a reason to accept an arbitrary
port result: the undo oracle requires a fresh Rust run to match the complete
MoonBit history prefix (up to 64 attempts). Every accepted alternative is logged
in `undo-results.json`.

Reproduce with the `undo` reference binary and either fixture:

- `fixtures/upstream-undo-map-order.json`: the same final map entry was observed
  as both 24 and 81 in separate runs.
- `fixtures/upstream-undo-xml-nondeterminism.json`: after repeated XML undo and
  restoration, the final map-only edit was observed to leave the XML text as
  `hello` or shorten it to `h`. The occurrence depends on restoration order;
  repeat the fixture across fresh processes. The harness does not modify the
  upstream checkout or its hashing implementation.

The default undo comparison uses a single editing author with synchronization to
followers and explicit bidirectional binary transfers. Multiple independent undo
authors are an additional, currently failing compatibility configuration; their
restored identities can affect later conflict ordering. Do not interpret the
single-author result as proof of full concurrent undo compatibility. Exact undo
observer-event equivalence also remains unverified; the separate event oracle
covers grouped and concurrent changes without independently generated undo.

## Subdocument destruction leaves a stale registry handle

`validation/fixtures/upstream-subdoc-destroy-registry.json` inserts child A,
explicitly destroys it, then removes its parent map entry. Pinned Yrs leaves A
in `ReadTxn::subdocs()` even though the map is empty. `Doc::destroy` registers
the replacement in both the added and removed identity maps; the original
registration survives. The MoonBit port removes the old identity and registers
the replacement, so removing the slot leaves an empty registry. This is an
intentional compatibility difference, not a passing exact-reference case.

`validation/subdocs.py` compares the complete registry, child state and lifecycle
events in 96 randomized histories without explicit destroy. A separate 32-history
destroy matrix compares child state and lifecycle events, excluding only the
reference registry. It independently requires the MoonBit registry to contain
exactly the live map slots, including duplicate GUIDs. Parent wire replays are
checked against both runtimes; child contents are replicated separately.


## Live mixed-runtime undo and formatting cleanup

`undo_mixed.py` uses persistent, unchanged-reference Rust sessions and persistent
MoonBit sessions. Each logical replica has one editing owner and a mirror in the
other runtime; the mirror replays wire updates rather than independently running
undo. This preserves the exact identities that drive conflict resolution. The
96-history matrix passes both wire formats, including nested collections, XML,
remote edits, undo/redo, duplicate delivery and final replica convergence.

Imports can generate additional deletion operations, including formatting cleanup
and the restored-parent attribute defect documented below. Source and mirror
exchange generated operations before comparing complete state. Comparisons now
include structured XML-text attributes, which rendered XML alone does not expose.
The refreshed matrix records 254 reconciliation rounds (250 rendered-content,
four attribute-only) and compares 9,186 remote synchronization/duplicate observer
transactions, including 5,738 notification batches and 5,074 deep events.

This checks convergence after generated operations have arrived, not equality
before reconciliation. Port-local undo/redo notifications also match unchanged Rust mirrors in 3,772
transactions; 7,768 port-local editing transactions are checked the same way.
These comparisons do not independently execute Rust undo. Independent restoration
identities remain a separate gate. `undo.py` now records its current
strict mismatch rather than retaining a historical passing report: a follower
loses restored nested-map entries in Rust while the corrected port preserves them.
`undo_persistence.py` independently checks every sampled successful port undo/redo
checkpoint against both decoders, and explicitly reproduces Rust's self-reload loss.


## Legacy JSON content decoder

The pinned Rust `ItemContent::JSON` decoder reads `count + 1` strings because its
loop uses `remaining >= 0`. Its encoder writes exactly `count` strings. The
valid v1 packet in `fixtures/upstream-legacy-json.json` is accepted by Yjs
13.6.27 and rejected by pinned Rust with `EndOfBuffer`. The Rust output conversion
also exposes the encoded JSON strings rather than their parsed values.

The port follows [Yjs ContentJSON](https://github.com/yjs/yjs/blob/v13.6.27/src/structs/ContentJSON.js):
read exactly the declared number of entries, parse each JSON value and preserve
the special `undefined` entry. `legacy.py` asserts the pinned Rust failure and
checks 64 v1/v2 cases against pinned Yjs, including deletion, block splitting and
replay of MoonBit output. This is an explicit reference exception; it is not a
passing Rust legacy-content comparison. A separate Rust matrix checks opaque
shared-type references 5, 9 and 15 with modern content, in both wire formats and
GC modes. Type reference 9 is distinct from actual subdocument content reference 9.


## Saved undo stacks and independently allocated identities

`fixtures/undo-reload-independent-identity.json` also demonstrates that independent
undo/reload histories can allocate different restored IDs while the rendered
text remains equal. Those IDs become visible in later stack deletion ranges.
The saved-stack contract oracle therefore starts each comparison from the exact
same Rust document update and serialized undo/redo stacks. It compares complete
output stack records and metadata, undo/redo results, and event parent multisets.
This validates cross-runtime stack restoration rather than requiring identical
allocation from independently generated histories. It does not resolve the
previously documented independent-history limitation.


## Formatting inside a UTF-16 surrogate pair

`fixtures/upstream-format-surrogate.json` inserts `🦀`, formats index 1 with
length 1, then deletes index 1. Pinned Rust leaves an inconsistent formatted
sequence and panics when deleting. Yjs 13.6.27 replaces the split surrogate
halves with U+FFFD, formats the second half, and deletes it successfully. The
port follows Yjs; the behavior has a unit regression and a pinned Yjs probe.
`diffs.py` requires the pinned Rust failure to remain reproducible. Its randomized
Rust matrix uses BMP and combining characters, avoiding half-surrogate edits.

Historical diff comparisons load identical document updates and binary snapshots
in both runtimes. Running position-based edits independently after historical
queries is unsuitable for comparing annotation identities: Rust queries split
internal blocks and can change subsequent formatting-marker allocation. Diff
chunks are merged only when attributes match and their annotated CRDT clock
spans are contiguous; this preserves the identity of every annotated character.

## Weak quotations and observer propagation

The reference build now enables Yrs's `weak` feature. The weak-link oracle
(`python3 validation/weak.py`) records partial compatibility, not a blanket pass.
It compares document values, quoted arrays, boundary identities, map references,
plain/XML text and v1/v2 cross-runtime imports. Text quotations are created before
random edits; arrays can be requoted during edits. Equal bounded positions are
made inclusive in this matrix, with raw empty ranges checked separately.

Retained reproductions:

- `fixtures/upstream-weak-empty-range-panic.json`: an empty excluded/included range
  reaches an `Option::unwrap()` panic in upstream `store.rs:342`. The MoonBit
  quotation stays empty. The oracle runs this fixture with `raw-bounds` and asserts
  the exact reference failure.
- `fixtures/upstream-weak-xml-panic.json` and
  `fixtures/upstream-weak-deleted-start.json`: creating a text quotation after
  deletions can produce a Rust XML slice out of bounds. The deleted-start fixture
  also exhibits a plain-string range mismatch. These cases are retained and are
  outside the passing randomized view matrix; the XML panic is reproduced by the
  script rather than silently ignored.
- `fixtures/upstream-weak-plain-prefix.json` and
  `fixtures/upstream-weak-xml-prefix.json`: Rust's plain and XML queries disagree on
  the same imported quotation's characters. The oracle accepts a differing query
  only when the other query agrees exactly and stripping the test's XML formatting
  confirms the reference's own inconsistency. Forty plain reads and eight XML reads
  have this exception across the matrix; these counts are asserted.
- `fixtures/upstream-weak-split-observers.json`: Rust drops link subscriptions on a
  split item. MoonBit copies those subscriptions to both pieces. Across the matrix,
  7,306 snapshots have observer differences: MoonBit produces 14,072 additional
  events and misses zero reference events. Values still agree. Exact observer
  parity is **not established**; every event mismatch is counted, and any missing
  MoonBit event fails the run.

The matrix covers 37,120 operation snapshots and 6,656 imports, both wire versions
and both GC modes. It does not establish full weak-reference compatibility or
exhaustive concurrent/deep-observer behavior. Focused MoonBit tests additionally
cover chained deep observers, self-quotation cycles, Unicode and safe empty ranges.


## Pending updates and sparse integration

`pending.py` checks source packet metadata independently in both runtimes, then
requires the union of source insertion identities to equal the MoonBit full
encoding and the partition of integrated and pruned data. It also requires the
MoonBit before/restore state to be identical and compares complete histories after
all withheld packets arrive. Scoped GC is checked by reconstructing retained
content with an empty historical deletion set, rather than only checking wire size.

The pinned reference has several distinct behaviors in this matrix:

- `fixtures/upstream-pending-skip-encoding.json` records a full update whose
  insertion clocks differ from the original packets. There are 101 affected
  encodings. `fixtures/upstream-pruned-skip-roundtrip.json` also reproduces a
  prune/encode/reapply change; 23 cases change full-update metadata on roundtrip.
- Pending deletion ranges can redundantly include already integrated identities.
  `TransactionMut::apply_delete` uses the original Skip block length when a
  deletion starts inside it, rather than subtracting the skipped prefix. In 50
  cases the oracle verifies that every extra pending deletion is already applied,
  and that no required pending deletion is lost.
- `fixtures/upstream-pending-retry-stall.json` has ready dependencies that Rust
  processes only after explicitly pruning and reapplying pending data. Thirty
  sparse cases reach the MoonBit state after such retries.
- `fixtures/pending-sparse-integration-difference.json` records the first of 14
  further sparse intermediate-state differences. These remain a compatibility
  gap; this suite does not classify all of them as reference bugs. Complete
  histories converge after withheld packets arrive.
- Three complete histories leave Rust's pending flag set even though all source
  identities, deletion sets, state vectors and visible text match. MoonBit's flag
  is clear. The flag difference is counted separately.

All 832 cases remain in the results. The suite reports **partial compatibility**.
It does not use reference-corrupted full-update identities as an expected result.
Array event block-start IDs also depend on physical splitting: the expanded
transaction matrix records 166 different layouts. It checks every reported ID's
logical membership and requires each changed interval's start, while comparing
deltas and transaction ranges. The first layout is retained in
`fixtures/array-event-block-layout.json`.

## UTF-8 cursor offsets versus UTF-16 clocks

`fixtures/upstream-byte-cursor-units.json` demonstrates that pinned Rust's
`StickyIndex::at` adds a byte-relative position directly to a UTF-16 item clock.
`get_offset` also adds the intra-item UTF-16 offset to the preceding UTF-8 length.
The result may initially look plausible and then move incorrectly after a split,
or name an item that does not exist. The port previously had the same defect.

The port now converts valid character boundaries in both directions. Invalid
UTF-8 boundaries return `None`; a UTF-16 cursor inside a surrogate pair likewise
cannot be resolved to a byte boundary. The original UTF-16 path is preserved,
including upstream's unusual left-associated end behavior. The cursor oracle
compares UTF-16 identities and positions exactly with Rust, then checks byte-mode
identities against those same cursors and byte offsets against independently
converted Unicode prefixes. All 12,864 snapshots pass those checks. Rust byte-mode
results differ in 11,016 snapshots; these differences are counted explicitly.


`fixtures/upstream-weak-open-end-observers.json` also demonstrates omitted Rust
notifications when appending to an unbounded quotation or repopulating it after
all quoted content is deleted. The port retains sequence quotations at their
branch, attaches newly inserted items by range membership, and retries observation
setup when an anchor arrives late. This is a deliberate correction to the pinned
reference, in addition to preserving edges when blocks split.

The separate mixed-runtime weak network suite covers 32 three-author histories
in both wire formats and GC settings. All 15,360 state/view comparisons converge
without query exceptions. It records 1,650 observer-difference snapshots (2,282
additional MoonBit notifications, zero missing reference events). The main weak
matrix's updated counts above include both split and open-boundary corrections.

## Cancellation during observer dispatch

`validation/rust/src/bin/observers.rs` exercises mutual cancellation: each of two
callbacks removes the other. Typed collection observers correctly run only one
callback. The pinned Rust document transaction phases instead run both callbacks
on every edit, because `commit` temporarily takes `store.events` out before
calling them; the transaction's unsubscribe method sees no registry. Destruction
has the same issue. The captured fixture is
`fixtures/upstream-document-observer-cancellation.json`.

The port now checks shared subscription cells at dispatch time, fixing its typed
observer cancellation bug and applying consistent immediate cancellation to
document, awareness, undo and deep observers as well. This is an intentional
difference from the pinned document callback behavior. The generic public
`Observer[K, F]` also exposes replacement, dispatch, pending cancellation and
subscriber queries; generic keys replace Rust's `Into<Origin>` conversion. Like
Rust, an unsubscribed key remains discoverable until the next dispatch or
subscription drains it, so repeated unsubscribe can return true before that drain.

## Sparse integration versus pending scheduling

The pending oracle's `replay_original` diagnostic bypasses merged pending data:
for each pass it drops unresolved blocks, reapplies each original packet, and
continues until the integrated encoding is stable. It preserves integrated
blocks and deletions between passes. This exercises exactly the same sparse
integration schedule in each runtime without relying on pending retry triggers.
All 512 sampled partial histories produce identical content, ranges, full and
integrated encodings, and pass counts in both runtimes (at most nine passes).
The fixture `pending-sparse-integration-difference.json` also agrees under this
schedule. This narrows the remaining discrepancy to buffered-delivery behavior;
it does not establish ordinary pending lifecycle parity, which remains partial.

## High custom protocol message tags

The pinned `Message::Custom` encoder writes its tag with `write_u8`, while the
decoder reads a variable-length unsigned integer. Tags 128–255 therefore do not
round-trip reliably. The port writes the varuint expected by both decoders.
`python3 validation/protocol_codec.py` exercises all 252 non-reserved tags with
six payload lengths (including length-encoding boundaries). The unchanged Rust
decoder accepts all 1,512 port packets with the exact original tag and payload.
Low-tag encodings agree exactly; 768 high-tag encodings differ from Rust's
malformed output. These are explicit encoder exceptions, not byte-parity passes.

## Yjs surrogate-split suffix recovery

`fixtures/yjs-surrogate-suffix-loss.json` contains a two-packet reproducer for
Yjs 13.6.27. Insert `🌙` with client 1, then request a diff against the synthetic
state vector `{1: 1}`, which claims knowledge of only half the scalar's two
UTF-16 clocks. Deliver this suffix before the original full item. Rust and
MoonBit preserve `🌙`; Yjs renders two replacement characters. This is an
adversarial state vector, not one observed during valid whole-character editing.

The sparse-wire oracle separately exercises 256 observed receiver state vectors
and 256 arbitrary clock vectors. It records 32 text mismatches caused solely by
this Yjs surrogate replacement, requires the port's completed text/arrays/maps to
match the original history, and checks insertion identities and deletion ranges
independently. All observed-state-vector cases agree. The exception is counted
explicitly; arbitrary-clock text mismatches are not reported as parity passes.

### Reduced retry-watermark and head-blocking sequence

`python3 validation/pending_scheduling.py` checks the eight-packet reduction in
`fixtures/upstream-pending-watermark-blocking.json`. All packets belong to client
1. An independent item at clocks 30–33 raises Rust's store high-water clock while
clocks 6–9 are still absent. Delivering 6–9 later makes queued 9–12, 18–21 and
33–36 ready, but does not increase that high-water clock. Rust's
`TransactionMut::apply_update` retries only when the stored missing-clock
threshold is less than the current high-water clock, so those items stay queued.

A final 42–45 item then joins the pending batch. Pruning and reapplying the batch
unblocks the earlier items, but `BlockPicker::switch` stops at 36–39, whose
dependency 27–30 is still absent. That also blocks the later, now-ready 42–45 item
from the same client. Reapplying each original packet separately integrates it
in both runtimes. No insertion identities are lost from the pending partition.

This explains how an initial retry stall can cause a persistent difference even
after retrying the merged pending update. The port intentionally retries ready
dependencies eagerly. The oracle retains exact prefix-level evidence; it does
not reclassify the ordinary buffered outputs as equal.

The additional weak callbacks are now classified at every compared step:
13,912 report a changed quoted view; 158 follow formatting operations without a
view change; two follow deletion cleanup without a view change. None are
unclassified, and none of Rust's notifications are missing. The retained
`weak-empty-quote-format-events.json` and
`weak-empty-quote-cleanup-events.json` fixtures exercise the latter categories.
The cleanup regression also checks internal operation identities: the extra
callback is caused by deleting a format marker attached to the empty quotation.
Observers report changes to CRDT structure, so an empty rendered string alone
does not imply that no quoted operation changed. These classifications explain
the tested differences; they do not turn them into exact upstream event parity.

## Minimum signed variable integer encoding

Pinned Rust's `write_var::<i64>` and `write_var_signed::<i64>` negate a negative
value in signed arithmetic. In release mode `i64::MIN` remains negative after
negation and the encoder emits `[64]` (negative zero), losing the integer. The
port computes an unsigned magnitude and emits all ten bytes. The unchanged Rust
decoder accepts those bytes and returns `i64::MIN`. `validation/streams.py`
retains both exceptions separately from 2,032 exact encoding/decoding cases;
fixed-width `write_i64` has no such issue.

## Undo restoration references the deleted parent

`fixtures/upstream-undo-restored-attribute-parent.json` creates XML attributes,
clears the initial undo history, overwrites attributes, removes the element, and
undoes that capture group. The restored element and text have their attributes
in memory. Encoding that document and importing it into a fresh unchanged Rust
instance loses those attributes. The same defect existed in the port.

When restoring a map entry, `ItemPtr::redo` can retain a left origin in the old,
deleted parent even after restoring the parent under a new ID. Item encoding
omits the explicit parent when an origin is present. A receiving replica thus
infers the old parent and deletes the restored entry. The port now anchors a
restored map entry in the new parent's map chain whenever the old origin belongs
to a different branch. This deliberately corrects the pinned reference behavior;
it also applies to ordinary nested maps, not just XML attributes.

`undo_restore_attributes_test.mbt` checks XML attributes and repeated nested-map
undo/redo through both update formats, including GC-enabled documents. The undo
oracles now compare structured XML trees and text attributes as well as rendered
XML, which alone did not expose every lost attribute.

## GC-enabled mixed-author undo

The expanded `undo_mixed.py` defaults to both GC modes and both wire versions.
A GC-enabled v1 mixed-author run at seed 49, step 165 panicked in unchanged
Rust at `yrs/src/slice.rs:217`: `Could not get parent branch info for item`.
The command was an update import followed by document encoding in a process
that had performed local undo. The final imported packet loads successfully
into fresh Rust documents with either GC mode; replaying only the received
packets also succeeds. This implicates the retained local undo/GC state, but
does not yet establish the precise cause or prove the port free of related bugs.

The harness records both processes' complete call streams on failure in
`/tmp/yrs-undo-mixed-execution-failure.json`. These are diagnostic evidence, not
a deterministic standalone replay: rerunning Rust local undo may allocate
different restoration identities from those embedded in captured remote
packets. Reproduce the live comparison with `python3 validation/undo_mixed.py
--gc on --owner mixed`; Rust's restoration order can change the first failure.
The default suite still fails on an exception or mismatch; there is no waived
GC-enabled mixed-author case.

A separate GC-enabled run with MoonBit authoring every replica and unchanged
Rust mirrors passes 96 histories in each wire format. The report explicitly
labels this ownership scope and counts 126 required reconciliation exchanges.
It validates port-generated edits, undo/redo, notifications and convergence
under GC; it does not replace the unfinished Rust-owned undo comparison.
