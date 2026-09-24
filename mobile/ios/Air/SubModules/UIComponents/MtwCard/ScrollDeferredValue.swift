/// Keeps the last presented value stable while a scroll gesture or its deceleration is active.
public struct ScrollDeferredValue<Value: Equatable> {
    public private(set) var displayed: Value
    public private(set) var latest: Value

    public init(_ value: Value) {
        displayed = value
        latest = value
    }

    @discardableResult
    public mutating func update(_ value: Value, isScrolling: Bool) -> Bool {
        latest = value
        guard !isScrolling, displayed != latest else { return false }
        displayed = latest
        return true
    }
}
