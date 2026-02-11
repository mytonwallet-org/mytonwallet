extension BidirectionalCollection {
    /// Safely returns an element at the specified index, or `nil` if the index is out of bounds.
    @inlinable
    public subscript(at index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension RangeReplaceableCollection {
    /// Appends an element to the collection only if the element is not `nil`.
    @inlinable
    public mutating func append(ifNotNil element: Self.Element?) {
        if let element {
            append(element)
        }
    }
}

extension Collection {
    /// Applies a given function to the collection and returns the result.
    ///
    /// - Example:
    /// ```swift
    /// let array = [1, 2, 3, 4, 2]
    /// let unique = array.lazy.filter { $0 % 2 == 0 }.apply(Set.init)
    /// ```
    @inlinable @inline(__always)
    public func apply<T>(_ function: (Self) -> T) -> T {
        function(self)
    }
}
