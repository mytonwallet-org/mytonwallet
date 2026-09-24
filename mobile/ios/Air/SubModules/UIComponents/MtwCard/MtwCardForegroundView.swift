import UIKit
import WalletCore
import WalletContext

public final class MtwCardForegroundView: UIView {
    public enum Style { case centered, balance }
    private let gradient = CAGradientLayer()
    private let style: Style

    public init(style: Style = .centered) {
        self.style = style
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        gradient.type = .radial
        layer.addSublayer(gradient)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func configure(nft: ApiNft?) {
        let colors: [UIColor] = switch nft?.metadata?.mtwCardType {
        case .black: [UIColor(hex: "CECECF"), UIColor(hex: "444546")]
        case .platinum: [.white, UIColor(hex: "77777F")]
        case .gold: [UIColor(hex: "4C3403"), UIColor(hex: "B07D1D")]
        case .silver: [UIColor(hex: "272727"), UIColor(hex: "989898")]
        case .standard:
            Array(repeating: nft?.metadata?.mtwCardTextType == .dark ? UIColor(hex: "2F3241") : .white, count: 2)
        case nil: [.white, .white]
        }
        let cgColors = colors.map(\.cgColor)
        guard gradient.colors as? [CGColor] != cgColors else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = cgColors
        CATransaction.commit()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let center = CGPoint(x: style == .balance ? 0.3 : 0.5, y: 0.5)
        let radius = bounds.width * (style == .balance ? 0.6 : 0.475)
        gradient.startPoint = center
        gradient.endPoint = CGPoint(x: center.x + radius / max(1, bounds.width),
                                    y: center.y + radius / max(1, bounds.height))
        CATransaction.commit()
    }
}
