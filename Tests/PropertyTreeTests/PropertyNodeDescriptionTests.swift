import Testing
@testable import PropertyTree

@Suite("Text rendering")
struct PropertyNodeDescriptionTests {
    struct Address { let city: String; let street: String }
    struct Order { let id: Int; let address: Address; let tags: [String] }

    static let order = Order(
        id: 7,
        address: Address(city: "Moscow", street: "Arbat"),
        tags: ["a", "b"]
    )

    @Test("A node describes itself on one line")
    func describesOneNode() {
        let tree = PropertyNode(reflecting: Self.order, named: "order")
        let city = tree.children?
            .first { $0.name == "address" }?.children?
            .first { $0.name == "city" }

        #expect(city?.description == "city: Moscow")
    }

    @Test("A subtree renders as an indented tree")
    func drawsTheSubtree() {
        let expected = """
        order: 3
        ├── id: 7
        ├── address: 2
        │   ├── city: Moscow
        │   └── street: Arbat
        └── tags: 2
            ├── [0]: a
            └── [1]: b
        """

        #expect(PropertyNode(reflecting: Self.order, named: "order").treeDescription == expected)
    }

    @Test("A truncated node is marked")
    func marksTruncation() {
        let expected = """
        order: 3
        ├── id: 7
        ├── address: 2 …
        └── tags: 2 …
        """

        let tree = PropertyNode(reflecting: Self.order, named: "order", maxDepth: 1)

        #expect(tree.treeDescription == expected)
    }
}
