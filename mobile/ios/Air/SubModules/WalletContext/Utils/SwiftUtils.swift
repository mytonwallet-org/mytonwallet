
import Foundation
import OrderedCollections

public extension Array {
    func dictionaryByKey<Key: Hashable>(_ keyPath: KeyPath<Element, Key>) -> [Key: Element] {
        var dict: [Key: Element] = [:]
        for value in self {
            dict[value[keyPath: keyPath]] = value
        }
        return dict
    }

    func orderedDictionaryByKey<Key: Hashable>(_ keyPath: KeyPath<Element, Key>) -> OrderedDictionary<Key, Element> {
        var dict: OrderedDictionary<Key, Element> = [:]
        for value in self {
            dict[value[keyPath: keyPath]] = value
        }
        return dict
    }

    func first<T: Equatable>(whereEqual keyPath: KeyPath<Element, T>, _ value: T) -> Element? {
        first { $0[keyPath: keyPath] == value }
    }
}

public extension Sequence {
    func any(_ isTrue: (Element) -> Bool) -> Bool {
        for item in self {
            if isTrue(item) {
                return true
            }
        }
        return false
    }

    func any(_ isTrue: (Element) -> Bool?) -> Bool {
        for item in self {
            if isTrue(item) == true {
                return true
            }
        }
        return false
    }
}

public func += <T>(array: inout [T], element: T) {
    array.append(element)
}

public extension Array where Element: Identifiable {
    func first(id: Element.ID) -> Element? {
        first { $0.id == id }
    }
}

public func unique<T: Hashable>(_ array: [T]) -> [T] {
    Array(OrderedSet(array))
}

@inlinable
public func configured<T: AnyObject, E>(object: T, closure: (_ object: T) throws(E) -> Void) throws(E) -> T {
    try closure(object)
    return object
}

@inlinable
public func configure<T: AnyObject, E>(object: T, closure: (_ object: T) throws(E) -> Void) throws(E) {
    try closure(object)
}

@inlinable
public func mutate<T: ~Copyable, E>(value: consuming T, mutation: (inout T) throws(E) -> Void) throws(E) -> T {
    try mutation(&value)
    return value
}

@available(*, deprecated, message: "use configured(object:) for reference types instead")
public func mutate<T: AnyObject, E>(value: consuming T, mutation: (inout T) throws(E) -> Void) throws(E) -> T {
    try mutation(&value)
    return value
}

/// Exclude property from Equality comparison and hashValue.
@propertyWrapper
public struct HashableExcluded<T>: Equatable {
    public var wrappedValue: T

    public init(wrappedValue: T) {
        self.wrappedValue = wrappedValue
    }

    public init(_ wrappedValue: T) {
        self.init(wrappedValue: wrappedValue)
    }

    /// always true
    public static func == (_: Self, _: Self) -> Bool { true }
}

extension HashableExcluded: Hashable {
    /// Empty Implementation
    public func hash(into _: inout Hasher) {}
}

extension HashableExcluded: BitwiseCopyable where T: BitwiseCopyable {}

extension HashableExcluded: Sendable where T: Sendable {}

extension HashableExcluded: CustomStringConvertible where T: CustomStringConvertible {
    public var description: String { String(describing: wrappedValue) }
}

extension HashableExcluded: CustomDebugStringConvertible where T: CustomDebugStringConvertible {
    public var debugDescription: String { String(reflecting: wrappedValue) }
}
