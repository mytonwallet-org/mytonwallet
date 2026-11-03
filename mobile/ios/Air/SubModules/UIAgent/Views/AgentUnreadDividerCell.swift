import UIKit
import UIComponents
import WalletContext

/// "New" between faint lines over the first item the user hasn't seen, in a chat and in the News feed alike
final class AgentUnreadDividerCell: UICollectionViewCell {
    private let titleLabel = UILabel()
    private let leadingLine = UIView()
    private let trailingLine = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.applyTextStyle(.captionStrong, scaling: .dynamic)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleLabel.textColor = .tintColor
        titleLabel.text = lang("$agent_news_new")
        let stack = UIStackView(arrangedSubviews: [leadingLine, titleLabel, trailingLine])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        contentView.addSubview(stack)
        let column = UILayoutGuide()
        contentView.addLayoutGuide(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: AgentContentLayout.maxContentWidth),
            column.widthAnchor.constraint(equalTo: contentView.widthAnchor).withPriority(UILayoutPriority(999)),
            stack.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: AgentMessageCellMetrics.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -AgentMessageCellMetrics.horizontalInset),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            leadingLine.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            trailingLine.heightAnchor.constraint(equalTo: leadingLine.heightAnchor),
            leadingLine.widthAnchor.constraint(equalTo: trailingLine.widthAnchor),
        ])
        updateLineColor()
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = titleLabel.text
        contentView.accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        updateLineColor()
    }

    private func updateLineColor() {
        leadingLine.backgroundColor = tintColor.withAlphaComponent(0.2)
        trailingLine.backgroundColor = leadingLine.backgroundColor
    }
}
