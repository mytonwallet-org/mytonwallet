import UIKit
import WalletCore
import WalletContext

final class CardBorderView: UIView {
    private let gradient = CAGradientLayer()
    private let highlight = CAGradientLayer()
    private let borderMask = CALayer()
    private var cardType: ApiMtwCardType?
    private var shine: ApiMtwCardBorderShineType?
    private var widthMultiplier: CGFloat = 1
    private var motionEnabled = false
    private var showsDefaultBorder = false
    private var lightTilt = CGPoint.zero

    func setLight(_ light: CardSurfaceLight) {
        let next = light.borderTilt ?? .zero
        guard next != lightTilt else { return }
        lightTilt = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateHighlight()
        CATransaction.commit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        gradient.startPoint = CGPoint(x: 0.65, y: 0.1)
        gradient.endPoint = CGPoint(x: 0.45, y: 0.25)
        highlight.type = .radial
        highlight.startPoint = CGPoint(x: 0.5, y: 0.5)
        highlight.endPoint = CGPoint(x: 1, y: 1)
        highlight.colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        borderMask.cornerRadius = 26
        borderMask.cornerCurve = .continuous
        borderMask.borderColor = UIColor.white.cgColor
        layer.addSublayer(gradient)
        layer.addSublayer(highlight)
        layer.mask = borderMask
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(nft: ApiNft?, widthMultiplier: CGFloat, motionEnabled: Bool = false, showsDefaultBorder: Bool = false) {
        self.motionEnabled = motionEnabled
        self.showsDefaultBorder = showsDefaultBorder
        cardType = nft?.metadata?.mtwCardType
        shine = nft?.metadata?.mtwCardBorderShineType
        self.widthMultiplier = widthMultiplier
        updateColors()
        setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateColors()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        let dx = -0.2 * bounds.width * bounds.width
        let dy = 0.15 * bounds.height * bounds.height
        let length = 0.04 * bounds.width * bounds.width + 0.0225 * bounds.height * bounds.height
        let divisor = dx * dx + dy * dy
        if divisor > 0 {
            gradient.endPoint = CGPoint(x: 0.65 + dx * length / divisor, y: 0.1 + dy * length / divisor)
        }
        borderMask.contentsScale = traitCollection.displayScale
        borderMask.frame = bounds
        borderMask.borderWidth = (cardType == .black ? 2 : 1.333) * widthMultiplier
        updateHighlight()
        CATransaction.commit()
    }

    private func updateHighlight() {
        highlight.bounds = bounds
        highlight.position = CGPoint(x: bounds.midX, y: bounds.midY)
        highlight.locations = [cardType == .black ? 0.1 : 0.05, 1]
        highlight.isHidden = highlightRotation == nil
        let restRotation = (highlightRotation ?? 0) * .pi / 180
        if motionEnabled {
            // Match the native resting footprint in physical coordinates. A
            // finger/device vector takes it towards the corresponding card edge.
            let influence = min(1, hypot(lightTilt.x, lightTilt.y))
            let rest = CGPoint(x: cos(restRotation) * bounds.width * 0.5,
                               y: sin(restRotation) * bounds.width * 0.5)
            let offset = CGPoint(x: rest.x * (1 - influence) + lightTilt.x * bounds.width * 0.55,
                                 y: rest.y * (1 - influence) + lightTilt.y * bounds.height * 0.72)
            let rotation = hypot(offset.x, offset.y) > 0.001 ? atan2(offset.y, offset.x) : restRotation
            highlight.position = CGPoint(x: bounds.midX + offset.x, y: bounds.midY + offset.y)
            highlight.setAffineTransform(CGAffineTransform(rotationAngle: rotation)
                .scaledBy(x: cardType == .black ? 0.6 : 1, y: cardType == .black ? 1.3 : 0.5))
        } else {
            highlight.setAffineTransform(CGAffineTransform(rotationAngle: restRotation)
                .translatedBy(x: bounds.width * 0.5, y: 0)
                .scaledBy(x: cardType == .black ? 0.6 : 1, y: cardType == .black ? 1.3 : 0.5))
        }
    }

    private var highlightRotation: CGFloat? {
        if showsDefaultBorder || cardType?.isPremium == true { return -45 }
        return switch shine {
        case .up: -80
        case .down: 70
        case .left: -190
        case .right: 10
        case .radioactive: motionEnabled ? -45 : nil
        case nil: nil
        }
    }

    private func updateColors() {
        let colors: [UIColor]?
        if shine == .radioactive {
            colors = Array(repeating: UIColor(hex: "5CE850").withAlphaComponent(0.95), count: 2)
        } else {
            colors = switch cardType {
            case .black:
                [UIColor.white.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.06 : 0.12),
                 UIColor.white.withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.12 : 0.24)]
            case .platinum:
                [UIColor(hex: "77777F").withAlphaComponent(0.4), UIColor.white.withAlphaComponent(0.4)]
            case .gold:
                [UIColor(hex: "4C3403").withAlphaComponent(0.4), UIColor(hex: "B07D1D").withAlphaComponent(0.4)]
            case .silver:
                [UIColor(hex: "272727").withAlphaComponent(0.4), UIColor(hex: "989898").withAlphaComponent(0.4)]
            case .standard:
                [UIColor(hex: "8C94B0").withAlphaComponent(0.5), UIColor(hex: "BABCC2").withAlphaComponent(0.85)]
            case nil: showsDefaultBorder ? [UIColor.white.withAlphaComponent(0.08), UIColor.white.withAlphaComponent(0.28)] : nil
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.map(premultipliedGradientColors)
        gradient.isHidden = colors == nil
        CATransaction.commit()
    }

    private func premultipliedGradientColors(_ colors: [UIColor]) -> [CGColor] {
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        colors[0].getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        colors[1].getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        if a0 == a1 { return colors.map(\.cgColor) }
        return (0...64).map { index in
            let t = CGFloat(index) / 64
            let alpha = a0 * (1 - t) + a1 * t
            guard alpha > 0 else { return UIColor.clear.cgColor }
            return UIColor(red: (r0 * a0 * (1 - t) + r1 * a1 * t) / alpha,
                           green: (g0 * a0 * (1 - t) + g1 * a1 * t) / alpha,
                           blue: (b0 * a0 * (1 - t) + b1 * a1 * t) / alpha,
                           alpha: alpha).cgColor
        }
    }

}

/// One critically smoothed position; a finger temporarily owns it and releasing
/// hands it back to the live gyroscope, even with geometric card tilt set to zero.
struct CardBorderLightMotion {
    private var touch: CGPoint?
    private var target = CGPoint.zero
    private(set) var value = CGPoint.zero
    var isSettled: Bool { hypot(value.x - target.x, value.y - target.y) < 0.0001 }
    mutating func reset() { self = Self() }
    mutating func press(at point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        touch = CGPoint(x: min(1, max(-1, point.x)), y: min(1, max(-1, point.y)))
        target = touch!
    }
    mutating func release() { touch = nil; target = .zero }
    mutating func advance(gyro: CGPoint, by dt: TimeInterval) {
        guard dt > 0 else { return }
        target = touch ?? gyro
        let amount = CGFloat(1 - exp(-dt / 0.12))
        value.x += (target.x - value.x) * amount
        value.y += (target.y - value.y) * amount
        if isSettled { value = target }
    }
}
