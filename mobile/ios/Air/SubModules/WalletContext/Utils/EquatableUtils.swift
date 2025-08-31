//
//  EquatableUtils.swift
//  WalletContext
//
//  Created by Sina on 3/26/24.
//

import Foundation

public protocol WEquatable: Equatable {
    func isChanged(comparing: Self) -> Bool
}

public enum EquatableChange<T: Equatable> {
    case insert(T)
    case delete(T)
    case update(T)
}

public extension Array where Element: WEquatable {
    func diff(new: [Element], section: Int = 0) -> [EquatableChange<IndexPath>] {
        var changes = [EquatableChange<IndexPath>]()
        
        // Find deletions
        for (index, element) in self.enumerated() {
            if !new.contains(element) {
                changes.append(.delete(IndexPath(row: index, section: section)))
            }
        }
        
        // Find insertions and updates
        for (index, element) in new.enumerated() {
            if let oldIndex = self.firstIndex(of: element) {
                if index != oldIndex || element.isChanged(comparing: self[oldIndex]) {
                    // If the element exists in both arrays but has moved or changed, consider it as an update
                    changes.append(.update(IndexPath(row: oldIndex, section: section)))
                }
            } else {
                // If the element exists only in the new array, consider it as an insertion
                changes.append(.insert(IndexPath(row: index, section: section)))
            }
        }
        
        return changes
    }
    func hasChanged(comparing new: [Element]) -> Bool {
        if self.count != new.count {
            return true
        }
        for (index, element) in enumerated() {
            if (new[index].isChanged(comparing: element)) {
                return true
            }
        }
        return false
    }
}
