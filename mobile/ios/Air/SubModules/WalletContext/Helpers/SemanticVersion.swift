
import Foundation

public struct SemanticVersion: Equatable, Hashable, Comparable {
    
    public var major: Int
    public var minor: Int
    public var patch: Int
    
    public init(_ string: String) {
        let parts = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", omittingEmptySubsequences: true)
        var _0 = 0
        var _1 = 0
        var _2 = 0
        if parts.count > 0, let v = Int(parts[0]) {
            _0 = v
        }
        if parts.count > 1, let v = Int(parts[1]) {
            _1 = v
        }
        if parts.count > 2, let v = Int(parts[2]) {
            _2 = v
        }
        self.major = _0
        self.minor = _1
        self.patch = _2
    }
    
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}
