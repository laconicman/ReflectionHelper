//
//  PropertyNode.swift
//  PropertyTree
//

import Foundation

/// One node of a property tree: a reflected value, its rendering, and its children.
///
/// Build a tree with ``init(reflecting:named:maxDepth:)`` and drive a SwiftUI
/// `OutlineGroup` from it:
///
/// ```swift
/// let tree = PropertyNode(reflecting: order, named: "order")
///
/// List {
///     OutlineGroup(tree, children: \.children) { node in
///         LabeledContent(node.name, value: node.displayValue)
///     }
/// }
/// ```
///
/// ### Identity
///
/// ``id`` is the node's **path** from the root — `"order.address.city"`,
/// `"order.tags[0]"` — not a fresh `UUID`. Reflecting the same value twice
/// therefore produces the same identities, so a rebuilt tree keeps an
/// `OutlineGroup`'s expansion state instead of collapsing it.
///
/// Paths are **unique within a tree**: siblings whose names would collide get a
/// `#2`, `#3`, … suffix. They are **stable across rebuilds** whenever each set
/// of siblings renders distinctly, which is every ordinary value; two dictionary
/// keys or set elements that render identically are ordered arbitrarily, so
/// which of them holds which index can change between runs.
///
/// ### Sendability
///
/// `PropertyNode` is deliberately **not** `Sendable`: ``value`` is `Any`, so a
/// node is exactly as safe to share as whatever was reflected into it. Build the
/// tree on the actor that owns the value.
public struct PropertyNode: Identifiable {

    /// The shape the reflected value turned out to have.
    ///
    /// This is what distinguishes a dictionary from a struct — both produce a
    /// node with named children, and without ``kind`` they are indistinguishable.
    public enum Kind: String, Sendable {
        /// A leaf. Its ``PropertyNode/displayValue`` is the rendered value.
        case value
        /// A struct, class or tuple: children are named after its properties.
        case structure
        /// An array, set or other collection: children are indexed `[0]`, `[1]`, …
        case collection
        /// A dictionary: children are named after its keys, ordered by key.
        case dictionary
        /// An enum case, whose associated values are its children.
        case enumeration
    }

    /// The node's path from the root of the tree — unique within the tree, and
    /// stable across rebuilds. See the Identity section above.
    public let id: String

    /// The property name, collection index (`[0]`), or dictionary key this node
    /// was reached by. The root's name is whatever was passed as `named:`.
    public let name: String

    /// The reflected value itself, for a caller that wants to downcast it.
    ///
    /// Holding this keeps the reflected object graph alive for as long as the
    /// tree lives — see ``typeName`` and ``displayValue`` for the rendered form,
    /// which is all a display needs.
    public let value: Any

    /// The value's dynamic type, as `String(describing: type(of: value))`.
    ///
    /// Correct for every value, optionals included (`"Optional<Int>"` for a
    /// `nil`). A UI that wants type badges should switch on this or on ``kind``.
    public let typeName: String

    /// The node's rendered value.
    ///
    /// - For ``Kind/value``: the value through `CustomStringConvertible`, falling
    ///   back to `CustomDebugStringConvertible` and then `String(describing:)`.
    ///   A `nil` optional renders as `"nil"`.
    /// - For ``Kind/enumeration``: the case name, with any associated values —
    ///   `"circle(radius: 1.0)"`.
    /// - For every other kind: the number of children the value has, as a
    ///   string — including when those children were cut off by `maxDepth`.
    public let displayValue: String

    /// What shape the value had. See ``Kind``.
    public let kind: Kind

    /// The node's children, or `nil` for a leaf.
    ///
    /// An empty array is never stored; a childless node has `nil` here.
    public let children: [PropertyNode]?

    /// `true` when the value had children that `maxDepth` cut off.
    ///
    /// Without this a truncated branch would be indistinguishable from a leaf.
    /// ``displayValue`` still reports how many children were skipped.
    public let isTruncated: Bool

    /// `true` when the node has at least one child.
    public var hasChildren: Bool {
        children?.isEmpty == false
    }

    init(
        id: String,
        name: String,
        value: Any,
        typeName: String,
        displayValue: String,
        kind: Kind,
        children: [PropertyNode]?,
        isTruncated: Bool
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.typeName = typeName
        self.displayValue = displayValue
        self.kind = kind
        self.children = children?.isEmpty == false ? children : nil
        self.isTruncated = isTruncated
    }
}

// MARK: - PropertyNode + Hashable

/// Equality compares a node's *description* of a value rather than the value
/// itself: ``PropertyNode/value`` is `Any`, so there is nothing to compare it
/// against. Two nodes are equal when their path, name, kind, type name,
/// rendering, truncation and children agree.
///
/// In practice that makes two trees over equal data equal, and two trees of the
/// same shape over different data unequal — but the guarantee is about the
/// *rendering*, so two values that render identically compare equal however they
/// differ underneath. `Data` was the shipped example of that: its own
/// description is a byte count alone, so any two blobs of one size collapsed. It
/// now renders a hex preview, leaving only blobs that agree in both length and
/// first 16 bytes.
extension PropertyNode: Hashable {
    public static func == (lhs: PropertyNode, rhs: PropertyNode) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.kind == rhs.kind
            && lhs.typeName == rhs.typeName
            && lhs.displayValue == rhs.displayValue
            && lhs.isTruncated == rhs.isTruncated
            && lhs.children == rhs.children
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(kind)
        hasher.combine(typeName)
        hasher.combine(displayValue)
        hasher.combine(isTruncated)
        hasher.combine(children)
    }
}
