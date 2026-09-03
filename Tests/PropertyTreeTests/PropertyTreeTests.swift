import Foundation
import Testing
@testable import PropertyTree

/// The walker's job is to make a value *readable*, so these pin the
/// transformations that do that — collapsing optionals, indexing collections,
/// ordering dictionaries and sets, treating opaque Foundation types as values —
/// rather than restating what `Mirror` already does.
@Suite("Property tree")
struct PropertyTreeTests {
    struct Address { let city: String; let street: String }
    struct Order { let id: Int; let address: Address; let tags: [String] }

    static func order(tags: [String] = ["a", "b"]) -> Order {
        Order(id: 7, address: Address(city: "Moscow", street: "Arbat"), tags: tags)
    }

    // MARK: Structures

    @Test("A struct becomes one node per stored property")
    func reflectsStoredProperties() {
        let tree = PropertyNode(reflecting: Self.order(), named: "order")

        #expect(tree.name == "order")
        #expect(tree.kind == .structure)
        #expect(tree.children?.map(\.name) == ["id", "address", "tags"])
    }

    @Test("Nesting is preserved")
    func nestsChildren() {
        let tree = PropertyNode(reflecting: Self.order(), named: "order")
        let address = tree.children?.first { $0.name == "address" }

        #expect(address?.children?.map(\.name) == ["city", "street"])
        #expect(address?.hasChildren == true)
    }

    @Test("A class reflects like a struct")
    func reflectsClasses() {
        final class Session { let token = "abc" }

        let tree = PropertyNode(reflecting: Session(), named: "session")

        #expect(tree.kind == .structure)
        #expect(tree.children?.map(\.name) == ["token"])
    }

    @Test("A tuple's elements keep their labels, or their positions when unlabelled")
    func reflectsTuples() {
        let labelled = PropertyNode(reflecting: (n: 1, s: "a"), named: "pair")
        let positional = PropertyNode(reflecting: (1, "a"), named: "pair")

        #expect(labelled.children?.map(\.name) == ["n", "s"])
        #expect(positional.children?.map(\.name) == [".0", ".1"])
    }

    // MARK: Optionals

    @Test("An optional is collapsed rather than shown as `some`")
    func collapsesOptionals() {
        // `Mirror` reflects `.some(x)` as a child labelled "some". Left alone,
        // every optional in a tree would add a meaningless level.
        let value: String? = "present"

        let tree = PropertyNode(reflecting: value, named: "name")

        #expect(tree.kind == .value)
        #expect(tree.hasChildren == false)
        #expect(tree.displayValue == "present")
        #expect(tree.typeName == "String")
    }

    @Test("A nil optional renders as `nil` and still reports its type")
    func rendersNil() {
        let value: Int? = nil

        let tree = PropertyNode(reflecting: value, named: "count")

        #expect(tree.kind == .value)
        #expect(tree.displayValue == "nil")
        #expect(tree.typeName == "Optional<Int>")
    }

    @Test("Every optional type reports its own type, not the first one tried")
    func typeNamesAreNotConfusedAcrossOptionals() {
        // Regression: a dynamic cast from `Any` matches *any* nil optional
        // against *any* optional type, so a table of `case is String?` arms
        // labelled every nil as a String. `typeName` reads the metatype instead.
        let noString: String? = nil
        let noDate: Date? = nil
        let noDouble: Double? = nil

        #expect(PropertyNode(reflecting: noString, named: "a").typeName == "Optional<String>")
        #expect(PropertyNode(reflecting: noDate, named: "b").typeName == "Optional<Date>")
        #expect(PropertyNode(reflecting: noDouble, named: "c").typeName == "Optional<Double>")
    }

    // MARK: Collections

    @Test("Array elements are indexed, not reflected as Array internals")
    func indexesArrayElements() {
        let tree = PropertyNode(reflecting: ["a", "b", "c"], named: "tags")

        #expect(tree.kind == .collection)
        #expect(tree.children?.map(\.name) == ["[0]", "[1]", "[2]"])
        #expect(tree.children?.map(\.displayValue) == ["a", "b", "c"])
    }

    @Test("A set is ordered by its rendered elements, so the tree is stable across runs")
    func ordersSetElements() {
        // `Set` has no order of its own; without sorting, the same data would
        // render differently on each launch.
        let tree = PropertyNode(reflecting: Set(["zulu", "alpha", "mike"]), named: "ids")

        #expect(tree.kind == .collection)
        #expect(tree.children?.map(\.displayValue) == ["alpha", "mike", "zulu"])
        #expect(tree.children?.map(\.name) == ["[0]", "[1]", "[2]"])
    }

    @Test("An empty collection stays a collection with no children")
    func keepsEmptyCollectionsAsCollections() {
        let tree = PropertyNode(reflecting: [String](), named: "tags")

        #expect(tree.kind == .collection)
        #expect(tree.children == nil)
        #expect(tree.displayValue == "0")
    }

    // MARK: Dictionaries

    @Test("Dictionary keys are sorted, so the tree is stable across runs")
    func sortsDictionaryKeys() {
        let subject: [String: Any] = ["zulu": 1, "alpha": 2, "mike": 3]

        let tree = PropertyNode(reflecting: subject, named: "root")

        #expect(tree.kind == .dictionary)
        #expect(tree.children?.map(\.name) == ["alpha", "mike", "zulu"])
    }

    @Test("A dictionary with non-String keys is keyed too, ordered by rendered key")
    func handlesNonStringKeys() {
        // Regression: only `[String: Any]` used to be recognised, so every other
        // dictionary reflected as unlabelled `(key:value:)` tuples. Ordering is
        // lexicographic on the rendered key — hence "10" before "2".
        let tree = PropertyNode(reflecting: [2: "b", 10: "j", 1: "a"], named: "map")

        #expect(tree.kind == .dictionary)
        #expect(tree.children?.map(\.name) == ["1", "10", "2"])
        #expect(tree.children?.map(\.displayValue) == ["a", "j", "b"])
    }

    @Test("A dictionary and a struct are told apart by kind")
    func distinguishesDictionariesFromStructures() {
        // Both produce a node with named children; `kind` is the only thing that
        // separates them.
        let dictionary = PropertyNode(reflecting: ["city": "Moscow", "street": "Arbat"], named: "a")
        let structure = PropertyNode(reflecting: Address(city: "Moscow", street: "Arbat"), named: "b")

        #expect(dictionary.children?.map(\.name) == structure.children?.map(\.name))
        #expect(dictionary.kind == .dictionary)
        #expect(structure.kind == .structure)
    }

    // MARK: Enums

    @Test("An enum case renders as its case name and expands its associated values")
    func reflectsEnumCases() {
        enum Shape { case circle(radius: Double, filled: Bool); case square; case line(Double) }

        let circle = PropertyNode(reflecting: Shape.circle(radius: 1, filled: true), named: "shape")
        let square = PropertyNode(reflecting: Shape.square, named: "shape")
        let line = PropertyNode(reflecting: Shape.line(3), named: "shape")

        #expect(circle.kind == .enumeration)
        #expect(circle.displayValue == "circle(radius: 1.0, filled: true)")
        #expect(circle.children?.map(\.name) == ["radius", "filled"])

        #expect(square.kind == .enumeration)
        #expect(square.displayValue == "square")
        #expect(square.children == nil)

        #expect(line.children?.map(\.displayValue) == ["3.0"])
    }

    // MARK: Opaque values

    @Test("Foundation value types are leaves, not branches over their internals")
    func treatsFoundationValueTypesAsLeaves() {
        // Regression: reflected, these expose `timeIntervalSinceReferenceDate`,
        // `_url`, a byte buffer and `_mantissa` in place of the value.
        let cases: [(name: String, value: Any)] = [
            ("date", Date(timeIntervalSince1970: 0)),
            ("url", URL(string: "https://example.com")!),
            ("data", Data([1, 2, 3])),
            ("decimal", Decimal(string: "1.5")!),
            ("uuid", UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        ]

        for element in cases {
            let node = PropertyNode(reflecting: element.value, named: element.name)
            #expect(node.kind == .value, "\(element.name) should be a leaf")
            #expect(node.children == nil, "\(element.name) should have no children")
            // Deliberately compared against the type's own rendering rather than
            // a hardcoded string: Foundation's formatting of these types is not
            // contractual and differs between Darwin and corelibs.
            #expect(node.displayValue == String(describing: element.value))
        }
    }

    @Test("An opaque value renders as the value, not as a number")
    func rendersOpaqueValuesReadably() {
        // The point of the leaf list: a date must not arrive as a
        // `timeIntervalSinceReferenceDate` Double, nor a URL as `_url`.
        let date = PropertyNode(reflecting: Date(timeIntervalSince1970: 0), named: "when")
        let url = PropertyNode(reflecting: URL(string: "https://example.com")!, named: "url")
        let uuid = PropertyNode(
            reflecting: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            named: "id"
        )

        #expect(date.displayValue.contains("1970"))
        #expect(url.displayValue == "https://example.com")
        #expect(uuid.displayValue == "00000000-0000-0000-0000-000000000001")
    }

    // MARK: Identity

    @Test("A node's id is its path from the root")
    func identifiesNodesByPath() {
        let tree = PropertyNode(reflecting: Self.order(), named: "order")
        let city = tree.children?.first { $0.name == "address" }?
            .children?.first { $0.name == "city" }
        let firstTag = tree.children?.first { $0.name == "tags" }?.children?.first

        #expect(tree.id == "order")
        #expect(city?.id == "order.address.city")
        #expect(firstTag?.id == "order.tags[0]")
    }

    @Test("Reflecting the same value twice produces the same identities")
    func identitiesAreStableAcrossRebuilds() {
        // Regression: identities used to be fresh UUIDs, so a rebuilt tree
        // collapsed every expanded row of a SwiftUI OutlineGroup.
        let first = PropertyNode(reflecting: Self.order(), named: "order")
        let second = PropertyNode(reflecting: Self.order(), named: "order")

        #expect(first.id == second.id)
        #expect(first.children?.map(\.id) == second.children?.map(\.id))
        #expect(first == second)
    }

    @Test("Trees of the same shape over different data are not equal")
    func equalityFollowsTheData() {
        let first = PropertyNode(reflecting: Self.order(tags: ["a"]), named: "order")
        let second = PropertyNode(reflecting: Self.order(tags: ["b"]), named: "order")

        #expect(first != second)
    }

    // MARK: Depth

    @Test("A value deeper than maxDepth is truncated and says so")
    func truncatesBeyondMaxDepth() {
        let tree = PropertyNode(reflecting: Self.order(), named: "order", maxDepth: 1)
        let address = tree.children?.first { $0.name == "address" }

        #expect(address?.isTruncated == true)
        #expect(address?.children == nil)
        // The count survives truncation, so a display can still say what was cut.
        #expect(address?.displayValue == "2")
        #expect(address?.kind == .structure)
    }

    @Test("A leaf is never marked truncated")
    func doesNotMarkLeavesTruncated() {
        let tree = PropertyNode(reflecting: Self.order(), named: "order", maxDepth: 1)
        let id = tree.children?.first { $0.name == "id" }

        #expect(id?.isTruncated == false)
        #expect(id?.displayValue == "7")
    }

    @Test("A reference cycle terminates instead of exhausting the stack")
    func survivesReferenceCycles() {
        // Regression: two objects pointing at each other recursed without bound.
        // The depth limit is what stops it.
        final class Link {
            let name: String
            var next: Link?
            init(_ name: String) { self.name = name }
        }
        let a = Link("a")
        let b = Link("b")
        a.next = b
        b.next = a

        let tree = PropertyNode(reflecting: a, named: "a", maxDepth: 6)

        // Bounded: `maxDepth` levels below the root, plus the root itself.
        #expect(depth(of: tree) == 7)
        #expect(flattened(tree).contains { $0.isTruncated })
    }

    // MARK: Rendering

    @Test("A leaf renders its value; a container renders its child count")
    func rendersDisplayValue() {
        let leaf = PropertyNode(reflecting: 42, named: "answer")
        let container = PropertyNode(reflecting: ["a", "b"], named: "tags")

        #expect(leaf.displayValue == "42")
        #expect(container.displayValue == "2")
    }

    @Test("A type's own description wins over reflection")
    func prefersCustomStringConvertible() {
        struct Money: CustomStringConvertible {
            let amount: Int
            var description: String { "\(amount) ₽" }
        }

        let tree = PropertyNode(reflecting: Money(amount: 5), named: "price")

        #expect(tree.displayValue == "5 ₽")
        // …and the node still opens onto the properties behind that rendering.
        #expect(tree.kind == .structure)
        #expect(tree.children?.map(\.name) == ["amount"])
    }
}

// MARK: - Helpers

private func depth(of node: PropertyNode) -> Int {
    1 + (node.children?.map(depth(of:)).max() ?? 0)
}

private func flattened(_ node: PropertyNode) -> [PropertyNode] {
    [node] + (node.children ?? []).flatMap(flattened)
}
