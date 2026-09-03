# ``PropertyTree``

Turn any Swift value into a browsable tree, and let a type decide what `Mirror` shows of it.

## Overview

`Mirror` will describe any value, but its literal output is a poor *description* of one: optionals
arrive wrapped in a `some` level, arrays expose their internals, dictionaries come back as unnamed
`(key:value:)` pairs, a `Date` becomes a `timeIntervalSinceReferenceDate`, and a reference cycle
recurses forever.

``PropertyNode`` walks a value and produces a readable tree instead — one node per property,
element or key — ready to drive a SwiftUI `OutlineGroup`:

```swift
import PropertyTree

let tree = PropertyNode(reflecting: order, named: "order")

List {
    OutlineGroup(tree, children: \.children) { node in
        LabeledContent(node.name, value: node.displayValue)
    }
}
```

Or read it straight out of a console with ``PropertyNode/treeDescription``:

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

Node identity is the node's **path** (`"order.address.city"`), so a rebuilt tree keeps an outline's
expanded rows instead of collapsing them.

The other half of the package is ``SelectivelyReflectable``, which lets a type list exactly which
properties its mirror exposes — the only way to surface a *computed* property, which `Mirror` omits.

The **direction docs** — architecture decisions and their rejected alternatives, roadmap, and the
debt register — live in [`docs/`](https://github.com/laconicman/PropertyTree/tree/main/docs) in the
repository and are authoritative.

## Topics

### Building a tree

- ``PropertyNode``
- ``PropertyNode/init(reflecting:named:maxDepth:)``

### Reading a node

- ``PropertyNode/name``
- ``PropertyNode/displayValue``
- ``PropertyNode/typeName``
- ``PropertyNode/kind``
- ``PropertyNode/value``

### Walking the tree

- ``PropertyNode/id``
- ``PropertyNode/children``
- ``PropertyNode/hasChildren``
- ``PropertyNode/isTruncated``

### Rendering as text

- ``PropertyNode/description``
- ``PropertyNode/treeDescription``

### Choosing what a type reflects

- ``SelectivelyReflectable``
- ``SelectivelyReflectable/selectedKeyPathsToMirror``
