import Foundation
import Testing
@testable import PropertyTree

@Suite("Selective reflection")
struct SelectivelyReflectableTests {
    struct Offer: SelectivelyReflectable {
        let price: Double
        let vat: Double
        var total: Double { price + vat }

        static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Offer>)] {
            [("price", \.price), ("total", \.total)]
        }
    }

    @Test("A computed property appears, and an unlisted stored one does not")
    func mirrorsTheSelectedKeyPaths() {
        // The whole point: `Mirror` shows stored properties only, so `total`
        // would be invisible and `vat` unavoidable. Conforming inverts both.
        let children = Mirror(reflecting: Offer(price: 100, vat: 20)).children

        #expect(children.map(\.label) == ["price", "total"])
        #expect(children.compactMap { $0.value as? Double } == [100, 120])
    }

    @Test("The selection is what a built tree shows")
    func drivesTheTree() {
        let tree = PropertyNode(reflecting: Offer(price: 100, vat: 20), named: "offer")

        #expect(tree.children?.map(\.name) == ["price", "total"])
        #expect(tree.children?.map(\.displayValue) == ["100.0", "120.0"])
    }

    @Test("The listed order is the order shown")
    func preservesTheListedOrder() {
        struct Reversed: SelectivelyReflectable {
            let a = 1
            let b = 2

            static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Reversed>)] {
                [("b", \.b), ("a", \.a)]
            }
        }

        #expect(PropertyNode(reflecting: Reversed(), named: "r").children?.map(\.name) == ["b", "a"])
    }
}
