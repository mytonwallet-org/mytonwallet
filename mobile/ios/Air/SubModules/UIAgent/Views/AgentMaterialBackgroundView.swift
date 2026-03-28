import UIKit

final class AgentMaterialBackgroundView: UIView {
    private let effectView = UIVisualEffectView()
    private let cornerRadius: CGFloat

    var contentView: UIView {
        effectView.contentView
    }

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        setupViews()
        applyEffect()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyEffect() {
        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let effect = UIGlassEffect(style: .regular)
            effectView.effect = effect
            effectView.cornerConfiguration = .corners(radius: .init(floatLiteral: cornerRadius))
        } else {
            effectView.effect = UIBlurEffect(style: .systemMaterial)
            effectView.layer.cornerRadius = cornerRadius
            effectView.layer.cornerCurve = .continuous
            effectView.layer.masksToBounds = true
        }
    }

    private func setupViews() {
        backgroundColor = .clear

        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.backgroundColor = .clear
        effectView.contentView.backgroundColor = .clear
        addSubview(effectView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}
