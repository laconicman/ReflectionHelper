//
//  SelectivelyReflectable.swift
//  PropertyTree
//

import Foundation

/// Lets a type choose exactly which of its properties `Mirror` exposes.
///
/// `Mirror` reflects **stored** properties, all of them and nothing else.
/// Conforming inverts both halves of that: an unlisted stored property
/// disappears, and a computed property — otherwise invisible — appears.
///
/// ```swift
/// struct Offer: SelectivelyReflectable {
///     let price: Double
///     let vat: Double
///     var total: Double { price + vat }        // computed: invisible to Mirror
///
///     static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Offer>)] {
///         [("price", \.price), ("total", \.total)]
///     }
/// }
///
/// PropertyNode(reflecting: Offer(price: 100, vat: 20), named: "offer")
/// // offer: 2
/// // ├── price: 100.0
/// // └── total: 120.0
/// ```
///
/// Conform a protocol to it to select the same properties across a family of
/// types. To expose *every* property without listing them, reach for a macro
/// such as [KeyPathIterable](https://github.com/Ryu0118/KeyPathIterable) instead
/// — this protocol is for choosing.
public protocol SelectivelyReflectable: CustomReflectable {
    /// The properties to expose, in the order they should appear.
    static var selectedKeyPathsToMirror: [(label: String, keyPath: PartialKeyPath<Self>)] { get }
}

public extension SelectivelyReflectable {
    /// Built from ``selectedKeyPathsToMirror``; conforming types need not write
    /// this themselves.
    var customMirror: Mirror {
        Mirror(
            self,
            children: Self.selectedKeyPathsToMirror.map { property in
                Mirror.Child(label: property.label, value: self[keyPath: property.keyPath])
            }
        )
    }
}
