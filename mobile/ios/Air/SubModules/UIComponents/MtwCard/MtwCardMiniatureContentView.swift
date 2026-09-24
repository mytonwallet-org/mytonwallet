import UIKit
import WalletContext
import WalletCore

public final class MtwCardMiniatureContentView: UIView {
    private let content = UIView()
    private let gradient = CAGradientLayer()
    private let tintLayer = CALayer()
    private let maskLayer = CALayer()
    private let barFrames = [
        CGRect(x: 0, y: 3, width: 16, height: 2),
        CGRect(x: 5, y: 6.5, width: 6, height: 1.5),
        CGRect(x: 4, y: 13.5, width: 8, height: 1.5),
    ]

    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        // Match the SwiftUI overlay's 15 pt content plus 18 pt bottom padding before scaling.
        content.bounds = CGRect(x: 0, y: 0, width: 16, height: 33)
        addSubview(content)
        gradient.frame = CGRect(x: 0, y: 0, width: 16, height: 15)
        gradient.type = .radial
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.975, y: 0.5 + 7.6 / 15)
        gradient.colors = [UIColor.white.cgColor, UIColor.white.cgColor]
        gradient.allowsEdgeAntialiasing = true
        tintLayer.frame = gradient.frame
        tintLayer.backgroundColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
        maskLayer.frame = gradient.bounds
        for (index, frame) in barFrames.enumerated() {
            let capsule = CALayer()
            capsule.frame = frame
            capsule.backgroundColor = UIColor.white.cgColor
            capsule.cornerRadius = frame.height / 2
            capsule.cornerCurve = .continuous
            capsule.opacity = index == 0 ? 1 : 0.6
            capsule.allowsEdgeAntialiasing = true
            maskLayer.addSublayer(capsule)
        }
        tintLayer.mask = maskLayer
        tintLayer.addSublayer(gradient)
        content.layer.addSublayer(tintLayer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(nft: ApiNft?) {
        let colors: [UIColor] = switch nft?.metadata?.mtwCardType {
        case .black: [UIColor(hex: "444546"), UIColor(hex: "CECECF")]
        case .platinum: [UIColor(hex: "77777F"), .white]
        case .gold: [UIColor(hex: "B07D1D"), UIColor(hex: "4C3403")]
        case .silver: [UIColor(hex: "989898"), UIColor(hex: "272727")]
        case .standard:
            Array(repeating: nft?.metadata?.mtwCardTextType == .dark ? UIColor(hex: "2F3241") : .white, count: 2)
        case nil: [.white, .white]
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.map(\.cgColor)
        CATransaction.commit()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // SwiftUI aligns the 1.5 pt bars to display pixels before applying the card transforms.
        let displayScale = max(traitCollection.displayScale, 1)
        for (index, capsule) in (maskLayer.sublayers ?? []).enumerated() {
            let frame = barFrames[index]
            let minY = (frame.minY * displayScale).rounded() / displayScale
            let maxY = (frame.maxY * displayScale).rounded() / displayScale
            capsule.frame = CGRect(x: frame.minX, y: minY, width: frame.width, height: maxY - minY)
            capsule.cornerRadius = capsule.bounds.height / 2
        }
        CATransaction.commit()
        content.center = CGPoint(x: bounds.midX, y: bounds.maxY - 16.5)
        let scale = bounds.width / 34
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.backgroundColor = UIColor.label.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }
}
