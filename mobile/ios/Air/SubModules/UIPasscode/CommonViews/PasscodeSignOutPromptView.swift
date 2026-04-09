import UIKit
import UIComponents
import WalletContext

final class PasscodeSignOutPromptView: UIView {
    private let onButtonPressed: () -> Void

    init(
        promptTextColor: UIColor,
        actionTextColor: UIColor = .systemRed,
        onButtonPressed: @escaping () -> Void
    ) {
        self.onButtonPressed = onButtonPressed
        super.init(frame: .zero)
        setupViews(promptTextColor: promptTextColor, actionTextColor: actionTextColor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(promptTextColor: UIColor, actionTextColor: UIColor) {
        let promptLabel = UILabel()
        promptLabel.font = .systemFont(ofSize: 14)
        promptLabel.text = lang("Can't confirm?")
        promptLabel.textColor = promptTextColor

        let actionLabel = UILabel()
        actionLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        actionLabel.text = lang("Exit all wallets")
        actionLabel.textColor = actionTextColor

        let chevronImageView = UIImageView(
            image: UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            )?.withRenderingMode(.alwaysTemplate)
        )
        chevronImageView.tintColor = actionTextColor
        chevronImageView.contentMode = .scaleAspectFit

        let buttonContentStackView = UIStackView(arrangedSubviews: [actionLabel, chevronImageView])
        buttonContentStackView.axis = .horizontal
        buttonContentStackView.alignment = .center
        buttonContentStackView.spacing = 4
        buttonContentStackView.isUserInteractionEnabled = false

        let actionButton = WBaseButton(type: .system)
        actionButton.backgroundColor = .clear
        actionButton.highlightBackgroundColor = .clear
        actionButton.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
        actionButton.addSubview(buttonContentStackView)
        buttonContentStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonContentStackView.topAnchor.constraint(equalTo: actionButton.topAnchor),
            buttonContentStackView.leadingAnchor.constraint(equalTo: actionButton.leadingAnchor),
            buttonContentStackView.trailingAnchor.constraint(equalTo: actionButton.trailingAnchor),
            buttonContentStackView.bottomAnchor.constraint(equalTo: actionButton.bottomAnchor),
        ])

        let contentStackView = UIStackView(arrangedSubviews: [promptLabel, actionButton])
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentStackView.axis = .horizontal
        contentStackView.alignment = .center
        contentStackView.spacing = 4
        addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(equalTo: topAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func buttonPressed() {
        onButtonPressed()
    }
}
