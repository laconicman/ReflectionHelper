import Foundation
import Testing
@testable import ReflectionHelper

/// The tree builder's job is to make a value *readable*, so these pin the three transformations
/// that do that — unwrapping optionals, indexing arrays, ordering dictionaries — rather than
/// restating what `Mirror` already does.
@Suite("Property tree")
struct PropertyTreeTests {
    struct Address { let city: String; let street: String }
    struct Order { let id: Int; let address: Address; let tags: [String] }

    @Test("A struct becomes one node per stored property")
    func reflectsStoredProperties() {
        let tree = PropertyNode.createPropertyTree(
            reflecting: Order(id: 7, address: .init(city: "Москва", street: "Арбат"), tags: ["a"]),
            named: "order"
        )

        #expect(tree.name == "order")
        #expect(tree.children?.map(\.name) == ["id", "address", "tags"])
    }

    @Test("Nesting is preserved")
    func nestsChildren() {
        let tree = PropertyNode.createPropertyTree(
            reflecting: Order(id: 7, address: .init(city: "Москва", street: "Арбат"), tags: []),
            named: "order"
        )
        let address = tree.children?.first { $0.name == "address" }

        #expect(address?.children?.map(\.name) == ["city", "street"])
        #expect(address?.hasChildren == true)
    }

    @Test("An optional is unwrapped rather than shown as `some`")
    func unwrapsOptionals() {
        // `Mirror` reflects `.some(x)` as a child labelled "some". Left alone, every optional
        // in a tree would add a meaningless level.
        let value: String? = "present"

        let tree = PropertyNode.createPropertyTree(reflecting: value, named: "name")

        #expect(tree.name == "name")
        #expect(tree.hasChildren == false)
        #expect(tree.displayValue == "present")
    }

    @Test("Array elements are indexed, not reflected as Array internals")
    func indexesArrayElements() {
        let tree = PropertyNode.createPropertyTree(reflecting: ["a", "b", "c"], named: "tags")

        #expect(tree.children?.map(\.name) == ["[0]", "[1]", "[2]"])
        #expect(tree.children?.map(\.displayValue) == ["a", "b", "c"])
    }

    @Test("Dictionary keys are sorted, so the tree is stable across runs")
    func sortsDictionaryKeys() {
        // Dictionary ordering is not defined. Without the sort, the same data would render
        // differently on each launch.
        let subject: [String: Any] = ["zulu": 1, "alpha": 2, "mike": 3]

        let names = PropertyNode.createPropertyTree(reflecting: subject, named: "root").children?.map(\.name)

        #expect(names == ["alpha", "mike", "zulu"])
    }

    @Test("A leaf renders its value; a branch renders its child count")
    func rendersDisplayValue() {
        let leaf = PropertyNode.createPropertyTree(reflecting: 42, named: "answer")
        let branch = PropertyNode.createPropertyTree(reflecting: ["a", "b"], named: "tags")

        #expect(leaf.displayValue == "42")
        #expect(branch.displayValue == "2")
    }

    @Test("Identity is per node, so a tree can drive a SwiftUI OutlineGroup")
    func nodesAreIdentifiable() {
        let a = PropertyNode(name: "x", value: 1)
        let b = PropertyNode(name: "x", value: 1)

        #expect(a.id != b.id)
    }
}

@Suite("Selective reflection")
struct SelectivelyReflectableTests {
    struct Offer: SelectivelyReflectable {
        let price: Double
        let vat: Double
        var total: Double { price + vat }

        static var selectedKeyPathsToMirror: [(String, PartialKeyPath<Offer>)] {
            [("price", \.price), ("total", \.total)]
        }
    }

    @Test("A computed property appears, and an unlisted stored one does not")
    func mirrorsTheSelectedKeyPaths() {
        // The whole point: `Mirror` shows stored properties only, so `total` would be invisible
        // and `vat` unavoidable. Conforming inverts both.
        let children = Mirror(reflecting: Offer(price: 100, vat: 20)).children

        #expect(children.map(\.label) == ["price", "total"])
        #expect(children.compactMap { $0.value as? Double } == [100, 120])
    }
}
