//
//  PropertyNode+Description.swift
//  PropertyTree
//

// MARK: - PropertyNode + CustomStringConvertible

extension PropertyNode: CustomStringConvertible {
    /// The node itself on one line — `"city: Moscow"`.
    ///
    /// For the whole subtree, use ``treeDescription``.
    public var description: String {
        "\(name): \(displayValue)"
    }
}

// MARK: - Rendering a subtree

public extension PropertyNode {

    /// The subtree drawn as indented text, for inspecting a value from a console
    /// or a test rather than a SwiftUI outline.
    ///
    /// ```swift
    /// print(PropertyNode(reflecting: order, named: "order").treeDescription)
    /// // order: 3
    /// // ├── id: 7
    /// // ├── address: 2
    /// // │   ├── city: Moscow
    /// // │   └── street: Arbat
    /// // └── tags: 2
    /// //     ├── [0]: a
    /// //     └── [1]: b
    /// ```
    ///
    /// A truncated node is marked with an ellipsis.
    var treeDescription: String {
        ([description + (isTruncated ? " …" : "")] + childLines()).joined(separator: "\n")
    }

    private func childLines() -> [String] {
        guard let children, !children.isEmpty else { return [] }

        return children.enumerated().flatMap { index, child -> [String] in
            let isLast = index == children.count - 1
            return child.treeDescription
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { offset, line in
                    let prefix = offset == 0
                        ? (isLast ? "└── " : "├── ")
                        : (isLast ? "    " : "│   ")
                    return prefix + line
                }
        }
    }
}
