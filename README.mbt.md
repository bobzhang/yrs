# Yrs for MoonBit

A MoonBit port of Yrs, the Rust implementation of the Yjs CRDT. Work in progress; full upstream compatibility is the target, not a current claim.

The reference is Yrs 0.28.0 at `ac339600c712642e556895426113c3f9c117de39`, checked out in `.repos/y-crdt`. The implementation preserves Yjs item identities, conflict ordering, deletion semantics and binary updates. Public APIs use MoonBit constructors.

Implementation sequence:

1. Collaborative text and binary v1 update exchange against Rust, including concurrent and out-of-order edits.
2. Arrays, maps, nested types, rich text and XML on the same item store.
3. Binary v2, update utilities, sync and awareness protocols.
4. Transactions, observers, undo, snapshots, relative positions, subdocuments and the remaining pinned upstream surface.

Every milestone needs real Rust interoperability tests, rather than only MoonBit-to-MoonBit convergence tests. Validation evidence and remaining limitations will be recorded as each milestone lands.
