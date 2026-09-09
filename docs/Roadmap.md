# PropertyTree — Roadmap

Priority-ordered milestone summary. Rationale lives in [Design](./Design.md); the debt each
milestone discharges is in [Tech-Debt](./Tech-Debt.md).

## Now — 2.0.0, unreleased

The walker is rebuilt on `Mirror.DisplayStyle`, identity is path-based, and the six defects 1.0.0
shipped with are fixed and pinned by tests (30, green).

- **In flight:** first use against a real decoded response. Every fix so far is driven by a test
  or a probe, not by a screen — the shape of a large real payload is what will say whether
  `maxDepth: 16` and the child-count rendering are the right defaults.
- **Before tagging:** CI green on both jobs. The Linux job is the only evidence that the
  Foundation-only claim in `Package.swift` holds; it has never been run.

## Next — the two rough edges a real payload will expose

- **Filtering and pruning** — 1.0.0 carried a commented-out `createFilteredPropertyTree` and a
  `// TODO` for a type filter, which says the need is real. It wants a design, not a port: a
  predicate over nodes (`(PropertyNode) -> Bool`) applied during the walk, so a filtered subtree is
  never built rather than built and discarded. The removal of `replacing(children:)` in 2.0.0
  leaves this the only way to narrow a tree.
- **Ordering** ([PT-2](./Tech-Debt.md)) — dictionary keys and set elements are ordered
  lexicographically on their rendered form, so a `[Int: T]` reads 1, 10, 2. Wrong-looking the first
  time anyone inspects a numerically-keyed dictionary.
- **Lazy rendering** ([PT-6](./Tech-Debt.md)) — only if a real payload makes the eager pass
  noticeable.

## Later — reach

- **Publish.** Tag 2.0.0 and submit to Swift Package Index (`.spi.yml` is in place). The 1.0.0 tag
  stays where it is, under the old name.
- **The snapshot design** ([PT-5](./Tech-Debt.md)) — dropping `value: Any` would make the node
  `Sendable` and `Codable`: buildable off the main actor, and attachable to a bug report. It is a
  3.0.0, and it waits for a consumer who wants it. Rationale and the rejection are in
  [Design](./Design.md).
- **Consumer-extensible leaf policy** ([PT-4](./Tech-Debt.md)) — on demand only. The four
  Foundation types cover what a decoded response contains.
