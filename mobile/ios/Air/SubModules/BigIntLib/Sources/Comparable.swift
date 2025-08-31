//
//  Comparable.swift
//  BigInt
//
//  Created by Károly Lőrentey on 2016-01-03.
//  Copyright © 2016-2017 Károly Lőrentey.
//

#if canImport(Foundation)
import Foundation
#endif

extension BigUInt: Comparable {
    #if !canImport(Foundation)
    public enum ComparisonResult: Sendable, Comparable, Hashable {
        case orderedDescending
        case orderedSame
        case orderedAscending
    }
    #endif

    //MARK: Comparison
    
    /// Compare `a` to `b` and return an `NSComparisonResult` indicating their order.
    ///
    /// - Complexity: O(count)
    public static func compare(_ a: BigUInt, _ b: BigUInt) -> ComparisonResult {
        let aCount = a.count
        if aCount != b.count { return a.count > b.count ? .orderedDescending : .orderedAscending }
        var i = aCount - 1
        while i >= 0 {
            let ad = a[i]
            let bd = b[i]
            if ad != bd { return ad > bd ? .orderedDescending : .orderedAscending }
            i -= 1
        }
        return .orderedSame
    }

    /// Return true iff `a` is equal to `b`.
    ///
    /// - Complexity: O(count)
    public static func ==(a: BigUInt, b: BigUInt) -> Bool {
        return BigUInt.compare(a, b) == .orderedSame
    }

    /// Return true iff `a` is less than `b`.
    ///
    /// - Complexity: O(count)
    public static func <(a: BigUInt, b: BigUInt) -> Bool {
        return BigUInt.compare(a, b) == .orderedAscending
    }
}

extension BigInt: Comparable {
    /// Return true iff `a` is equal to `b`.
    public static func ==(a: BigInt, b: BigInt) -> Bool {
        return a.sign == b.sign && a.magnitude == b.magnitude
    }

    /// Return true iff `a` is less than `b`.
    public static func <(a: BigInt, b: BigInt) -> Bool {
        switch (a.sign, b.sign) {
        case (.plus, .plus):
            return a.magnitude < b.magnitude
        case (.plus, .minus):
            return false
        case (.minus, .plus):
            return true
        case (.minus, .minus):
            return a.magnitude > b.magnitude
        }
    }
}


