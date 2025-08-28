
import Foundation

/// Linear interpolation.
///
/// - Parameters:
///     - from: value at 0
///     - to: value at 1
///     - progress: interpolates beyond 0...1
public func interpolate(from: Double, to: Double, progress: Double) -> Double {
    from * (1 - progress) + to * progress
}

/// Clamps between min and max value
///
/// - Parameters:
///     - min: lowest possible value
///     - max: highest possoble value
public func clamp(_ value: Double, min: Double, max: Double) -> Double {
    Swift.min(max, Swift.max(min, value))
}

/// Clamps between min and max value
///
/// - Parameters:
///     - min: lowest possible value
///     - max: highest possoble value
public func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(range.upperBound, Swift.max(range.lowerBound, value))
}


public func interpolate(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
    from * (1 - progress) + to * progress
}

public func interpolate(from: CGRect, to: CGRect, progress: CGFloat) -> CGRect {
    CGRect(
        x: interpolate(from: from.origin.x, to: to.origin.x, progress: progress),
        y: interpolate(from: from.origin.y, to: to.origin.y, progress: progress),
        width: interpolate(from: from.width, to: to.width, progress: progress),
        height: interpolate(from: from.height, to: to.height, progress: progress)
    )
}
