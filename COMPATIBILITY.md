# Compatibility scope and release gates

The reference is Yrs 0.28.0 at
`ac339600c712642e556895426113c3f9c117de39`, with its `weak` feature enabled.
Yjs 13.6.27 is a second wire-format reference. **This port is still in development;
full upstream compatibility is not established.** Passing the core suite is one
part of that work, not a release certification.

## Public API inventory

The following inventory accounts for all 83 root exports in the pinned Rust
`lib.rs`. “Adapted” means the operation is expressed using MoonBit types or
methods; it does not mean that every edge case has been proved equivalent.
The generated `pkg.generated.mbti` is the authoritative MoonBit API.

| Rust root exports | MoonBit surface / status |
| --- | --- |
| `Doc`, `OffsetKind` | Implemented; explicit constructor options and defaults below |
| `Options` | Adapted to labeled `Doc(...)` arguments |
| `ClientID`, `ID`, `BranchID` | `UInt64`, `Id`, `BranchId`; the port also accepts client IDs beyond Rust's 53-bit domain |
| `Any`, `Number` | `Any`; numeric variants are `Integer(Int64)` and `Float(Double)` |
| `In`, `Out`, deprecated `Value` | `In`, `Out`; no deprecated `Value` alias |
| `Array`, `ArrayRef`, `ArrayPrelim` | `ArrayRef` methods and `In.Array` preliminary values |
| `Map`, `MapRef`, `MapPrelim` | `MapRef` methods and `In.Map` preliminary values; generic `get_or_init` has concrete helpers |
| `Text`, `TextRef`, `TextPrelim` | `Text` methods and `In.Text` preliminary values |
| `Xml`, `XmlOut` | `XmlNode`, concrete XML methods and `In` constructors |
| `XmlElementRef`, `XmlElementPrelim` | `XmlElement`, `In.XmlElement` |
| `XmlFragment`, `XmlFragmentRef`, `XmlFragmentPrelim` | `XmlFragment`, `In.XmlFragment` |
| `XmlTextRef`, `XmlTextPrelim` | `XmlText`, `In.XmlText` |
| `GetString`, `Observable`, `DeepObservable` | Concrete `get_string`, `observe`, `observe_deep`, and keyed `unobserve` methods |
| `Quotable`, `WeakPrelim`, `WeakRef` | Concrete `quote` methods, `WeakPrelim`, `WeakRef`; query/event differences remain open |
| `SharedRef`, `RootRef`, `Root`, `Nested`, `Hook` | Typed collection resolution and identity serialization; generic trait surface is being audited |
| `StateVector`, `Snapshot`, `Update`, `IdSet` | Implemented, including owned empty-client metadata and v1/v2 round-trips |
| `IdMap`, `AttrRange`, `ContentAttribute`, `ContentAttributes`, `Diff` | Generic attribution types and operations; `Diff` is used for text history results |
| `Assoc`, `IndexScope`, `Offset`, `StickyIndex`, `IndexedSequence` | Cursor types plus concrete collection `sticky_index` / `sticky_boundary` methods |
| `JsonPath`, `JsonPathEval` | `JsonPath` and `Doc.json_path` |
| `Observer` | Generic `Observer[K,F]` with explicit keyed cancellation |
| `Transaction`, `TransactionMut`, `ReadTxn`, `WriteTxn`, `Transact` | Callback-scoped `Doc.transact`, `Transaction` metadata, and direct collection operations |
| `Origin` | `Bytes`; identity tokens are serialized explicitly |
| `RootRefs`, `SubdocsEventIter` | Arrays/iterators of root entries and child documents |
| `SubdocsEvent`, `TransactionCleanupEvent`, `UpdateEvent` | `SubdocsEvent`, `Transaction`, and update bytes passed to callbacks |
| `UndoManager` | `UndoManager[M]`, with injectable clock and metadata |
| `AcquireTransaction`, `AcquireTransactionMut`, `AsyncTransact`, `TransactionAcqError` | Rust lock-acquisition/future types have no implementation; the portable document is confined to its host execution context |
| `Store` | Partially exposed through `Doc`: state, roots, pending pruning and scoped GC; no public raw mutable store or lock interface |
| `Uuid`, `uuid_v4`, `uuid_v4_from` | GUIDs are strings; `uuid_v4_from(Bytes)` formats 16 network-order bytes and `uuid_v4(entropy)` uses a host-provided entropy callback |
| `merge_updates_v1`, `merge_updates_v2` | Implemented stateless update union |
| `diff_updates_v1`, `diff_updates_v2` | Implemented stateless state-vector clipping |
| `encode_state_vector_from_update_v1`, `encode_state_vector_from_update_v2` | Implemented contiguous-prefix extraction |

This root inventory is **not a complete public-module audit**. Rust also exposes
`block`, `doc`, `types`, `updates`, `any`, `atomic`, `branch`, `encoding`, `error`,
`iter`, `json_path`, `observer`, `sync`, and `undo` modules. In particular:

- `sync`: awareness, message codecs, `Protocol`, `AsyncProtocol`, and
  `DefaultProtocol` are available. Transport and scheduling are host concerns.
- `updates` / `encoding`: public v1/v2 utilities and codecs are available, but
  Rust's extensible encoder/decoder traits and low-level stream objects are not.
- `block` / `branch` / `iter` / `atomic`: raw pointers, mutation internals,
  transaction-bound iterators and atomic storage are not ported as public APIs.
- `types` / `undo`: concrete editing and observation are implemented; method-level
  edge cases, generic conversions and event equivalence remain under audit.
- Errors use MoonBit error types. Stricter malformed-input validation is
  intentional; Rust panic behavior is not a compatibility target.

## Host and language adaptations

`Doc(client_id=...)` requires a host-provided client ID. Subdocument GUIDs must be
unique and explicit; `uuid_v4` accepts the host's entropy callback. The default offset mode is UTF-16 and deleted content is
retained (`skip_gc=true`); Rust defaults to byte offsets and GC enabled. Pass
`offset_kind=Bytes, skip_gc=false` to select those Rust defaults. A protocol peer
must never reuse another active editor's client ID.

Transactions run synchronously within a callback. They batch notifications and
updates; they are not rollback transactions. The API does not expose a Rust-style
read/write lock or promise safe concurrent mutation from multiple native threads.
`AsyncProtocol` may suspend its handlers, but does not make `Doc` thread-safe.
The host must serialize access to a shared document.

Observers use explicit keys and cancellation instead of Rust RAII subscription
guards. Iterator-returning convenience methods may snapshot collections. These
are API/lifetime adaptations, not claims of identical Rust ownership behavior.

## Behavioral gates still open

| Area | Current evidence | Work remaining |
| --- | --- | --- |
| Ordinary sparse pending delivery | Complete histories and scoped GC agree; original-packet fixed-point replay agrees in all 512 cases | Ordinary buffering intentionally differs in 44 cases; a reduced retry-watermark/head-blocking fixture explains how the 14 persistent cases arise. Exact buffered-state parity remains unclaimed |
| Weak references | Mixed-runtime concurrent editing converges; broad query/event oracles retained | Resolve query inconsistencies and additional port notifications; do not label partial event comparisons as passes |
| Concurrent undo | Mixed-runtime networks and restored stack tests pass | Separate nondeterministic restored identities from actual event/behavior mismatches in independently generated histories |
| Public API | Root exports inventoried above; main editing and protocol APIs implemented | Finish method/module audit and resolve or explicitly define the portability boundary for unimplemented APIs |
| Performance | All five real editing traces pass on JS/native with GC on/off | Remeasure recent improvements and address the substantial large-trace runtime gap |
| Release packaging | Local small commits and reproducible oracle scripts | Pinned CI and reproduction instructions are prepared locally; finish the supported-feature contract and regression gates, then create the public GitHub repository |

Known reference defects and deliberate corrections are recorded in
[`validation/REFERENCE_LIMITATIONS.md`](validation/REFERENCE_LIMITATIONS.md).
Individual `validation/*-results.json` files describe the exact scope of each
comparison. They must not be combined into a blanket percentage of compatibility.
