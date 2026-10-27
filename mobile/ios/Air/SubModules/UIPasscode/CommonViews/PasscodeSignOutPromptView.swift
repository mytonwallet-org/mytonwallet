import UIKit
import UIComponents
import WalletContext

final class PasscodeSignOutPromptView: UIView {
    private let onButtonPressed: () -> Void

    init(
        textColor: UIColor,
        onButtonPressed: @escaping () -> Void
    ) {
        self.onButtonPressed = onButtonPressed
        super.init(frame: .zero)
        setupViews(textColor: textColor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(textColor: UIColor) {
        let promptLabel = UILabel()
        promptLabel.applyTextStyle(.supporting)
        promptLabel.text = lang("Can't confirm?")
        promptLabel.textColor = textColor
        promptLabel.alpha = 0.75

        let actionLabel = UILabel()
        actionLabel.applyTextStyle(.supportingStrong)
        actionLabel.text = lang("Exit all wallets")
        actionLabel.textColor = textColor

        let chevronImageView = UIImageView(
            image: UIImage(
                systemName: "chevron.forward",
                withConfiguration: UIImage.SymbolConfiguration(
                    font: WTypography.uiFont(.supportingStrong, content: .technical)
                )
            )?.withRenderingMode(.alwaysTemplate)
        )
        chevronImageView.tintColor = textColor
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
