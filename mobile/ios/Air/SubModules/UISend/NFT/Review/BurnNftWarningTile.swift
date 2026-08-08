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
        backgroundColor = .air.error.withAlphaComponent(0.12)
        layer.cornerCurve = .continuous
        layer.cornerRadius = 10
        layer.masksToBounds = true

        let band = UIView()
        band.backgroundColor = .air.error
        band.translatesAutoresizingMaskIntoConstraints = false
        addSubview(band)

        textLabel.text = text
        textLabel.textColor = .air.error
        textLabel.applyTextStyle(.supportingEmphasized)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        addSubview(textLabel)

        widthConstraint = widthAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            band.leadingAnchor.constraint(equalTo: leadingAnchor),
            band.topAnchor.constraint(equalTo: topAnchor),
            band.bottomAnchor.constraint(equalTo: bottomAnchor),
            band.widthAnchor.constraint(equalToConstant: 4),
            textLabel.leadingAnchor.constraint(
                equalTo: band.trailingAnchor,
                constant: 12
            ),
            textLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: 8
            ),
            textLabel.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -8
            ),
            textLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -16
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
        widthConstraint.constant = min(300, textSize.width + 32)
    }
}
