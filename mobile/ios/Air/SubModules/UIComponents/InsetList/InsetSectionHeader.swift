import SwiftUI
import UIKit
import WalletContext

public struct InsetSectionHeader: View {
    public static let height: CGFloat = 39
    private let title: String

    public init(title: String) { self.title = title }

    public var body: some View {
        Text(verbatim: title)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(height: 22)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 9)
            .accessibilityAddTraits(.isHeader)
    }
}

/// UIKit counterpart for collection section headers and embedded cards.
public final class InsetSectionHeaderCell: UICollectionReusableView {
    private let titleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private var onAction: (() -> Void)?
    private var topConstraint: NSLayoutConstraint!

    public override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.applyTextStyle(.bodyStrong)
        titleLabel.textColor = .air.secondaryLabel
        titleLabel.accessibilityTraits.insert(.header)
        actionButton.titleLabel?.applyTextStyle(.supporting)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
        actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
        actionButton.isHidden = true
        let row = UIStackView(arrangedSubviews: [titleLabel, actionButton])
        row.alignment = .center
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        topConstraint = row.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            topConstraint,
            row.heightAnchor.constraint(equalToConstant: 22),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    public func configure(title: String, topSpacing: CGFloat = 0, actionTitle: String? = nil, actionAccessibilityIdentifier: String? = nil, onAction: (() -> Void)? = nil) {
        actionButton.accessibilityIdentifier = actionAccessibilityIdentifier
        titleLabel.text = title
        titleLabel.applyTextStyle(.bodyStrong)
        actionButton.titleLabel?.applyTextStyle(.supporting)
        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.isHidden = actionTitle == nil
        self.onAction = onAction
        topConstraint.constant = 8 + topSpacing
    }
}
