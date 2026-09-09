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
    ///   A `nil` becomes a leaf rendering `"nil"`. One consequence worth knowing:
    ///   ``PropertyNode/typeName`` reports `Optional<Int>` for a `nil` and `Int`
    ///   for a present value, so it does not identify optionality consistently.
    /// - **Inherited properties appear.** `Mirror.children` stops at the type
    ///   itself, so a class's inherited stored properties are collected from its
    ///   ancestors too — without this a subclass declaring no stored properties
    ///   of its own would look like a leaf.
    /// - **Collections are indexed** `[0]`, `[1]`, … rather than reflected as
    ///   `Array`'s internals. Sets are ordered by their rendered elements, since
    ///   set order is otherwise not defined between runs.
    /// - **Dictionaries are keyed and ordered by key**, for any key type — not
    ///   just `String`.
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
    ///   - maxDepth: How many levels below the root to expand; values below zero
    ///     are treated as zero. A node at the limit keeps its
    ///     ``PropertyNode/kind`` and child count but reports
    ///     ``PropertyNode/isTruncated``. The limit is what stops a reference
    ///     cycle — two objects pointing at each other — from recursing until the
    ///     stack is exhausted.
    ///
    /// - Note: Generic rather than taking `Any`, so that reflecting an optional
    ///   is warning-free at the call site and keeps its static type — the same
    ///   reason `String(describing:)` is generic.
    init<Subject>(reflecting object: Subject, named: String, maxDepth: Int = 16) {
        self = PropertyNode.node(
            reflecting: object,
            name: named,
            path: named,
            depth: 0,
            maxDepth: max(0, maxDepth)
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

        let members = members(of: mirror, subject: object)
        let kind = kind(of: object, mirror: mirror, memberCount: members.count)
        let isTruncated = kind != .value && !members.isEmpty && depth >= maxDepth
        let children: [PropertyNode]? = (kind == .value || depth >= maxDepth)
            ? nil
            : childNodes(members: members, mirror: mirror, kind: kind, path: path, depth: depth, maxDepth: maxDepth)

        return PropertyNode(
            id: path,
            name: name,
            value: object,
            typeName: typeName(of: object),
            displayValue: displayValue(of: object, kind: kind, memberCount: members.count),
            kind: kind,
            children: children,
            isTruncated: isTruncated
        )
    }

    /// The value's reflected members, including those it inherited.
    ///
    /// `Mirror.children` stops at the type itself, so a class's **inherited**
    /// stored properties hang off its `superclassMirror` and would otherwise
    /// vanish from the tree — and a subclass declaring no stored properties of
    /// its own would be classified as a leaf, hiding everything it holds. The
    /// ancestor chain is walked root-most first, so a subclass's own properties
    /// read last. For anything that is not a class this is exactly
    /// `mirror.children`, since `superclassMirror` is then `nil`.
    ///
    /// Ancestors are **not** walked for a `CustomReflectable`: such a type has
    /// stated exactly what it wants shown, and adding its ancestors' properties
    /// would put back whatever it chose to hide — which is the entire purpose of
    /// ``SelectivelyReflectable``.
    static func members(of mirror: Mirror, subject: Any) -> [Mirror.Child] {
        guard !(subject is CustomReflectable) else { return Array(mirror.children) }

        var chain: [Mirror] = []
        var ancestor: Mirror? = mirror
        while let current = ancestor {
            chain.append(current)
            ancestor = current.superclassMirror
        }
        return chain.reversed().flatMap { Array($0.children) }
    }

    static func childNodes(
        members: [Mirror.Child],
        mirror: Mirror,
        kind: Kind,
        path: String,
        depth: Int,
        maxDepth: Int
    ) -> [PropertyNode] {
        let entries = childEntries(members: members, mirror: mirror, kind: kind)

        // Components are made unique *before* any recursion, so no two nodes in
        // a tree can share an `id`. Two dictionary keys that render alike, or a
        // subclass property shadowing an inherited one, would otherwise collide
        // and make a SwiftUI outline conflate their rows. Each component already
        // carries its own separator, so appending is all that is left to do.
        return zip(entries, disambiguated(entries.map(\.component))).map { entry, component in
            node(
                reflecting: entry.value,
                name: entry.name,
                path: path + component,
                depth: depth + 1,
                maxDepth: maxDepth
            )
        }
    }

    /// `name` is what a reader sees; `component` is what the path is built from,
    /// escaped and carrying its own leading separator.
    typealias ChildEntry = (name: String, component: String, value: Any)

    static func childEntries(members: [Mirror.Child], mirror: Mirror, kind: Kind) -> [ChildEntry] {
        switch kind {
        case .value:
            return []

        case .collection:
            var elements = members.map(\.value)
            if mirror.displayStyle == .set {
                // A `Set` has no order of its own, so without this the same data
                // would produce a differently-ordered tree on each launch.
                // Elements that render alike still tie, and ties are ordered
                // arbitrarily — see PT-2 in docs/Tech-Debt.md.
                elements.sort { String(describing: $0) < String(describing: $1) }
            }
            return elements.enumerated().map { index, element in
                (name: "[\(index)]", component: "[\(index)]", value: element)
            }   // an index is digits, so it needs no escaping

        case .dictionary:
            // Each child of a dictionary's mirror is a `(key:value:)` tuple, so
            // keys of any type are reachable — not only `String`.
            return members
                .compactMap { entry -> (key: String, value: Any)? in
                    let pair = Mirror(reflecting: entry.value).children
                    guard let key = pair.first(where: { $0.label == "key" })?.value,
                          let value = pair.first(where: { $0.label == "value" })?.value
                    else { return nil }
                    return (String(describing: key), value)
                }
                .sorted { $0.key < $1.key }
                .map { (name: $0.key, component: "[\(escaped($0.key))]", value: $0.value) }

        case .enumeration:
            // A case with associated values reflects as one child: its label is
            // the case name, its value the payload. Flatten a payload tuple so
            // `circle(radius:)` yields a `radius` child rather than a `circle`
            // level wrapping one.
            guard let payload = members.first else { return [] }
            let payloadMirror = Mirror(reflecting: payload.value)
            if payloadMirror.displayStyle == .tuple {
                return payloadMirror.children.enumerated().map { index, associated in
                    let name = associated.label ?? "[\(index)]"
                    return (name: name, component: pathComponent(for: name), value: associated.value)
                }
            }
            let name = payload.label ?? "value"
            return [(name: name, component: pathComponent(for: name), value: payload.value)]

        case .structure:
            return members.enumerated().map { index, property in
                let name = property.label ?? "[\(index)]"
                return (name: name, component: pathComponent(for: name), value: property.value)
            }
        }
    }

    /// Appends `#2`, `#3`, … to repeated components, so a node's path is unique
    /// among its siblings and therefore unique in the tree.
    static func disambiguated(_ components: [String]) -> [String] {
        var occurrences: [String: Int] = [:]
        return components.map { component in
            let occurrence = (occurrences[component] ?? 0) + 1
            occurrences[component] = occurrence
            return occurrence == 1 ? component : "\(component)#\(occurrence)"
        }
    }
}

// MARK: - Classification and rendering

private extension PropertyNode {

    static func kind(of object: Any, mirror: Mirror, memberCount: Int) -> Kind {
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
        // unless it names one, which is why this asks about members rather than
        // style. A value with nothing to show is a leaf, not an empty branch:
        // that keeps `UUID` (no reflected members) a leaf rendering its uuid
        // string.
        //
        // A plain `default` rather than `@unknown default` because newer
        // toolchains add styles (`.foreignReference`, for C++ interop types) and
        // naming them here would stop this file compiling on the older ones the
        // package otherwise supports. `.optional` never reaches this point.
        default:
            return memberCount == 0 ? .value : .structure
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

    static func displayValue(of object: Any, kind: Kind, memberCount: Int) -> String {
        switch kind {
        case .value:
            switch object {
            case let data as Data:
                return description(of: data)
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
            return (object as? CustomStringConvertible)?.description ?? "\(memberCount)"

        case .collection, .dictionary:
            // Never the type's own description here: every standard collection
            // conforms, and would dump its entire contents into one row.
            return "\(memberCount)"
        }
    }

    /// `Data`'s own description is its length alone — `"3 bytes"` — which tells a
    /// reader nothing about the payload and makes two different blobs of equal
    /// size render, and so compare, identically. A short hex preview restores
    /// both the information and the distinction.
    ///
    /// Hex is built by hand rather than with `String(format:)` to keep this
    /// stdlib-only, and so identical on Linux.
    static func description(of data: Data) -> String {
        guard !data.isEmpty else { return "0 bytes" }

        let previewLength = 16
        let preview = data.prefix(previewLength)
            .map { byte in
                let hex = String(byte, radix: 16)
                return hex.count == 1 ? "0" + hex : hex
            }
            .joined(separator: " ")
        let ellipsis = data.count > previewLength ? " …" : ""
        return "\(data.count) bytes: \(preview)\(ellipsis)"
    }

    /// The path component for a named child — a property, an enum's associated
    /// value, a tuple element — separator included.
    ///
    /// `Mirror` spells an unlabelled tuple element `.0`, and that leading dot is
    /// the separator rather than part of the name, so it is dropped before
    /// escaping; otherwise `root.0` would come out `root.\.0`.
    static func pathComponent(for name: String) -> String {
        let bare = name.hasPrefix(".") ? String(name.dropFirst()) : name
        return "." + escaped(bare)
    }

    /// Escapes the four characters the path grammar reserves, so that a name can
    /// never be mistaken for structure.
    ///
    /// Without this the grammar is ambiguous in two ways, both found in review.
    /// A child named `a.b` encodes exactly like a child `a` holding a child `b`.
    /// And `#`, which marks a disambiguated repeat, could already appear in a
    /// name: siblings `a`, `a`, `a#2` would have produced `a#2` twice — the
    /// disambiguator colliding with a literal sibling.
    ///
    /// Ordinary names contain none of these, so ordinary paths are unchanged.
    static func escaped(_ name: String) -> String {
        var escaped = ""
        for character in name {
            if character == "\\" || character == "." || character == "[" || character == "]" || character == "#" {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
