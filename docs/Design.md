# PropertyTree — Design

Architecture decisions for the PropertyTree package. Each subsection states the **decision**,
the **why**, and the **alternative rejected**. Authoritative over code comments where they
disagree. See [Roadmap](./Roadmap.md) and [Tech-Debt](./Tech-Debt.md).

The package exists to make a decoded API response readable in a debug UI: reflect a value, get a
tree, drive a SwiftUI `OutlineGroup` from it. Everything below follows from that one use, and from
the fact that `Mirror`'s literal output is a poor description of a value.

## Dispatch on `Mirror.DisplayStyle`, not on concrete casts

**Decision.** The walker branches on `Mirror(reflecting:).displayStyle` — `.optional`,
`.collection`, `.set`, `.dictionary`, `.enum`, `.tuple`, `.struct`, `.class` — and never asks
whether a value *is* a particular concrete type in order to decide its shape.

**Why.** `displayStyle` describes every value, including the ones a cast list cannot enumerate.
The 1.0.0 walker tested `case let array as [Any]` and `case let dictionary as [String: Any]`, which
meant a `Set` and a `[Int: String]` fell through to the default branch and reflected as children
with empty names. Dispatching on style handles all of them — plus enums and tuples, which 1.0.0
never considered — in the same nine lines. A dictionary's mirror children are `(key:value:)`
tuples, so keys of *any* type are reachable by decomposing the pair, not just `String`.

It also fixes what 1.0.0's README listed as its first known limit: a dictionary and a struct both
produce a node with named children, and `displayStyle` is precisely what tells them apart. That
distinction is published as `PropertyNode.Kind`.

**Rejected.** Growing the cast list (`as? Set<AnyHashable>`, `as? [Int: Any]`, …) — it can never be
complete, because the element and key types are open-ended.

**Consequence.** A `CustomReflectable` mirror carries *no* display style unless it names one, so
the classifier's fallback asks whether the mirror has children rather than trusting the style to be
present. This is what makes `SelectivelyReflectable` types reflect as structures rather than
leaves; it is pinned by `SelectivelyReflectableTests.drivesTheTree`.

## Identity is the node's path, not a fresh `UUID`

**Decision.** `PropertyNode.id` is a `String` path from the root — `"order.address.city"`,
`"order.tags[0]"`. Reflecting the same value twice yields the same identities.

**Why.** The type exists to drive an `OutlineGroup`, and SwiftUI tracks which rows are expanded by
`id`. 1.0.0 minted a fresh `UUID` per node on every build, so every rebuild of the tree collapsed
the outline; worse, its `init(id:…)` dropped the `id` argument and assigned `UUID()` anyway, which
made `replacing(children:)` — whose only purpose was to preserve identity while swapping children —
silently useless. A path is derived from the data, so it is stable by construction rather than by
remembering to thread it through.

A path is also a debuggable identifier: it prints as the thing you would type to reach the value.

**Rejected.** Keeping `UUID` and having callers cache nodes between rebuilds — that pushes the
library's problem onto every consumer. Hashing the reflected value into the id — `value` is `Any`
and not reliably `Hashable`.

**Uniqueness is enforced, stability is conditional.** Paths are derived from names, and names are
not injective: two dictionary keys rendering the same string, a key containing a `.` or `[`, or a
subclass property shadowing an inherited one would all produce one `id` for two nodes — the very
SwiftUI collision the path was introduced to prevent. Sibling path components are therefore made
unique before the walker recurses, by suffixing repeats `#2`, `#3`, …; the visible `name` is left
alone, so only the path disambiguates. What cannot be enforced is *stability* for siblings that
render alike: their order is arbitrary, so which of them holds which index can change between runs
([PT-2](./Tech-Debt.md)). Every ordinary value renders distinctly and is unaffected.

## A class's inherited properties are part of it

**Decision.** For a class, members are collected from the whole ancestor chain via
`Mirror.superclassMirror`, root-most ancestor first, and that combined list drives classification,
the child count, and the children themselves.

**Why.** `Mirror.children` stops at the type itself. Without walking ancestors a subclass shows
only the properties it declares, so inherited state silently disappears from the tree — and a
subclass declaring no stored properties of its own has empty children, which this walker's
"nothing to show is a leaf" rule then turned into a leaf rendering its own type name, hiding
everything it holds. Found in review; both shapes are now pinned by tests. Ancestors read first
because that is the order the type was built in.

**Not applied to a `CustomReflectable`.** Such a type has stated exactly which properties it wants
shown, and walking its ancestors would put back whatever it chose to hide — which is precisely
what `SelectivelyReflectable` exists to do. So the chain is walked only when the subject does not
supply its own mirror.

**Rejected.** Asking `displayStyle == .class` before walking. `superclassMirror` is `nil` for
everything else, so the check would only add a branch that can never change the answer.

## Rendering is computed once, at build time

**Decision.** `PropertyNode.displayValue` and `PropertyNode.typeName` are **stored**, computed
while the tree is built, not computed properties.

**Why.** `displayValue` runs a three-way dynamic cast and `String(describing:)`. As a computed
property it ran on every SwiftUI body evaluation, for every visible row. Storing it also makes
`Equatable` and `Hashable` total and cheap, which is what lets two trees over equal data compare
equal — see below.

**Rejected.** Lazy rendering per node. It is the better answer for a very large tree and is
recorded as [PT-6](./Tech-Debt.md); for the trees this package is built for — a decoded response,
tens to hundreds of nodes — eager is simpler and the cost is invisible.

## Equality compares the rendering, not the value

**Decision.** `==` compares path, name, kind, type name, rendering, truncation and children. It
does not compare `PropertyNode.value`, and the contract is stated in terms of the *description* of
a value rather than the value.

**Why.** `value` is `Any`, which is not `Equatable`; there is nothing to compare. Everything else
is derived from the value, so comparing the derived form is the available proxy: two trees over
equal data are equal, and two trees of the same shape over different data are not. 1.0.0 compared
`id` alone, which — combined with fresh UUIDs — meant no two nodes were ever equal, including a
node and its own rebuild.

**The proxy is only as good as the rendering, which is why `Data` renders its bytes.** An earlier
draft of this document claimed outright that trees over different data are unequal. Review found
the counter-example: `Data`'s own description is a byte count alone, so `Data([1,2,3])` and
`Data([9,9,9])` rendered identically, compared equal, and collapsed into one element in a `Set`.
The fix is at the source — an opaque `Data` leaf now renders a 16-byte hex preview, which a reader
wants to see anyway — and the contract is now stated honestly: **values that render identically
compare equal**, however they differ underneath. Blobs agreeing in both length and first 16 bytes
still collapse.

**Rejected.** Opening `value` as an `any Equatable` existential to compare it properly. It works
for conforming types, but a value that is not `Equatable` would then never compare equal to
anything — reintroducing 1.0.0's defect for exactly the types reflection is most often pointed at.
Equality would also stop agreeing with what the reader sees.

## `value: Any` is kept, and the package is therefore not `Sendable`

**Decision.** The reflected value stays on the node as `Any`. `PropertyNode` is not `Sendable` and
makes no attempt to be.

**Why.** It is the escape hatch: a consumer that wants to render its own type specially can
downcast. Claiming `Sendable` over `Any` would require `@unchecked`, which would be a lie about
whatever was reflected in.

**Rejected — for now — the snapshot design.** Dropping `value` entirely and keeping only
`PropertyNode.displayValue`, `PropertyNode.typeName` and `PropertyNode.kind` would make the
node a plain value: `Sendable`, so a tree could be built off the main actor; `Codable`, so a tree
could be attached to a bug report; and non-retaining, which matters because today a tree holds the
whole reflected object graph alive for as long as it lives ([PT-5](./Tech-Debt.md)). That is
probably the better library. It is not in 2.0.0 because it removes a published capability for a
benefit no consumer has asked for yet — revisit when one does, as 3.0.0.

## Opaque Foundation value types are leaves

**Decision.** `Date`, `URL`, `Data` and `Decimal` are rendered as values and never expanded. The
test is metatype equality, not `is`.

**Why.** Reflected, they expose `timeIntervalSinceReferenceDate`, `_url`, a `count`/`pointer`/
`bytes` triple and `_mantissa` respectively — implementation noise in place of the value, and a
junk level under every date in a decoded response. `UUID` and other childless values need no
entry: a mirror with no children is classified as a value already.

`is` is the wrong test because a dynamic cast from `Any` implicitly unwraps optionals and matches
across optionality — the trap described under type glyphs below.

**Rejected.** Treating every `CustomStringConvertible` as a leaf. Too broad: it would collapse any
of the consumer's own structs that conform, and a type having a description is not a statement that
it has no interesting parts — hence the compromise that a `.structure` shows its own description
*and* still expands.

`Data` is the one whose rendering is ours rather than Foundation's: its description is a byte
count, which describes no payload and made distinct blobs compare equal (see § Equality). It
renders `3 bytes: 01 02 03`, truncated after 16 bytes, built without `String(format:)` so it is
identical on Linux.

**Cost.** The list is closed; a consumer's own opaque wrapper still spills its internals
([PT-4](./Tech-Debt.md)).

## A depth limit, not cycle detection

**Decision.** `PropertyNode.init(reflecting:named:maxDepth:)` takes a `maxDepth`, default 16. A
node at the limit keeps its kind and child count and reports `PropertyNode.isTruncated`.

**Why.** Two objects that point at each other made 1.0.0 recurse until the stack was exhausted —
measured still descending at 5 000 levels. That is a crash, not the "deep tree" its README
described, and reference graphs (a Core Data object, a view hierarchy) are exactly what one
inspects. A depth limit is four lines and ends the whole class of problem, cycles included.
`isTruncated` exists so a truncated branch is not silently indistinguishable from a leaf. A
negative `maxDepth` is clamped to zero rather than left to mean whatever the comparison happens to
do, so the argument's contract is total.

**Rejected — for now — real cycle detection** (tracking visited `ObjectIdentifier`s along the
current path). It renders better output — "cycle" instead of a repeating chain — but costs an
allocation per node to prevent a crash the depth limit already prevents. Recorded as
[PT-1](./Tech-Debt.md).

## `Kind`, not type glyphs

**Decision.** The package publishes `PropertyNode.Kind` and `PropertyNode.typeName`. It does
not ship the glyph table that 1.0.0 carried internally (`🅂` for `String`, `🄸` for `Int`, …).

**Why.** That table could not work, and measurably did not. Built from `case is String:` arms over
an `Any`, it hit two Swift casting rules at once: a `.some` value implicitly unwraps, so
`case is String` matched a `String?`, and a `nil` of *any* optional type casts successfully to
*every* optional type, so the first optional arm — `case is String?` — claimed every nil in the
program. Verified: a `nil` `Int?`, `Date?` and `Double?` all rendered as `🅂?`. Nine of the ten
optional arms were unreachable and the tenth was wrong.

`typeName` reads the metatype through `type(of:)`, which is correct for every value including
optionals (`"Optional<Int>"`), and `kind` carries the structural information a UI actually
switches on. Glyphs are presentation: a consumer that wants them can map either field, and gets to
pick its own notation.

**Rejected.** Rebuilding the table on metatype comparison (`type(of: value) == String.self`).
Correct, but it hardcodes a closed list of ten types into a model layer, to produce a decoration.

## Selective reflection stays a protocol

**Decision.** `SelectivelyReflectable` keeps its shape from 1.0.0 — a static list of
`(label, keyPath)` pairs, with `customMirror` supplied by a protocol extension. Only the tuple
labels are new.

**Why.** It is the only way to surface a *computed* property, which `Mirror` omits, and to hide a
stored one. It is small, it works, and it is already published API.

**Rejected.** Replacing it with a macro. A macro that lists every property is a different tool for
a different job — the README points at
[KeyPathIterable](https://github.com/Ryu0118/KeyPathIterable) for that — and this protocol is for
*choosing*, which is a decision a macro cannot make.

## Package shape

**Decision.** One library product, one target, no dependencies — not even `swift-docc-plugin` —
`swift-tools-version: 6.0`, and no `platforms:` declaration. Sources are flat under `Sources/PropertyTree/`, split one primary entity
per file. Direction docs are Markdown in `docs/`; the DocC catalog is API reference only.

**Why.** 6.0 is the lowest tools version that gives Swift 6 language mode and `swift test` support
for Swift Testing, both of which this package uses; 6.1 would add only package traits (SE-0450),
which there is nothing here to gate, while cutting off Xcode before 16.3. Omitting `platforms:`
keeps the package buildable anywhere Swift is, since it imports Foundation and nothing else — CI
runs the suite on macOS *and* on a Linux container so that claim is tested rather than asserted.
Four source files need no subdirectories. The docc plugin is left out so a consumer resolves
nothing but this package: `xcodebuild docbuild` needs no plugin, and Swift Package Index injects
one itself when a package doesn't declare it — verified, the DocC catalog builds warning-free
without it.

The docs split mirrors KaPow: `docs/` is authoritative and reviewable on GitHub without building
anything, while DocC — which Swift Package Index renders — carries the API reference where a reader
of the API is already looking.

**Rejected.** Direction docs as DocC articles, which is the `repo-init` default. They render more
nicely but are invisible in a diff and on the GitHub file listing, and this package's docs are read
while deciding *whether* to adopt it, not while using it.
