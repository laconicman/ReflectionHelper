import Foundation

/// Протокол, позволяющий указать, какие из свойств объекта отображать в `Mirror`
/// Можно подписывать под него конкретные типы или же другие протоколы используя protocol Inheritance.
public protocol SelectivelyReflectable: CustomReflectable {
    /// Список свойств объекта, которые должны отображаться в `Mirror`
    /// Нужен в том числе для отображения вычисляемых свойств, потому что они по умолчанию не отражаются.
    /// См. также макрос для отображения всех свойств: [KeyPathIterable](https://github.com/Ryu0118/KeyPathIterable)
    static var selectedKeyPathsToMirror: [(String, PartialKeyPath<Self>)] { get }
}

public extension SelectivelyReflectable {
    var customMirror: Mirror {
        Mirror(self, children: Self.selectedKeyPathsToMirror.map{ Mirror.Child(label: $0, value: self[keyPath: $1]) })
    }
}

/// Структура данных об объекте и иерархии его содержимого
public struct PropertyNode: Identifiable {
    public init(id: UUID = UUID(), name: String, value: Any, children: [PropertyNode]? = nil) {
        self.id = UUID()
        self.name = name
        self.value = value
        if let children, !children.isEmpty {
            self.children = children
        } else {
            self.children = nil
        }
    }

    public let id: UUID
    public let name: String
    public let value: Any
    public let children: [PropertyNode]?

    public var hasChildren: Bool {
        children?.isEmpty == false
    }
    
    public func replacing(children: [PropertyNode]?) -> PropertyNode {
        .init(id: id, name: name, value: value, children: children)
    }
}

// В данном случае для conformance `Hashable` и `Equatable` оптимально использовать только `id`.
extension PropertyNode: Hashable {
    public static func == (lhs: PropertyNode, rhs: PropertyNode) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// TODO: Добавить инициализатор с лимитом уровней вложенности, с фильтром (см. наработку `createFilteredPropertyTree()`).
/// Инициализатор для reflection `Mirror`
public extension PropertyNode {
    init(reflecting object: Any, named: String) {
        self = .init(name: named,
                     value: object,
                     children: Mirror(reflecting: object).children.map{ .init(reflecting: $0.value, named: $0.label ?? "") })
    }

    // @Sendable автоматически, потому что pure. К тому же ещё и `static`. См. SE-0418.
    // TODO: Хорошо бы переделать в инициализатор, но нужно продумать сигнатуру. Можно сократить.

    /// Создаёт очищенный и отфоматированный `PropertyNode` для отображения в иерархическом списке
    /// - Parameters:
    ///   - object: объект, для которого будет сформировано дерево
    ///   - named: Имя переданного `object`
    /// - Returns: иерархическое дерево объектов для `object`
    static func createPropertyTree(reflecting object: Any, named: String) -> PropertyNode {
        let mirror = Mirror(reflecting: object)
        var childNodes: [PropertyNode] = []
        switch object {
        case let array as [Any]:
            childNodes = array.enumerated().map { index, item in
                createPropertyTree(reflecting: item, named: "[\(index)]")
            }
        case let dictionary as [String: Any]:
            childNodes = dictionary.sorted(by: { $0.key < $1.key }).map { key, value in
                createPropertyTree(reflecting: value, named: key)
            }
        default:
            if mirror.children.count == 1, let firstChild = mirror.children.first, firstChild.label == "some" {
                return createPropertyTree(reflecting: firstChild.value, named: named)
            }
            childNodes = mirror.children.map { child in
                createPropertyTree(reflecting: child.value, named: child.label ?? "")
            }
        }
        return PropertyNode(name: named, value: object, children: childNodes.isEmpty ? nil : childNodes)
    }

    // Возможно, стоит оформить в функцию, возможно, вынести из модельного слоя, но не факт.
    var displayValue: String {
        if hasChildren, let children {
            "\(children.count)"
        } else {
            switch value {
            case let stringConvertible as CustomStringConvertible:
                stringConvertible.description
            case let debugStringConvertible as CustomDebugStringConvertible:
                debugStringConvertible.debugDescription
// TODO: доделать, чтоб различать объекты c наборами свойств от dictionaries (`switch (value, hasChildren)`).
// Сейчас словарь и структрура неразличимы при использовании `createPropertyTree()`.
//            case let codable as Codable:
//                // Special handling for Codable types
//                "Codable: \(String(describing: type(of: codable)))"
//            case let collection as any Collection:
//                "Collection (\(collection.count) items)"
            default:
                String(describing: value)
            }
        }
    }

}

extension PropertyNode: CustomStringConvertible {
    public var description: String {
        "\(name) \(pictogram(for: value))"
    }
}
// MARK: - далее идёт код, подлежаший рефакторингу
/*
public extension PropertyNode {
    // Можно отрефакторить по аналогии с `PropertyNode.init()`
    static func createFilteredPropertyTree(
        from object: Any,
        name: String,
        excludeTypes: [String] = [] // i.e. = ["Optional"]
    ) -> PropertyNode {
        let mirror = Mirror(reflecting: object)
        let typeName = String(describing: type(of: object))

        if excludeTypes.contains(where: { typeName.contains($0) }) {
            return PropertyNode(name: name, value: object, children: nil)
        }

        if mirror.children.isEmpty || isPrimitiveType(object) {
            return PropertyNode(name: name, value: object, children: nil)
        } else {
            let childNodes = mirror.children.compactMap { child -> PropertyNode? in
                let childName = child.label ?? "unknown"
                return createFilteredPropertyTree(
                    from: child.value,
                    name: childName,
                    excludeTypes: excludeTypes
                )
            }
            return PropertyNode(name: name, value: object, children: childNodes.isEmpty ? nil : childNodes)
        }
    }

}

// @Sendable – автоматически, глобальная. См. SE-0418.
private func isPrimitiveType(_ value: Any) -> Bool {
    // Синтаксис наивный
    value is String || value is Int || value is Double ||
    value is Float || value is Bool || value is Character
}
*/

func pictogram(for value: Any) -> String {
    // Implementation may seem repetitive but it more efficient than trying to mess with metatypes or `Mirror`.
    switch value {
    case is String: "🅂"
    case is Int: "🄸"
    case is Date: "🄳🅃"
    case is Double: "🄳"
    case is Float: "🄵"
    case is Bool: "🄱"
    case is Character: "🄲"
    case is [Any]: "🅰︎"
    case is Set<AnyHashable>: "🆂"
    case is [AnyHashable: Any]: "🅳🅸"
    case is String?: "🅂?"
    case is Int?: "🄸?"
    case is Date?: "🄳🅃?"
    case is Double?: "🄳?"
    case is Float?: "🄵?"
    case is Bool?: "🄱?"
    case is Character?: "🄲?"
    case is [Any]?: "🅰︎?"
    case is Set<AnyHashable>?: "🆂?"
    case is [AnyHashable: Any]?: "🅳🅸?" 
    default: "" // or `String(describing: type(of: object))`
    }
}

//func pictogram<T>(for value: T) -> String {
//    let isOptional = T.self is ExpressibleByNilLiteral.Type // is nor reliable
//    return pictogramForUnderlyingType(of: value) + (isOptional ? "?" : "")
//}
//
//func pictogramForUnderlyingType(of value: Any) -> String {
//    switch value {
//    case is String?:             "🅂"
//    case is Int?:                "🄸"
//    case is Date?:               "🄳🅃"
//    case is Double?:             "🄳"
//    case is Float?:              "🄵"
//    case is Bool?:               "🄱"
//    case is Character?:          "🄲"
//    case is [Any]?:              "🅰︎"
//    case is Set<AnyHashable>?:   "🆂"
//    case is [AnyHashable: Any]?: "🅳🅸"
//    default:                     ""
//    }
//}

//func pictogram<T>(for value: T) -> String {
//    return pictogramForType(T.self, isOptional: T.self is ExpressibleByNilLiteral.Type)
//}
//
//private func pictogramForType(_ type: Any.Type, isOptional: Bool) -> String {
//    let suffix = isOptional ? "?" : ""
//    
//    // Use a more systematic approach with metatype checking
//    return switch type {
//    case is String.Type, is String?.Type: "🅂" + suffix
//    case is Int.Type, is Int?.Type: "🄸" + suffix
//    case is Date.Type, is Date?.Type: "🄳🅃" + suffix
//    case is Double.Type, is Double?.Type: "🄳" + suffix
//    case is Float.Type, is Float?.Type: "🄵" + suffix
//    case is Bool.Type, is Bool?.Type: "🄱" + suffix
//    case is Character.Type, is Character?.Type: "🄲" + suffix
//    case is Array<Any>.Type, is Array<Any>?.Type: "🅰︎" + suffix
//    case is Set<AnyHashable>.Type, is Set<AnyHashable>?.Type: "🆂" + suffix
//    case is Dictionary<AnyHashable, Any>.Type, is Dictionary<AnyHashable, Any>?.Type: "🅳🅸" + suffix
//    default: ""
//    }
//}
