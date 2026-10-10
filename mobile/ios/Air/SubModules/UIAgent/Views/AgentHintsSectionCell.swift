import UIKit
import UIComponents
import WalletContext

private enum AgentHintsSectionMetrics {
    static let contentInset: CGFloat = 20
    static let sparkleSize: CGFloat = 48
    static let sparkleToPillsSpacing: CGFloat = 16
}

final class AgentHintsSectionView: UIView {
    private let stackView = UIStackView()
    private let sparkleView = UIImageView(image: UIImage(named: "HintSparcle", in: AirBundle, compatibleWith: nil))
    private var buttons: [AgentSuggestionButton] = []
    private var hints: [AgentHint] = []
    private var onHintTap: ((AgentHint) -> Void)?

    nonisolated static func calculateContentHeight(for hintCount: Int) -> CGFloat {
        guard hintCount > 0 else { return 0 }
        return AgentHintsSectionMetrics.sparkleSize + AgentHintsSectionMetrics.sparkleToPillsSpacing
            + CGFloat(hintCount) * AgentSuggestionButton.height
            + CGFloat(hintCount - 1) * AgentSuggestionButton.spacing
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
        layer.shadowOpacity = 1
        layer.shadowRadius = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.spacing = AgentSuggestionButton.spacing
        addSubview(stackView)
        sparkleView.contentMode = .scaleAspectFit
        sparkleView.isAccessibilityElement = false
        stackView.addArrangedSubview(sparkleView)
        stackView.setCustomSpacing(AgentHintsSectionMetrics.sparkleToPillsSpacing, after: sparkleView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AgentHintsSectionMetrics.contentInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AgentHintsSectionMetrics.contentInset),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            sparkleView.widthAnchor.constraint(equalToConstant: AgentHintsSectionMetrics.sparkleSize),
            sparkleView.heightAnchor.constraint(equalToConstant: AgentHintsSectionMetrics.sparkleSize),
        ])
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = CGPath(rect: bounds.insetBy(dx: 0, dy: -8), transform: nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyTheme()
    }

    func configure(with hints: [AgentHint], onHintTap: @escaping (AgentHint) -> Void) {
        self.onHintTap = onHintTap
        self.hints = hints
        while buttons.count > hints.count {
            buttons.removeLast().removeFromSuperview()
        }
        while buttons.count < hints.count {
            let index = buttons.count
            let button = AgentSuggestionButton()
            button.addAction(UIAction { [weak self] _ in
                guard let self, self.hints.indices.contains(index) else { return }
                self.onHintTap?(self.hints[index])
            }, for: .touchUpInside)
            buttons.append(button)
            stackView.addArrangedSubview(button)
            button.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: AgentSuggestionButton.height).isActive = true
        }
        for (button, hint) in zip(buttons, hints) {
            button.configure(title: hint.title)
        }
        stackView.isHidden = hints.isEmpty
    }

    func applyTheme() {
        layer.shadowColor = UIColor.air.background.resolvedColor(with: traitCollection).cgColor
    }
}
