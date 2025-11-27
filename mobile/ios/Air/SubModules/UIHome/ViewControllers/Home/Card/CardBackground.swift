import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Kingfisher

private let MAX_NORMAL_ALPHA: Float = 0.1
private let MAX_OVERLAY_ALPHA: Float = 0.5
private let GRADIENT_COLORS_LIGHT_TEXT = [
    UIColor(white: 0, alpha: 1).cgColor,
    UIColor(white: 0, alpha: 0).cgColor,
]
private let GRADIENT_COLORS_DARK_TEXT = [
    UIColor(white: 1, alpha: 1).cgColor,
    UIColor(white: 1, alpha: 0).cgColor,
]

/// Renders card background (standard/nft) and custom border
@MainActor final class CardBackground: WTouchPassView {

    private var imageView = UIImageView()
    private var borderView = CardBorder()
    private var normalGradient = CAGradientLayer()
    private var overrlayGradient = CAGradientLayer()

    private var currentNft: ApiNft?
    private var currentState: WalletCardView.State = .expanded

    private var cardType: ApiMtwCardType? { currentNft?.metadata?.mtwCardType }
    private var darkText: Bool {
        if let textType = currentNft?.metadata?.mtwCardTextType {
            return textType == .dark
        }
        return false
    }

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 3
        layer.masksToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        normalGradient.type = .radial
        normalGradient.colors = GRADIENT_COLORS_LIGHT_TEXT
        normalGradient.locations = [0, 1.0]
        normalGradient.startPoint = CGPoint(x: 0.5, y: 0.45)
        normalGradient.endPoint = CGPoint(x: normalGradient.startPoint.x + 0.6, y: normalGradient.startPoint.y + 1.0)
        layer.addSublayer(normalGradient)
        normalGradient.opacity = 0

        overrlayGradient.type = .radial
        overrlayGradient.compositingFilter = "overlayBlendMode"
        overrlayGradient.colors = GRADIENT_COLORS_LIGHT_TEXT
        overrlayGradient.locations = normalGradient.locations
        overrlayGradient.startPoint = normalGradient.startPoint
        overrlayGradient.endPoint = normalGradient.endPoint
        layer.addSublayer(overrlayGradient)
        overrlayGradient.opacity = 0

        borderView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(borderView)
        NSLayoutConstraint.activate([
            borderView.topAnchor.constraint(equalTo: topAnchor),
            borderView.bottomAnchor.constraint(equalTo: bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func update(accountId: String?, nft: ApiNft?, accountChanged: Bool) {
    }

    func update(state: WalletCardView.State) {
    }
}
