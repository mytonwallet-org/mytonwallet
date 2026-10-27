import SwiftUI

public struct WarningBackground: View {
    public var color: Color

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(color.opacity(0.12))
            .overlay {
                WarningSideBars()
                    .fill(color)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct WarningSideBars: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(26, rect.height / 2, rect.width / 2)
        let barWidth = min(4, radius)
        let outer = RoundedRectangle(cornerRadius: radius, style: .continuous)
            .path(in: rect)
        let inner = RoundedRectangle(
            cornerSize: CGSize(width: radius - barWidth, height: radius),
            style: .continuous
        )
        .path(in: rect.insetBy(dx: barWidth, dy: 0))
        // Resolve the shared horizontal edges before rendering to avoid seams while scrolling.
        return Path(outer.cgPath.subtracting(inner.cgPath))
    }
}
