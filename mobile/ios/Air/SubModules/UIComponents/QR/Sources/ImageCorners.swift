import UIKit

public enum ImageCorner: Equatable {
    case Corner(CGFloat)
    case Tail(CGFloat, UIImage)
    
    public var extendedInsets: CGSize {
        switch self {
            case .Tail:
                return CGSize(width: 4.0, height: 0.0)
            default:
                return CGSize()
        }
    }
    
    public var withoutTail: ImageCorner {
        switch self {
            case .Corner:
                return self
            case let .Tail(radius, _):
                return .Corner(radius)
        }
    }
    
    public var radius: CGFloat {
        switch self {
            case let .Corner(radius):
                return radius
            case let .Tail(radius, _):
                return radius
        }
    }
}

public func ==(lhs: ImageCorner, rhs: ImageCorner) -> Bool {
    switch lhs {
        case let .Corner(lhsRadius):
            switch rhs {
                case let .Corner(rhsRadius) where abs(lhsRadius - rhsRadius) < CGFloat.ulpOfOne:
                    return true
                default:
                    return false
            }
        case let .Tail(lhsRadius, lhsImage):
            if case let .Tail(rhsRadius, rhsImage) = rhs, lhsRadius.isEqual(to: rhsRadius), lhsImage === rhsImage {
                return true
            } else {
                return false
            }
    }
}

public struct ImageCorners: Equatable {
    public let topLeft: ImageCorner
    public let topRight: ImageCorner
    public let bottomLeft: ImageCorner
    public let bottomRight: ImageCorner
    
    public var isEmpty: Bool {
        if self.topLeft != .Corner(0.0) {
            return false
        }
        if self.topRight != .Corner(0.0) {
            return false
        }
        if self.bottomLeft != .Corner(0.0) {
            return false
        }
        if self.bottomRight != .Corner(0.0) {
            return false
        }
        return true
    }
    
    public init(radius: CGFloat) {
        self.topLeft = .Corner(radius)
        self.topRight = .Corner(radius)
        self.bottomLeft = .Corner(radius)
        self.bottomRight = .Corner(radius)
    }
    
    public init(topLeft: ImageCorner, topRight: ImageCorner, bottomLeft: ImageCorner, bottomRight: ImageCorner) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
    
    public init() {
        self.init(topLeft: .Corner(0.0), topRight: .Corner(0.0), bottomLeft: .Corner(0.0), bottomRight: .Corner(0.0))
    }
    
    public var extendedEdges: UIEdgeInsets {
        let left = self.bottomLeft.extendedInsets.width
        let right = self.bottomRight.extendedInsets.width
        
        return UIEdgeInsets(top: 0.0, left: left, bottom: 0.0, right: right)
    }
    
    public func withRemovedTails() -> ImageCorners {
        return ImageCorners(topLeft: self.topLeft.withoutTail, topRight: self.topRight.withoutTail, bottomLeft: self.bottomLeft.withoutTail, bottomRight: self.bottomRight.withoutTail)
    }
}
