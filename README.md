# PropertyTree

[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2FPropertyTree%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/laconicman/PropertyTree)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Flaconicman%2FPropertyTree%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/laconicman/PropertyTree)
[![License](https://img.shields.io/github/license/laconicman/PropertyTree)](LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/laconicman/PropertyTree)

Turn any Swift value into a browsable tree, and let a type decide what `Mirror` shows of it.

`Mirror` will describe any value, but its literal output is a poor *description* of one. Optionals
arrive wrapped in a `some` level. Dictionaries come back as unnamed `(key:value:)` pairs — and only
if you thought to handle them. A `Date` becomes a `timeIntervalSinceReferenceDate`. A reference
cycle recurses until the stack is gone.

PropertyTree walks a value and produces something readable instead:

```swift
import PropertyTree

struct Address { let city: String; let street: String }
struct Order { let id: Int; let address: Address; let tags: [String] }

let tree = PropertyNode(
    reflecting: Order(id: 7, address: .init(city: "Moscow", street: "Arbat"), tags: ["a", "b"]),
    named: "order"
)

print(tree.treeDescription)
// order: 3
// ├── id: 7
// ├── address: 2
// │   ├── city: Moscow
// │   └── street: Arbat
// └── tags: 2
//     ├── [0]: a
//     └── [1]: b
```

Written to inspect decoded API responses in a debug UI. It is deliberately small: two types, no
dependencies, Foundation only.

Release history, breaking changes and known limitations: [CHANGELOG](CHANGELOG.md).

## Direction docs

The authoritative architecture, plan, and debt register live under [`docs/`](docs/):
[Design](docs/Design.md) (decisions + rejected alternatives), [Roadmap](docs/Roadmap.md)
(Now/Next/Later), [Tech-Debt](docs/Tech-Debt.md) (`PT-#` register), and
[Migration](docs/Migration.md) (1.0.0 → 2.0.0, every break and its edit). The notes below are a
summary; those docs are authoritative.

## Driving a SwiftUI outline

`PropertyNode` is `Identifiable`, and its `id` is the node's **path** from the root —
`"order.address.city"`, `"order.tags[0]"`. Reflecting the same value twice produces the same
identities, so a rebuilt tree keeps the rows a reader had expanded instead of collapsing them.

```swift
List {
    OutlineGroup(tree, children: \.children) { node in
        LabeledContent(node.name, value: node.displayValue)
    }
}
```

## What the walker does to make a value readable

- **Optionals collapse.** `Mirror` reflects `.some(x)` as a child labelled `some`; that level is
  removed, so a `String?` looks like a `String`. A `nil` becomes a leaf rendering `"nil"` — and
  still reports its type, `Optional<Int>`.
- **Collections are indexed** `[0]`, `[1]`, … rather than reflected as `Array`'s internals. Sets
  are ordered by their rendered elements, since set order is otherwise undefined between runs.
- **Dictionaries are keyed and ordered by key** — for *any* key type, not just `String`.
- **Enum cases** render as the case name, associated values and all — `circle(radius: 1.0)` — and
  expand to those values.
- **`Date`, `URL`, `Data` and `Decimal` are leaves.** Reflected, they expose
  `timeIntervalSinceReferenceDate`, `_url`, a byte buffer and `_mantissa` — noise in place of the
  value.
- **Depth is bounded** (`maxDepth`, default 16). This is what stops a reference cycle from
  recursing until the stack is exhausted; a node at the limit reports `isTruncated` and still says
  how many children were cut.

All of it dispatches on `Mirror.DisplayStyle` rather than casting to concrete types, which is why
`Set`, `[Int: String]`, enums and tuples work at all — see
[Design](docs/Design.md) § Dispatch on `Mirror.DisplayStyle`.

## Reading a node

| | |
|---|---|
| `name` | the property name, index (`[0]`) or dictionary key it was reached by |
| `displayValue` | the rendered value; for a container, its child count |
| `typeName` | the dynamic type, correct for optionals too (`Optional<Int>`) |
| `kind` | `value`, `structure`, `collection`, `dictionary`, `enumeration` |
| `value` | the reflected value itself, to downcast if you want to |
| `children` / `hasChildren` / `isTruncated` | the shape below this node |

`kind` is what tells a **dictionary from a struct** — both produce a node with named children, and
nothing else separates them.

## Choosing what a type reflects

`Mirror` shows stored properties: all of them, and nothing else. Conform to
`SelectivelyReflectable` to invert both halves of that — an unlisted stored property disappears,
and a computed one, otherwise invisible, appears:

```swift
struct Offer: SelectivelyReflectable {
    let price: Double
    let vat: Double
    var total: Double { price + vat }          // computed — invisible to Mirror by default

    static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Offer>)] {
        [("price", \.price), ("total", \.total)]
    }
}

// offer: 2
// ├── price: 100.0
// └── total: 120.0
```

The protocol refines `CustomReflectable` and supplies `customMirror` for you. Conform a protocol to
it to select the same properties across a family of types. For the *all* properties case without
listing them by hand, a macro such as
[KeyPathIterable](https://github.com/Ryu0118/KeyPathIterable) is the better tool — this protocol is
for choosing.

## Installation

```swift
.package(url: "https://github.com/laconicman/PropertyTree", from: "2.0.0")
```

No platform floor: the module imports Foundation and nothing else, so it builds wherever Swift
does. Requires Swift 6.0 or later.

Coming from `ReflectionHelper` 1.0.0? [**Migration**](docs/Migration.md) covers every break and
the edit that resolves it — including the four that are *not* compile errors.

## Documentation

API reference is hosted on the
[Swift Package Index](https://swiftpackageindex.com/laconicman/PropertyTree/documentation/propertytree),
generated from the DocC catalog in `Sources/PropertyTree/PropertyTree.docc/` per `.spi.yml`. To
build it locally — no plugin dependency needed, and none is declared:

```sh
xcodebuild docbuild -scheme PropertyTree -destination 'generic/platform=macOS' -derivedDataPath .docc-build
```

## Tests

```sh
swift test
```

The suite pins the transformations that make a tree readable, and carries a named regression test
for each defect 1.0.0 shipped with — see the discharged half of
[Tech-Debt](docs/Tech-Debt.md#discharged-in-200). CI runs it on macOS and on a Linux container.

## License

Apache 2.0 — see [LICENSE](LICENSE).
