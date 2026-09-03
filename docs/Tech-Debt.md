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

### PT-2 — Ordering is lexicographic on the rendered form · **open**

Dictionary keys and set elements are sorted by `String(describing:)`.

**Cost.** A `[Int: T]` orders its keys 1, 10, 2. Correct and stable, but wrong-looking — and the
first thing anyone notices in a numerically-keyed dictionary.
**Discharge.** Compare numerically when every rendered key parses as a number, lexicographically
otherwise. Pinned today by `handlesNonStringKeys`, which asserts the current order deliberately, so
that test changes with the fix.

### PT-3 — Path ids collide on keys containing a separator · **open**

`id` is built by joining components with `.` and `[]`.

**Cost.** A dictionary key of `"a.b"` produces the same path as a nested `a` → `b`, so two nodes in
one tree can share an `id` — exactly the SwiftUI identity collision the path was introduced to fix.
Needs an adversarial key to hit; a decoded response can contain one.
**Discharge.** Escape `.`, `[` and `]` in a name before joining, or make `ID` a structured type
holding its components rather than a `String`.

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
rows. Invisible at the sizes this package targets; the wrong shape for a big one.
**Discharge.** Render on demand behind a stored cache, or build children lazily so an unexpanded
branch is never walked.

### PT-7 — No release has been exercised against a real payload · **open**

Every behaviour is pinned by a test or a probe over a hand-written fixture.

**Cost.** The defaults — `maxDepth: 16`, child count as a container's rendering, lexicographic
ordering — are reasoned, not observed. A real decoded response is what would show whether they
read well.
**Discharge.** Inspect one in a debug UI before tagging 2.0.0, and record what changed.

---

## Discharged in 2.0.0

The six defects 1.0.0 shipped with, each now pinned by a named test.

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
