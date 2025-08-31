
import Foundation

public struct NilError: Error, CustomStringConvertible {
    
    public var reason: String?
    
    public init(_ reason: String? = nil) {
        self.reason = reason
    }
    
    public var description: String {
        if let reason {
            "NilError(\(reason))"
        } else {
            "NilError"
        }
    }
}


extension Optional {
    public func orThrow(_ reason: String? = nil) throws(NilError) -> Wrapped {
        if let self { return self }
        throw NilError(reason)
    }
}

public extension String {
    var nilIfEmpty: String? {
        if isEmpty { return nil }
        return self
    }
}

public extension Array {
    var nilIfEmpty: Self? {
        if isEmpty { return nil }
        return self
    }
}

public extension Dictionary {
    var nilIfEmpty: Self? {
        if isEmpty { return nil }
        return self
    }
}

public extension Int {
    var nilIfZero: Self? {
        if self == 0 { return nil }
        return self
    }
}

public extension BigInt {
    var nilIfZero: Self? {
        if self == 0 { return nil }
        return self
    }
}

public extension Double {
    var nilIfZero: Self? {
        if self == 0 { return nil }
        return self
    }
}

public extension CGFloat {
    var nilIfZero: Self? {
        if self == 0 { return nil }
        return self
    }
}

public extension Optional where Wrapped: ExpressibleByIntegerLiteral {
    var orZero: Wrapped { self ?? 0 }
}
