//
//  PropertyNode+Reflection.swift
//  PropertyTree
//
//  The walker. Everything here dispatches on `Mirror.DisplayStyle` rather than
//  casting to concrete types (`as? [Any]`, `as? [String: Any]`), which is what
//  makes `Set`, `[Int: String]`, enums and tuples work at all — see
//  docs/Design.md § Dispatch on `Mirror.DisplayStyle`.
//

import Foundation

public extension PropertyNode {

    /// Reflects a value into a tree of nodes, one per property, collection
    /// element, or dictionary key.
    ///
    /// ```swift
    /// struct Address { let city: String; let street: String }
    /// struct Order { let id: Int; let address: Address; let tags: [String] }
    ///
    /// let tree = PropertyNode(
    ///     reflecting: Order(id: 7, address: .init(city: "Moscow", street: "Arbat"), tags: ["a", "b"]),
    ///     named: "order"
    /// )
    /// ```
    ///
    /// The transformations that make the result readable, rather than a literal
    /// transcript of `Mirror`:
    ///
    /// - **Optionals collapse.** `Mirror` reflects `.some(x)` as a child labelled
    ///   `"some"`; that level is removed, so a `String?` looks like a `String`.
    ///   A `nil` becomes a leaf rendering `"nil"`.
    /// - **Collections are indexed** `[0]`, `[1]`, … rather than reflected as
    ///   `Array`'s internals. Sets are ordered by their rendered elements, since
    ///   set order is otherwise not defined between runs.
    /// - **Dictionaries are keyed and sorted by key**, for any key type — not
    ///   just `String` — so two runs over the same data agree.
    /// - **Enum cases** render as their case name and expand to their associated
    ///   values.
    /// - **`Date`, `URL`, `Data` and `Decimal` are leaves.** Reflected, they
    ///   would expose `timeIntervalSinceReferenceDate`, `_url`, a byte buffer and
    ///   `_mantissa` — noise in place of the value.
    ///
    /// - Parameters:
    ///   - object: The value to reflect.
    ///   - named: The root node's ``PropertyNode/name``, which also roots every
    ///     descendant's ``PropertyNode/id`` path.
    ///   - maxDepth: How many levels below the root to expand. A node at the
    ///     limit keeps its ``PropertyNode/kind`` and child count but reports
    ///     ``PropertyNode/isTruncated``. The limit is what stops a reference
    ///     cycle — two objects pointing at each other — from recursing until the
    ///     stack is exhausted.
    /// - Note: Generic rather than taking `Any`, so that reflecting an optional
    ///   is warning-free at the call site and keeps its static type — the same
    ///   reason `String(describing:)` is generic.
    init<Subject>(reflecting object: Subject, named: String, maxDepth: Int = 16) {
        self = PropertyNode.node(
            reflecting: object,
            name: named,
            path: named,
            depth: 0,
            maxDepth: maxDepth
        )
    }
}

// MARK: - Walking

private extension PropertyNode {

    static func node(
        reflecting object: Any,
        name: String,
        path: String,
        depth: Int,
        maxDepth: Int
    ) -> PropertyNode {
        let mirror = Mirror(reflecting: object)

        // Optionals: collapse `.some`, render `.none` as a leaf. Done before
        // anything else so no other rule ever sees an `Optional`.
        if mirror.displayStyle == .optional {
            if let wrapped = mirror.children.first?.value {
                return node(reflecting: wrapped, name: name, path: path, depth: depth, maxDepth: maxDepth)
            }
            return PropertyNode(
                id: path,
                name: name,
                value: object,
                typeName: typeName(of: object),
                displayValue: "nil",
                kind: .value,
                children: nil,
                isTruncated: false
            )
        }

        let kind = kind(of: object, mirror: mirror)
        let childCount = mirror.children.count
        let isTruncated = kind != .value && childCount > 0 && depth >= maxDepth
        let children: [PropertyNode]? = (kind == .value || depth >= maxDepth)
            ? nil
            : childNodes(of: mirror, kind: kind, path: path, depth: depth, maxDepth: maxDepth)

        return PropertyNode(
            id: path,
            name: name,
            value: object,
            typeName: typeName(of: object),
            displayValue: displayValue(of: object, kind: kind, childCount: childCount),
            kind: kind,
            children: children,
            isTruncated: isTruncated
        )
    }

    static func childNodes(
        of mirror: Mirror,
        kind: Kind,
        path: String,
        depth: Int,
        maxDepth: Int
    ) -> [PropertyNode] {
        func child(_ value: Any, named name: String, component: String? = nil) -> PropertyNode {
            node(
                reflecting: value,
                name: name,
                path: childPath(path, component: component ?? name),
                depth: depth + 1,
                maxDepth: maxDepth
            )
        }

        switch kind {
        case .value:
            return []

        case .collection:
            var elements = mirror.children.map(\.value)
            if mirror.displayStyle == .set {
                // A `Set` has no order of its own, so without this the same data
                // would produce a differently-ordered tree on each launch.
                elements.sort { String(describing: $0) < String(describing: $1) }
            }
            return elements.enumerated().map { index, element in
                child(element, named: "[\(index)]")
            }

        case .dictionary:
            // Each child of a dictionary's mirror is a `(key:value:)` tuple, so
            // keys of any type are reachable — not only `String`.
            return mirror.children
                .compactMap { entry -> (key: String, value: Any)? in
                    let pair = Mirror(reflecting: entry.value).children
                    guard let key = pair.first(where: { $0.label == "key" })?.value,
                          let value = pair.first(where: { $0.label == "value" })?.value
                    else { return nil }
                    return (String(describing: key), value)
                }
                .sorted { $0.key < $1.key }
                .map { entry in
                    child(entry.value, named: entry.key, component: "[\(entry.key)]")
                }

        case .enumeration:
            // A case with associated values reflects as one child: its label is
            // the case name, its value the payload. Flatten a payload tuple so
            // `circle(radius:)` yields a `radius` child rather than a `circle`
            // level wrapping one.
            guard let payload = mirror.children.first else { return [] }
            let payloadMirror = Mirror(reflecting: payload.value)
            if payloadMirror.displayStyle == .tuple {
                return payloadMirror.children.enumerated().map { index, associated in
                    child(associated.value, named: associated.label ?? "[\(index)]")
                }
            }
            return [child(payload.value, named: payload.label ?? "value")]

        case .structure:
            return mirror.children.enumerated().map { index, property in
                child(property.value, named: property.label ?? "[\(index)]")
            }
        }
    }
}

// MARK: - Classification and rendering

private extension PropertyNode {

    static func kind(of object: Any, mirror: Mirror) -> Kind {
        guard !isOpaqueValue(object) else { return .value }

        switch mirror.displayStyle {
        case .collection, .set:
            return .collection
        case .dictionary:
            return .dictionary
        case .enum:
            return .enumeration
        // `.struct`, `.class` and `.tuple` land here — and so does a
        // `CustomReflectable`'s mirror, which carries *no* display style at all
        // unless it names one, which is why this asks about children rather
        // than style. A value with nothing to show is a leaf, not an empty
        // branch: that keeps `UUID` (no reflected children) a leaf rendering
        // its uuid string.
        //
        // A plain `default` rather than `@unknown default` because newer
        // toolchains add styles (`.foreignReference`, for C++ interop types) and
        // naming them here would stop this file compiling on the older ones the
        // package otherwise supports. `.optional` never reaches this point.
        default:
            return mirror.children.isEmpty ? .value : .structure
        }
    }

    /// Foundation value types whose reflected internals are noise in place of
    /// the value: `timeIntervalSinceReferenceDate`, `_url`, a byte buffer,
    /// `_mantissa`.
    ///
    /// Compared by metatype rather than `is`, because a dynamic cast from `Any`
    /// implicitly unwraps optionals and matches across optionality — the trap
    /// that made the previous release's type-glyph table return wrong answers.
    static func isOpaqueValue(_ object: Any) -> Bool {
        let type = type(of: object)
        return type == Date.self || type == URL.self || type == Data.self || type == Decimal.self
    }

    static func typeName(of object: Any) -> String {
        String(describing: type(of: object))
    }

    static func displayValue(of object: Any, kind: Kind, childCount: Int) -> String {
        switch kind {
        case .value:
            switch object {
            case let convertible as CustomStringConvertible:
                return convertible.description
            case let convertible as CustomDebugStringConvertible:
                return convertible.debugDescription
            default:
                return String(describing: object)
            }

        case .enumeration:
            return String(describing: object)

        case .structure:
            // A type that writes its own `description` is stating how it wants
            // to read; honour it, and let the node still expand to its
            // properties. Without a conformance there is nothing better than the
            // count — `String(describing:)` would dump the whole value onto one
            // line.
            return (object as? CustomStringConvertible)?.description ?? "\(childCount)"

        case .collection, .dictionary:
            // Never the type's own description here: every standard collection
            // conforms, and would dump its entire contents into one row.
            return "\(childCount)"
        }
    }

    /// Joins a path component onto a parent path, without doubling the separator
    /// for components that carry their own (`[0]`, `.1`).
    static func childPath(_ parent: String, component: String) -> String {
        component.hasPrefix("[") || component.hasPrefix(".")
            ? parent + component
            : parent + "." + component
    }
}
