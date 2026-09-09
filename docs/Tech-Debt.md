# PropertyTree — Tech Debt

Numbered register of PropertyTree debt. Each item: **Cost** (what it hurts) and **Discharge** (the
change that retires it). Reference from code as `// TODO(PT-1): …`.

Status legend: **open** (live), **deferred** (intentional until a milestone), **discharged**
(retired, kept for the record).

---

### PT-1 — Cycles are survived, not detected · **open**

`maxDepth` is what stops a reference cycle from recursing; nothing recognises one.

**Cost.** A cyclic graph renders as a repeating chain down to the depth limit, which reads as real
data. Truncation is reported, a cycle is not.
**Discharge.** Track visited `ObjectIdentifier`s along the current path and render a node that
names the ancestor it points back to. Rejected for 2.0.0 in [Design](./Design.md) § A depth limit.

### PT-2 — Ordering is lexicographic on the rendered form, and ties are arbitrary · **open**

Dictionary keys and set elements are sorted by `String(describing:)`, which is neither a natural
order nor a total one.

**Cost.** Two costs, the second found in review. A `[Int: T]` orders its keys 1, 10, 2 — correct
and stable, but wrong-looking, and the first thing anyone notices in a numerically-keyed
dictionary. And when two siblings render *identically* the comparator orders neither first, so
their order comes from set or dictionary iteration, which varies between runs: measured across six
process launches, a three-element set of tied values came out `[1,2,3]`, `[1,3,2]`, `[3,1,2]` and
`[2,3,1]`. Their ids stay unique (see PT-3, discharged) but which element holds which index moves,
so a SwiftUI outline can carry expansion state to the wrong row. Ordinary values render distinctly
and are unaffected.
**Discharge.** Compare numerically when every rendered key parses as a number. For ties there is no
second key to compare on for an arbitrary `Any`, so the honest fix is either to require a
`Comparable`/`Hashable` witness where one exists, or to state ties as unordered and stop implying
stability. Pinned today by `handlesNonStringKeys`, which asserts the current order deliberately, so
that test changes with the fix.

### PT-4 — The leaf policy is a closed list · **open**

`Date`, `URL`, `Data` and `Decimal` are hardcoded as opaque values.

**Cost.** A consumer's own opaque wrapper — a money type, a tagged identifier — still spills its
stored representation into the tree, and there is no way to say otherwise short of conforming to
`SelectivelyReflectable` and listing nothing.
**Discharge.** An opt-in marker protocol (`OpaqueReflectedValue`) checked alongside the built-in
list, or a set of types passed to the initializer.

### PT-5 — A tree retains the whole reflected object graph · **open**

`PropertyNode.value` holds `Any`, so every node keeps its reflected value alive.

**Cost.** A tree held in view state keeps the response — or, for a reflected view controller, a
screen — alive for as long as the tree lives. It is also what stops `PropertyNode` being
`Sendable`, so a tree cannot be built off the main actor.
**Discharge.** The snapshot design: drop `value`, keep only the rendered fields. Deliberately
deferred to a 3.0.0 — see [Design](./Design.md) § `value: Any` is kept.

### PT-6 — Every node is rendered eagerly · **open**

`displayValue` and `typeName` are computed for the whole tree at build time.

**Cost.** Building a tree over a large payload renders every node even though a list shows twenty
rows. Invisible at the sizes this package targets; the wrong shape for a big one. Related, and
noted in review: a node *at* the depth limit still builds its mirror and collects its members, in
order to report a child count and `isTruncated`, so an expensive custom mirror runs at every
truncated boundary.
**Discharge.** Render on demand behind a stored cache, or build children lazily so an unexpanded
branch is never walked.

### PT-7 — No release has been exercised against a real payload · **open**

Every behaviour is pinned by a test or a probe over a hand-written fixture.

**Cost.** The defaults — `maxDepth: 16`, child count as a container's rendering, lexicographic
ordering — are reasoned, not observed. A real decoded response is what would show whether they
read well.
**Discharge.** Inspect one in a debug UI before tagging 2.0.0, and record what changed.

### PT-14 — Equality can only compare the rendering · **open**

`==` and `hash(into:)` cannot inspect `value`, because it is `Any`, so they compare the derived
fields — which means two values that render identically compare equal however they differ.

**Cost.** Found in review as a `Data` defect: its description is a byte count alone, so distinct
blobs of one size collapsed in a `Set`. `Data` now renders a hex preview, so the residue is
narrower — blobs agreeing in length *and* first 16 bytes — but the shape of the problem belongs to
any type whose description elides content, including a consumer's own.
**Discharge.** Open `value` as an `any Equatable` and compare properly where the witness exists,
falling back to the rendering where it does not. Rejected for 2.0.0 because a non-`Equatable` value
would then never compare equal to anything, which is 1.0.0's defect again for exactly the types
reflection is most often pointed at. See [Design](./Design.md) § Equality.

### PT-15 — `typeName` does not identify optionality consistently · **open**

A `nil` reports `Optional<Int>`; a present value reports `Int`, because the optional level is
collapsed and the wrapped value is what remains.

**Cost.** Found in review. A consumer cannot use `typeName` to answer "is this property optional?"
— the answer depends on whether the value happens to be present. Harmless for display, wrong for
anything driving behaviour off the type.
**Discharge.** Carry optionality separately — either a `Bool` on the node, or by keeping the
declared type alongside the unwrapped one. Both add a stored field to serve a question no consumer
has asked yet.

---

## Discharged in 2.0.0

The six defects 1.0.0 shipped with, plus three found reviewing this branch, each now pinned by a
named test.

### PT-3 — Path ids could collide · **discharged**

`id` is built by joining names, and names are not injective: a dictionary key containing `.` or
`[`, two keys rendering the same string, or a subclass property shadowing an inherited one all
produced one `id` for two nodes. Review found the second of those, which is the common case — the
register had recorded only the first.

Discharged over three passes, the first two of which were incomplete. Sibling components are made unique
before the walker recurses, suffixing repeats `#2`, `#3`, …; and names are escaped over the
grammar's reserved characters (`.` `[` `]` `#` `\`). Review showed twice why escaping is needed and
not merely tidy: without it, siblings `a`, `a`, `a#2` became `a`, `a#2`, `a#2` — the disambiguator
colliding with a literal sibling — and a child named `a.b` still encoded exactly like a child `a`
holding a child `b`. Escaping then had to move from `Character` to Unicode scalar, since a `.`
carrying a combining mark is one `Character` that is not equal to `"."` yet still contributes a
separator scalar. Ordinary names contain no reserved character, so ordinary paths are unchanged.

Pinned by `disambiguatesCollidingDictionaryKeys`, `disambiguatesTiedSetElements`,
`idsAreUniqueThroughout`, `doesNotCollideWithALiteralSuffix`,
`doesNotConfuseSeparatorsWithStructure`, `escapesSeparatorsAtScalarLevel` and
`keepsOrdinaryPathsClean`. Ordering stability for tied
siblings remains open as PT-2.

### PT-8 — `init(id:…)` dropped its `id` argument · **discharged**

`self.id = UUID()` ignored the parameter, so `replacing(children:)` — whose only job was to
preserve identity — minted a new one, collapsing a SwiftUI outline on every rebuild. Discharged by
path-based identity; `replacing(children:)` is gone, being incoherent under it.
Pinned by `identitiesAreStableAcrossRebuilds`.

### PT-9 — The type-glyph table was unreachable and wrong · **discharged**

Nine of ten optional arms could not be reached and the tenth claimed every `nil` in the program,
because a dynamic cast from `Any` unwraps optionals and matches across optionality. Discharged by
publishing `PropertyNode.typeName` (read from the metatype) and `PropertyNode.Kind`, and
deleting the table. Pinned by `typeNamesAreNotConfusedAcrossOptionals`.

### PT-10 — A reference cycle exhausted the stack · **discharged**

Two objects pointing at each other recursed without bound. Discharged by `maxDepth`.
Pinned by `survivesReferenceCycles`.

### PT-11 — `Date` reflected as a branch · **discharged**

Every date in a payload added a `timeIntervalSinceReferenceDate` level. Discharged by the opaque
leaf list, which also covers `URL`, `Data` and `Decimal`.
Pinned by `treatsFoundationValueTypesAsLeaves` and `rendersOpaqueValuesReadably`.

### PT-12 — `Set` and non-`String`-keyed dictionaries reflected as unnamed children · **discharged**

Only `[Any]` and `[String: Any]` were recognised. Discharged by dispatching on
`Mirror.DisplayStyle` and decomposing a dictionary's `(key:value:)` pairs.
Pinned by `ordersSetElements` and `handlesNonStringKeys`.

### PT-13 — A dictionary and a struct were indistinguishable · **discharged**

1.0.0's first documented known limit. Discharged by publishing `PropertyNode.Kind`.
Pinned by `distinguishesDictionariesFromStructures`.

### PT-16 — Inherited properties vanished from the tree · **discharged**

`Mirror.children` stops at the type itself, so reflecting a subclass showed only the properties it
declared and silently dropped everything its superclasses held; a subclass declaring no stored
properties of its own was classified a leaf, hiding all of them. Found in review. Discharged by
collecting members across the `superclassMirror` chain — except for a `CustomReflectable`, whose
choice of properties must not be undone. Pinned by `includesInheritedProperties`,
`doesNotMistakeAnInheritingSubclassForALeaf` and `respectsACustomMirrorOverInheritance`.

### PT-17 — Distinct `Data` payloads rendered and compared identically · **discharged**

`Data`'s own description is a byte count, so `Data([1,2,3])` and `Data([9,9,9])` both rendered
`3 bytes`, compared equal, and collapsed into one element in a `Set`. Found in review. Discharged
by rendering a 16-byte hex preview, which a reader wants regardless. Pinned by
`rendersDataContents` and `distinguishesDataPayloads`. The general case is PT-14.
