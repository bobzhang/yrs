# Changelog

## 0.1.1 — 2026-10-16

Fresh Codex CLI review fixes, with public issues and regression tests:

- Preserve binary embeds, Undefined and exact Int64 values throughout v2 document,
  transaction, update-utility, pending, historical and generic codec paths (#2).
  V1 rich-text JSON conversion retains its format-defined limitations.
- Forward integrated sparse blocks using actual clocks; resolve their cursor
  anchors; capture visible sparse history with explicit snapshot exclusion ranges
  without turning missing history into replication deletions (#1).
- Do not attach weak subscriptions to a conflict-deleted map value (#3).
- Freeze transactions retained by weak and subdocument observers (#4).
- Emit awareness change notifications when a removed remote participant returns
  (#5), correcting the same defect in pinned Rust Yrs.

Decoded updates preserve subdocument options without sharing live child instances
between receiving documents. Added a bidirectional typed-v2 Rust oracle and an
explicit awareness restoration witness. Existing public signatures are preserved.

## 0.1.0 — 2026-10-16

Initial MoonBit port of Yrs 0.28.0 with the weak-reference extension and Yjs
v1/v2 wire interoperability. The compatibility target is the complete public
CRDT feature set, with the language adaptations and upstream corrections listed
in [COMPATIBILITY.md](COMPATIBILITY.md).

The final compatibility audit added generic delta mapping and fixed three defects:

- Weak map links now continue notifying after their key is deleted and reinserted,
  including nested edits and links restored while the key is absent.
- New quotations count visible positions, skipping tombstones and formatting
  markers when selecting their starting identity.
- Pending integration no longer lets one unavailable dependency stall independent
  later blocks from the same client. Integrated state reaches the independently
  checked causal fixed point without packet resends.

Earlier port fixes include full-width v2 clock deltas, compressed deletion ranges,
restored-parent undo persistence, inferred-GC deletion propagation, snapshot
clipping, Unicode cursor conversion and subdocument registry cleanup. Each has
retained tests or reference reproductions under `validation/`.

Performance is not at Rust parity. The library requires serialized access to a
document; the host supplies transport, identities, clocks and scheduling.
