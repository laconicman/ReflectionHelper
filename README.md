# ReflectionHelper

Turns any Swift value into a browsable tree, and lets a type decide what `Mirror` shows of it.

Two small pieces, both built on `Mirror`:

- **`PropertyNode`** — an `Identifiable` tree node built by reflecting a value, ready to drive a
  SwiftUI `OutlineGroup`.
- **`SelectivelyReflectable`** — a protocol that lets a type list exactly which properties its
  mirror exposes, including computed ones, which `Mirror` omits by default.

Written to inspect decoded API responses in a debug UI. It is deliberately small.

## Installation

```swift
.package(url: "https://github.com/laconicman/ReflectionHelper", from: "1.0.0")
```

## Building a tree

`createPropertyTree(reflecting:named:)` walks a value and produces a node per property, per
array element, or per dictionary key:

```swift
struct Address { let city: String; let street: String }
struct Order { let id: Int; let address: Address; let tags: [String] }

let tree = PropertyNode.createPropertyTree(
    reflecting: Order(id: 7, address: .init(city: "Москва", street: "Арбат"), tags: ["a", "b"]),
    named: "order"
)
// order
// ├── id       7
// ├── address
// │   ├── city    Москва
// │   └── street  Арбат
// └── tags
//     ├── [0]  a
//     └── [1]  b
```

Three behaviours worth knowing, because they are what make the output readable:

- **Optionals are unwrapped.** `Mirror` reflects `Optional.some` as a node named `some` wrapping
  the value; the tree collapses that, so `String?` looks like `String`.
- **Arrays are indexed** — `[0]`, `[1]` — rather than reflected as `Array`'s internals.
- **Dictionaries are sorted by key**, so two runs over the same data produce the same tree.

`displayValue` renders a leaf through `CustomStringConvertible`, falling back to
`CustomDebugStringConvertible` and then `String(describing:)`. For a node with children it is
the child count.

There is a plain `init(reflecting:named:)` too. It is the shallow version — one `Mirror` pass,
no optional unwrapping and no array or dictionary handling — so prefer `createPropertyTree` for
anything you intend to display.

## Choosing what a type reflects

`Mirror` shows stored properties only. Conform to `SelectivelyReflectable` to control the list,
which is the only way to surface computed properties:

```swift
struct Offer: SelectivelyReflectable {
    let price: Double
    let vat: Double
    var total: Double { price + vat }          // computed — invisible to Mirror by default

    static var selectedKeyPathsToMirror: [(String, PartialKeyPath<Offer>)] = [
        ("price", \.price),
        ("total", \.total),                    // now it appears
    ]
}
```

The protocol refines `CustomReflectable` and supplies `customMirror` for you. For the
all-properties case without listing them by hand, a macro such as
[KeyPathIterable](https://github.com/Ryu0118/KeyPathIterable) is the better tool.

## Known limits

- **A dictionary and a struct look the same** in a built tree — both become a node with named
  children. Distinguishing them needs `displayValue` to switch on value *and* structure.
- **No depth limit.** A deeply nested or recursive value produces a deep tree; there is no
  cut-off yet.
- **Not thread-safe by design** — it holds `Any`, so it inherits whatever the reflected value is.
  `createPropertyTree` itself is pure and `static`, hence implicitly `@Sendable` (SE-0418).

Source comments are in Russian; the public API and this README are in English.

## License

Apache 2.0 — see [LICENSE](LICENSE).
