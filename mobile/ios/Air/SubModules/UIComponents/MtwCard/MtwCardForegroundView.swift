import UIKit
import WalletCore
import WalletContext

public final class MtwCardForegroundView: UIView {
    public enum Style { case centered, balance }
    private let gradient = CAGradientLayer()
    private let style: Style
    private var cachedTextColor: (key: TextColorKey, color: UIColor)?

    private struct TextColorKey: Equatable {
        var bounds: CGRect
        var rect: CGRect
        var scale: CGFloat
    }

    public init(style: Style = .centered) {
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradient.type = .radial
        layer.addSublayer(gradient)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(nft: ApiNft?) {
        let cgColors = Self.colors(for: nft).map(\.cgColor)
        guard gradient.colors as? [CGColor] != cgColors else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = cgColors
        CATransaction.commit()
        cachedTextColor = nil
    }

    /// Paint text with the same gradient as its neighboring icons, preserving color glyphs.
    func textColor(in rect: CGRect, scale: CGFloat) -> UIColor {
        guard let colors = gradient.colors as? [CGColor], let first = colors.first else { return .white }
        if colors.allSatisfy({ $0 == first }) { return UIColor(cgColor: first) }
        guard rect.width > 0, rect.height > 0 else { return .clear }
        let key = TextColorKey(bounds: bounds, rect: rect, scale: scale)
        if let cachedTextColor, cachedTextColor.key == key { return cachedTextColor.color }

        layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            gradient.render(in: context.cgContext)
        }
        let color = UIColor(patternImage: image)
        cachedTextColor = (key, color)
        return color
    }

    static func colors(for nft: ApiNft?) -> [UIColor] {
        switch nft?.metadata?.mtwCardType {
        case .black: [UIColor(hex: "CECECF"), UIColor(hex: "444546")]
        case .platinum: [.white, UIColor(hex: "77777F")]
        case .gold: [UIColor(hex: "4C3403"), UIColor(hex: "B07D1D")]
        case .silver: [UIColor(hex: "272727"), UIColor(hex: "989898")]
        case .standard:
            Array(repeating: nft?.metadata?.mtwCardTextType == .dark ? UIColor(hex: "2F3241") : .white, count: 2)
        case nil: [.white, .white]
        }

    }

    /// Shared by the visible amount and its concealed dust, in the same coordinates.
    static func radialGeometry(in rect: CGRect, style: Style) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: rect.minX + rect.width * (style == .balance ? 0.3 : 0.5), y: rect.midY),
         rect.width * (style == .balance ? 0.6 : 0.475))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let geometry = Self.radialGeometry(in: bounds, style: style)
        let center = CGPoint(x: (geometry.center.x - bounds.minX) / max(1, bounds.width),
                             y: (geometry.center.y - bounds.minY) / max(1, bounds.height))
        gradient.startPoint = center
        gradient.endPoint = CGPoint(x: center.x + geometry.radius / max(1, bounds.width),
                                    y: center.y + geometry.radius / max(1, bounds.height))
        CATransaction.commit()
    }
}
