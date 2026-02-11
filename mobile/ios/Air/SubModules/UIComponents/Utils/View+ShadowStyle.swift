import SwiftUI

public struct ViewShadowStyle {
    public let color: Color
    public let blurRadius: CGFloat
    public let offset: CGVector
}

extension ViewShadowStyle {
    public static let light = ViewShadowStyle(color: .black.opacity(0.06), blurRadius: 8, offset: CGVector(dx: 0, dy: 1.5))

    //  .black.opacity(0.45), radius: 16, x: 0, y: 0)
    public static let medium = ViewShadowStyle(color: .black.opacity(0.45), blurRadius: 16, offset: .zero)
}

extension View {
    public func shadow(style: ViewShadowStyle) -> some View {
        shadow(color: style.color, radius: style.blurRadius, x: style.offset.dx, y: style.offset.dy)
    }
}
