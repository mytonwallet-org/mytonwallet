import SwiftUI
import UIComponents
import UIKit

final class BurnNftWarningTile: UIView {
    private let textLabel = UILabel()
    private var widthConstraint: NSLayoutConstraint!

    init(text: String) {
        super.init(frame: .zero)
        setup(text: text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(text: String) {
        let background = HostingView {
            WarningBackground(color: .air.error)
        }
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        textLabel.text = text
        textLabel.textColor = .air.error
        textLabel.applyTextStyle(.supportingEmphasized)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        addSubview(textLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            textLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 18
            ),
            textLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 12
            ),
            textLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -12
            ),
            textLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -18
            ),
            widthConstraint,
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let textSize = textLabel.sizeThatFits(.init(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        widthConstraint.constant = min(300, textSize.width + 36)
    }
}
