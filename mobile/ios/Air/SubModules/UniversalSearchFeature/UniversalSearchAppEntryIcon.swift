import UIKit
import WalletContext

@MainActor
enum UniversalSearchAppEntryIcon {
    private static var actionImages: [UniversalSearchWalletAction: UIImage] = [:]

    static func image(for entry: UniversalSearchAppEntry) -> UIImage? {
        guard case .walletAction(let action) = entry.route, action != .swap else {
            return UIImage.airBundle(entry.iconName)
        }
        if let image = actionImages[action] { return image }
        let glyph = UIImage.airBundle(entry.iconName).withTintColor(.white.withAlphaComponent(0.8))
        // Use the wallet action menu's colors and glyphs in the search design's compact square.
        let colors: [UIColor] = switch action {
        case .fund: [UIColor(hex: "#A0DE7E"), UIColor(hex: "#54CB68")]
        case .send: [UIColor(hex: "#72D5FD"), UIColor(hex: "#2A9EF1")]
        case .earn: [UIColor(hex: "#82B1FF"), UIColor(hex: "#665FFF")]
        case .buyWithCard: [UIColor(hex: "#FFC32B"), UIColor(hex: "#FF7F24")]
        case .sell: [UIColor(hex: "#FF885E"), UIColor(hex: "#FF516A")]
        case .scan: [UIColor(hex: "#BDBDBD"), UIColor(hex: "#8E8E8E")]
        case .swap: []
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            let bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: 6.4)
            path.addClip()
            if let gradient = CGGradient(colorsSpace: nil, colors: colors.map(\.cgColor) as CFArray, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 12, y: 0),
                                                     end: CGPoint(x: 12, y: 24), options: [])
            }
            let scale = 15.2 / max(glyph.size.width, glyph.size.height)
            let size = CGSize(width: glyph.size.width * scale, height: glyph.size.height * scale)
            glyph.draw(in: CGRect(x: (24 - size.width) / 2, y: (24 - size.height) / 2,
                                  width: size.width, height: size.height))
        }
        actionImages[action] = image
        return image
    }
}
