import SwiftUI
import UIComponents
import WalletContext

enum AssetInfoExpansion {
    static let collapsedHeight = CGFloat(64)
    static let animationDuration = TimeInterval(0.45)
    static let crossfadeDuration = TimeInterval(0.2)

    @MainActor
    static func animator(from startHeight: CGFloat, to targetHeight: CGFloat) -> ValueAnimator {
        ValueAnimator(startValue: startHeight, endValue: targetHeight,
                      duration: animationDuration, dampingRatio: 0.93)
    }
}

struct AssetInfoExpandableDescription: View {
    let text: String
    let color: Color
    let expansionProgress: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            AssetInfoDescriptionText(text: text, color: color, lineLimit: nil)
                .opacity(expansionProgress)
            AssetInfoDescriptionText(text: text, color: color, lineLimit: 1)
                .padding(.trailing, 24)
                .opacity(1 - expansionProgress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct AssetInfoExpansionChevron: View {
    let expansionProgress: CGFloat
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Image(systemName: "chevron.down")
            .textStyle(.badgeBold, content: .technical)
            .foregroundStyle(Color.air.primaryLabel.opacity(0.3))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees((layoutDirection == .leftToRight ? -180 : 180) * Double(expansionProgress)))
            .padding(.top, 20 - 11 * expansionProgress)
            .padding(.trailing, 16)
    }
}
