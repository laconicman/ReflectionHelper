# Changelog

Notable changes to PropertyTree. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this package follows
[Semantic Versioning](https://semver.org/).

## [2.0.0] — unreleased

The package is renamed from **ReflectionHelper** to **PropertyTree**, and the walker is rebuilt on
`Mirror.DisplayStyle`. Six defects that 1.0.0 shipped with are fixed, each pinned by a named test.

### Changed — breaking

- **Module and package renamed** to `PropertyTree`. Update the dependency URL and `import`.
- **`PropertyNode.createPropertyTree(reflecting:named:)` is now an initializer**,
  `PropertyNode(reflecting:named:maxDepth:)`, resolving a `// TODO` left in 1.0.0. It is generic
  rather than taking `Any`, so reflecting an optional no longer warns at the call site.
- **`id` is a `String` path**, not a `UUID` — `"order.address.city"`, `"order.tags[0]"`.
- **`displayValue` and the new `typeName` are stored**, not computed on each access.
- **Equality follows the data.** `==` compares path, name, kind, type, rendering and children;
  1.0.0 compared `id` alone, which — with a fresh `UUID` per node — meant nothing was ever equal.
- **A `.structure` with its own `description` renders it** instead of a child count, and still
  expands to its properties.

### Added

- **`Kind`** — `value`, `structure`, `collection`, `dictionary`, `enumeration`. This is what tells
  a dictionary from a struct, 1.0.0's first documented known limit.
- **`typeName`** — the dynamic type, correct for every value including optionals.
- **`maxDepth`** (default 16) and **`isTruncated`**, so a truncated branch is not mistaken for a
  leaf. `displayValue` still reports how many children were cut.
- **`treeDescription`** — the subtree as indented text, for a console or a test.
- **Set, enum and tuple support**, and dictionaries with keys of any type.
- **`Date`, `URL`, `Data` and `Decimal` are leaves** rather than branches over their internals.
- **CI** on macOS and on a Linux container, the latter being what tests the Foundation-only claim.
- **Direction docs** in [`docs/`](docs/) — design decisions with their rejected alternatives, a
  roadmap, and a `PT-#` debt register — plus a DocC catalog for the API reference.

### Removed

- **`init(id:name:value:children:)`** — a node is built by reflecting a value.
- **`init(reflecting:named:)`'s shallow twin.** 1.0.0 had two initializers; the one documented as
  "the shallow version — one `Mirror` pass" in fact recursed fully, so it was a second, worse
  walker rather than a shallow option.
- **`replacing(children:)`** — incoherent under path identity, since a replacement child's path
  would no longer describe where it sits. Narrowing a tree is a filter, which is on the
  [roadmap](docs/Roadmap.md).
- **The internal type-glyph table.** It could not work: nine of its ten optional arms were
  unreachable and the tenth labelled every `nil` in the program a `String?`. `typeName` and `kind`
  replace it — see [Design](docs/Design.md) § `Kind`, not type glyphs.

### Fixed

- **`init` dropped its `id:` argument**, assigning a fresh `UUID` instead — which made
  `replacing(children:)` silently useless and collapsed a SwiftUI `OutlineGroup` on every rebuild.
- **A reference cycle exhausted the stack.** Two objects pointing at each other recursed without
  bound; `maxDepth` ends it.
- **`Set` and non-`String`-keyed dictionaries reflected as children with empty names.** Only
  `[Any]` and `[String: Any]` were recognised.
- **`Date` reflected as a branch**, adding a `timeIntervalSinceReferenceDate` level under every
  date in a decoded response.
- **A `SelectivelyReflectable` type now reflects as a structure.** A `CustomReflectable` mirror
  carries no display style, which the first draft of the new classifier read as "leaf".
- **The README described `init(reflecting:named:)` as shallow.** It recursed.

### Migration from 1.0.0

```diff
-.package(url: "https://github.com/laconicman/ReflectionHelper", from: "1.0.0")
+.package(url: "https://github.com/laconicman/PropertyTree", from: "2.0.0")

-import ReflectionHelper
+import PropertyTree

-let tree = PropertyNode.createPropertyTree(reflecting: order, named: "order")
+let tree = PropertyNode(reflecting: order, named: "order")
```

`selectedKeyPathsToMirror` gained tuple labels, which existing array literals satisfy unchanged.
Code that read `node.id` as a `UUID`, or called `replacing(children:)` or the memberwise
initializer, needs revisiting.

### Known limitations

- **Ordering is lexicographic on the rendered key**, so a `[Int: T]` reads 1, 10, 2 (PT-2).
- **Cycles are survived, not detected** — a cyclic graph renders as a repeating chain to the depth
  limit rather than naming the cycle (PT-1).
- **A tree retains the reflected object graph**, and `PropertyNode` is therefore not `Sendable`
  (PT-5).
- **The leaf list is closed** — a consumer's own opaque type still spills its internals (PT-4).
- **Path ids can collide** on a dictionary key containing `.` or `[` (PT-3).
- **No release has been used against a real decoded payload yet** (PT-7).

Full register: [docs/Tech-Debt.md](docs/Tech-Debt.md).

## [1.0.0] — 2026-08-18

First release, as **ReflectionHelper**. `PropertyNode`, a tree built by reflecting any value, and
`SelectivelyReflectable`, letting a type choose what its `Mirror` exposes.

[1.0.0]: https://github.com/laconicman/ReflectionHelper/releases/tag/1.0.0
