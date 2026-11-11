import UIKit
import WalletContext

@MainActor
public enum WActionButtonIcon {
    // Symbol canvases include transparent alignment margins around the visible glyphs.
    public static let fund = symbol("arrow.down", pointSize: 22.64, fitting: CGSize(width: 22, height: 23.5))
    public static let send = symbol("arrow.up", pointSize: 22.64, fitting: CGSize(width: 22, height: 23.5))
    public static let trade = centered(.airBundle("ActionButtonTrade"))
    public static let earn = centered(.airBundle("ActionButtonEarn"))

    private static func symbol(_ name: String, pointSize: CGFloat, fitting size: CGSize) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(font: .roundedNative(ofSize: pointSize, weight: .semibold))
        let image = UIImage(systemName: name, withConfiguration: configuration)
        return image.map { centered($0, fitting: size) }
    }

    private static func centered(_ image: UIImage, fitting bounds: CGSize? = nil) -> UIImage {
        let size = WScalableButton.preferredImageSize
        let scale = bounds.map { min($0.width / image.size.width, $0.height / image.size.height) } ?? 1
        let imageSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (size.width - imageSize.width) / 2, y: (size.height - imageSize.height) / 2)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: origin, size: imageSize))
        }.withRenderingMode(.alwaysTemplate)
    }
}
