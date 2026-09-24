import Foundation

/// Keeps diffable identifiers native to UIKit, avoiding Swift value boxing and
/// protocol conformance searches when UIKit builds its ordered sets.
public final class NativeIdentifier<Value: Hashable & Sendable>: NSObject, @unchecked Sendable {
    public let value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public override var hash: Int { value.hashValue }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NativeIdentifier<Value> else { return false }
        return value == other.value
    }
}
