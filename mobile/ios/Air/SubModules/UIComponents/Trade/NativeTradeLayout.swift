import UIKit

/// Footer measurement and placement happen together, with no geometry-to-state feedback pass.
public struct NativeTradeLayout {
    public let scroll: CGRect
    public let card: CGRect
    public let method: CGRect
    public let controls: CGRect
    public let contentHeight: CGFloat
    public let keypadHeight: CGFloat
    public let maximumAmountHeight: CGFloat
    public let amountTop: CGFloat
    public let footerTop: CGFloat

    public init(size: CGSize, bottomSafeArea: CGFloat, navigationBarSpace: CGFloat,
         feeHeight: CGFloat, impactHeight: CGFloat, hintHeight: CGFloat,
         amountSupplementHeight: CGFloat = 0) {
        let bottomInset = max(32, bottomSafeArea)
        keypadHeight = min(256, max(176, size.height - (256 + navigationBarSpace + 84) - 88 - bottomInset))
        let controlsHeight = 88 + keypadHeight + bottomInset
        let available = max(0, size.height - controlsHeight)
        let preferredCardHeight = max(136 + navigationBarSpace, available - 84)
        let heights = [feeHeight, impactHeight, hintHeight].filter { $0 > 0 }
        let footerHeight = heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * 8
        let hasNotice = impactHeight > 0 || hintHeight > 0
        let compact = preferredCardHeight - footerHeight - (hasNotice ? 16 : 22) < 240
        let bottomPadding: CGFloat = hasNotice ? 16 : compact ? 12 : 22
        maximumAmountHeight = compact ? 64 : 86
        let amountHeight = 26 + maximumAmountHeight + amountSupplementHeight
        let minimumTop = max(16, navigationBarSpace)
        let cardHeight = max(preferredCardHeight, minimumTop + amountHeight + 18 + footerHeight + bottomPadding)
        amountTop = max(minimumTop, min(54 + navigationBarSpace, cardHeight - amountHeight - 18 - footerHeight - bottomPadding))
        footerTop = cardHeight - bottomPadding - footerHeight
        scroll = CGRect(x: 0, y: 0, width: size.width, height: available)
        card = CGRect(x: 0, y: 0, width: size.width, height: cardHeight)
        method = CGRect(x: 16, y: cardHeight + 16, width: max(0, size.width - 32), height: 52)
        controls = CGRect(x: 0, y: available, width: size.width, height: controlsHeight)
        contentHeight = max(available, cardHeight + 84)
    }
}
