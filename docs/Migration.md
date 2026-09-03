# Migrating from 1.0.0 to 2.0.0

Every breaking change between `ReflectionHelper` 1.0.0 and `PropertyTree` 2.0.0, what it costs, and
the exact edit that resolves it.

## Overview

1.0.0 was `ReflectionHelper`. 2.0.0 is **`PropertyTree`**: the same two ideas — a tree built by
reflecting a value, and a protocol letting a type choose what its `Mirror` exposes — with the walker
rebuilt on `Mirror.DisplayStyle` and six defects fixed. Renaming the module is what makes every
other break cheap to find: nothing compiles until you have changed the import, so there is no
half-migrated state.

**Unusually for a major version, the changes worth reading are the ones that are *not* compile
errors.** 1.0.0 shipped two initializers; the one it kept — `PropertyNode(reflecting:named:)` — is
still there in 2.0.0, with the same argument labels, and now runs the good walker instead of the raw
one. Your call site keeps compiling and produces a different tree.

| # | Change | How it shows up |
|---|---|---|
| 1 | Module renamed to `PropertyTree` | "No such module 'ReflectionHelper'" |
| 2 | `createPropertyTree(reflecting:named:)` is now an initializer | "Type 'PropertyNode' has no member" |
| 3 | `id` is a `String` path, not a `UUID` | Type mismatch wherever the id is stored |
| 4 | `init(id:name:value:children:)` removed | "Extra arguments" / no such initializer |
| 5 | `replacing(children:)` removed | "Value has no member 'replacing'" |
| 6 | `selectedKeyPathsToMirror` gained tuple labels | "Does not conform to protocol" |
| 7 | **`PropertyNode(reflecting:named:)` changed meaning** | **Nothing. The tree is different.** |
| 8 | **`description` changed format** | **Nothing. Your logs change.** |
| 9 | **Equality is data-based, not identity-based** | **Nothing. `Set` and `==` behave differently.** |
| 10 | **Depth is bounded at 16** | **Nothing. Deep values truncate.** |

Items 1–6 are compile errors and are mechanical. Items 7–10 are silent and are the ones to read.

### Where to start

```console
% swift build 2>&1 | grep error
```

Change the dependency and the import first — that turns the whole migration into a list of compile
errors — then work down the numbered sections.

```diff
-.package(url: "https://github.com/laconicman/ReflectionHelper", from: "1.0.0")
+.package(url: "https://github.com/laconicman/PropertyTree", from: "2.0.0")
```

```diff
-import ReflectionHelper
+import PropertyTree
```

The package also requires **Swift 6.0** (1.0.0 asked for 6.1, so this is a floor *lowered*, not
raised) and declares no platform floor at all.

## 1. Building a tree is an initializer

`createPropertyTree(reflecting:named:)` resolved a `// TODO` left in 1.0.0's source — *"would be
good to make this an initializer"* — and is now exactly that. It is also generic rather than
`Any`-taking, which removes a warning you were probably seeing.

```diff
-let tree = PropertyNode.createPropertyTree(reflecting: order, named: "order")
+let tree = PropertyNode(reflecting: order, named: "order")
```

If you reflected an optional, 1.0.0's `Any` parameter made the call site warn — `expression
implicitly coerced from 'String?' to 'Any'` — and the usual fix was `as Any`. Drop it; the generic
signature takes the optional with its static type, the same way `String(describing:)` does.

```diff
-let tree = PropertyNode.createPropertyTree(reflecting: name as Any, named: "name")
+let tree = PropertyNode(reflecting: name, named: "name")
```

There is a third parameter, `maxDepth`, defaulted to 16 — see section 10.

## 2. `id` is the node's path

```diff
-let id: UUID = node.id
+let id: String = node.id          // "order.address.city", "order.tags[0]"
```

1.0.0 minted a fresh `UUID` per node on every build, so a rebuilt tree collapsed every expanded row
of a SwiftUI `OutlineGroup`. Worse, its `init(id:…)` **dropped the `id` argument** and assigned
`UUID()` regardless, which made `replacing(children:)` — whose only purpose was to preserve identity
— silently useless.

A path is derived from the data, so reflecting the same value twice gives the same identities and an
outline keeps its expanded rows. If you were working around the old behaviour by caching nodes
between rebuilds, or by keying your own dictionary off `node.id` as a `UUID`, delete that: the
identity is now stable on its own.

See [Design](./Design.md) § Identity is the node's path.

## 3. Nodes are built by reflecting, not by hand

The memberwise initializer and `replacing(children:)` are both gone.

```diff
-let node = PropertyNode(name: "city", value: "Moscow")
+let node = PropertyNode(reflecting: "Moscow", named: "city")
```

`replacing(children:)` has no replacement, deliberately. Under path identity a node's `id` describes
*where it sits*, so swapping in arbitrary children produces nodes whose paths no longer match their
position — the incoherence is the reason it went rather than being fixed. If you used it to narrow a
tree, that is a filter, and it is the top item on the [Roadmap](./Roadmap.md); until it lands, build
the tree from an already-narrowed value, or conform that value to `SelectivelyReflectable` and list
the properties you want.

## 4. `selectedKeyPathsToMirror` gained tuple labels

The requirement is now `[(label: String, keyPath: PartialKeyPath<Self>)]`. Tuple labels are part of
a tuple's type, so a conformance that **spelled the type explicitly** — which is how 1.0.0's own
README wrote it — no longer satisfies it:

```
error: type 'Offer' does not conform to protocol 'SelectivelyReflectable'
note: candidate has non-matching type '[(String, PartialKeyPath<Offer>)]'
```

Two ways out. Add the labels to the annotation:

```diff
 struct Offer: SelectivelyReflectable {
-    static var selectedKeyPathsToMirror: [(String, PartialKeyPath<Offer>)] = [
+    static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Offer>)] = [
         ("price", \.price),
         ("total", \.total),
     ]
 }
```

Or drop the annotation and let the literal infer the requirement's type, which is what the 2.0.0
README shows:

```swift
static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Offer>)] {
    [("price", \.price), ("total", \.total)]
}
```

The element literals themselves are unchanged either way. Nothing else about the protocol moved:
it still refines `CustomReflectable` and still supplies `customMirror` for you.

## 5. The type-glyph table is gone

1.0.0 rendered `description` as the node's name followed by a glyph for its type — `🅂` for a
`String`, `🄸` for an `Int`. The table was internal, so removing it breaks no call site, but it is
worth knowing *why* it went if you were relying on the output: **it could not work.**

Built from `case is String:` arms over an `Any`, it hit two Swift casting rules at once. A `.some`
value implicitly unwraps on a dynamic cast, so `case is String` matched a `String?` before the
`String?` arm was reached; and a `nil` of *any* optional type casts successfully to *every* optional
type, so the first optional arm — `case is String?` — claimed every `nil` in the program. Measured:
a `nil` `Int?`, `Date?` and `Double?` all rendered `🅂?`. Nine of the ten optional arms were
unreachable and the tenth was wrong.

Use `kind` and `typeName` instead — and if you want glyphs, map either field in your own view layer,
where the notation is yours to choose:

```diff
-Text(node.description)                       // "city 🅂"
+Text(glyph(for: node.kind)) + Text(node.name)
```

`typeName` reads the metatype through `type(of:)`, so it is correct for every value including
optionals (`"Optional<Int>"`). See [Design](./Design.md) § `Kind`, not type glyphs.

## 6. Silent: `PropertyNode(reflecting:named:)` now runs the good walker

**This is the change most likely to be missed in review.** 1.0.0 had two ways to build a tree, and
its README described the initializer as *"the shallow version — one `Mirror` pass"*. That was not
true: it recursed fully. What it actually was is the walker *without* any of the transformations
that make output readable. So it produced:

| | 1.0.0 `init(reflecting:named:)` | 2.0.0 |
|---|---|---|
| `String?` holding `"a"` | a node `name`, child `some`, grandchild | one leaf, `"a"` |
| `["a", "b"]` | `Array`'s internals | `[0]`, `[1]` |
| `["b": 1, "a": 2]` | unnamed `(key:value:)` pairs, unordered | `a`, `b`, ordered |
| `Date()` | a `timeIntervalSinceReferenceDate` branch | one leaf, the date |
| a `Set` | children with empty names | ordered, indexed |
| a reference cycle | recursion until the stack is gone | truncated at `maxDepth` |

If you called `createPropertyTree` you already had the good behaviour and nothing changes. If you
called the initializer, your trees get better without your asking — but **snapshot tests and any
assertion on tree shape will fail**, and that failure is correct. Read the new shape rather than
pinning the old one.

## 7. Silent: `description` changed format

```diff
-"city 🅂"        // name + type glyph
+"city: Moscow"   // name + rendered value
```

Anything logging `String(describing: node)`, or interpolating a node into a message, changes output.
For the whole subtree there is now `treeDescription` — see section 11.

## 8. Silent: equality follows the data

1.0.0's `==` and `hash(into:)` used `id` alone. Combined with a fresh `UUID` per node, that meant
**no two nodes were ever equal** — including a node and its own rebuild — and every node was a
distinct key in a `Set` or `Dictionary`.

2.0.0 compares path, name, kind, type name, rendering, truncation and children; `value` is excluded
because `Any` is not comparable. So two trees over equal data are now equal, and two trees of the
same *shape* over different data are not.

Code that relied on the old semantics changes behaviour without changing shape:

- `Set<PropertyNode>` **now deduplicates** structurally identical nodes. If you used a set as an
  accumulator, it will hold fewer elements than before.
- `nodes.contains(node)` and `firstIndex(of:)` now match a structurally equal node, not only the
  same instance.
- A diff keyed on `!=` now reports "unchanged" where it previously reported "changed every time",
  which is the point — but if some downstream refresh depended on always being told "changed", it
  now stops firing.

## 9. Silent: depth is bounded

`maxDepth` defaults to 16. A value nested deeper than that yields a node that keeps its `kind` and
its child count, reports `isTruncated == true`, and has `children == nil`.

```swift
let tree = PropertyNode(reflecting: deeplyNested, named: "root", maxDepth: 64)
```

Raise the argument if you need more; do not read the limit as something to remove. It is what stops
a reference cycle — two objects pointing at each other — from recursing until the stack is
exhausted, which is what 1.0.0 did: measured still descending at 5 000 levels. Cycles are
*survived*, not detected, so a cyclic graph renders as a repeating chain down to the limit
([PT-1](./Tech-Debt.md)).

A related quiet change: a `.structure` whose type has its own `CustomStringConvertible` conformance
now renders that description as its `displayValue`, where 1.0.0 rendered the child count. The node
still expands to its properties.

## 10. What you gain

- **`kind`** — `value`, `structure`, `collection`, `dictionary`, `enumeration`. This retires 1.0.0's
  first documented known limit: a dictionary and a struct both produce a node with named children,
  and nothing else told them apart.
- **`typeName`** — the dynamic type, correct for optionals.
- **`isTruncated`**, so a cut-off branch is not mistaken for a leaf.
- **`treeDescription`** — the subtree as indented text, for a console or a test:

  ```
  order: 3
  ├── id: 7
  ├── address: 2
  │   ├── city: Moscow
  │   └── street: Arbat
  └── tags: 2
      ├── [0]: a
      └── [1]: b
  ```
- **Sets, enums, tuples, and dictionaries with keys of any type** all reflect properly. 1.0.0
  recognised `[Any]` and `[String: Any]` and nothing else.
- **`Date`, `URL`, `Data` and `Decimal` are leaves** instead of branches over
  `timeIntervalSinceReferenceDate`, `_url`, a byte buffer and `_mantissa`.
- **Stable identity**, so an `OutlineGroup` keeps its expanded rows across a rebuild.
- **No crash on a reference cycle.**
- **`displayValue` and `typeName` are stored**, computed once while the tree is built rather than on
  every SwiftUI body evaluation of every visible row.

## 11. Checklist

1. Point the dependency at `PropertyTree`, `from: "2.0.0"`, and change every `import`.
2. Build. Fix in this order: `createPropertyTree` → `node.id` as `UUID` → hand-built nodes and
   `replacing(children:)` → `selectedKeyPathsToMirror` labels.
3. Delete any workaround for unstable identity — node caches between rebuilds, or your own id map.
4. Re-read, don't re-pin, any test asserting tree shape: if you called `init(reflecting:named:)` in
   1.0.0, the shape changed on purpose (section 6).
5. Check log formats and diff logic for the two silent semantic changes: `description` (section 7)
   and equality (section 8).
6. Decide whether `maxDepth: 16` suits your data, and whether `PropertyNode` retaining the reflected
   graph matters for where you hold the tree ([PT-5](./Tech-Debt.md)).

## See Also

- [Design](./Design.md) — each decision with the alternative it rejected
- [Tech-Debt](./Tech-Debt.md) — the `PT-#` register, including what 2.0.0 discharged
- [Roadmap](./Roadmap.md)
- [CHANGELOG](../CHANGELOG.md)
