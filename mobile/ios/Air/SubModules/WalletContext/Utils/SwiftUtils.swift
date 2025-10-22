
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
    func `any`(_ isTrue: (Element) -> Bool) -> Bool {
        for item in self {
            if isTrue(item) {
                return true
            }
        }
        return false
    }

    func `any`(_ isTrue: (Element) -> Bool?) -> Bool {
        for item in self {
            if isTrue(item) == true {
                return true
            }
        }
        return false
    }
}

public func +=<T>(array: inout [T], element: T) {
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
