import UIKit
import UIComponents
import WalletContext

/// The failure and Retry in the middle of a chat, the News feed or the chat list that couldn't load and has nothing to
/// show. With something to show, the failure is the chat's failure line under it instead. Without Retry, it is the
/// message of a feed that loaded with nothing to show.
final class AgentLoadErrorView: UIStackView {
    var onRetry: (() -> Void)?

    let label = UILabel()
    let retryButton = UIButton(type: .system)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        alignment = .center
        spacing = 12
        label.applyTextStyle(.body, scaling: .dynamic)
        label.textColor = .air.secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        label.accessibilityIdentifier = "agent_load_error"
        retryButton.setTitle(lang("Retry"), for: .normal)
        retryButton.titleLabel?.applyTextStyle(.bodyStrong, scaling: .dynamic)
        retryButton.accessibilityIdentifier = "agent_load_retry"
        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)
        retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        addArrangedSubview(label)
        addArrangedSubview(retryButton)
        isHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Centres the view in `column` at `centerY`, clear of the column's sides
    func install(in view: UIView, column: UILayoutGuide, centerY: NSLayoutYAxisAnchor) {
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: column.centerXAnchor),
            centerYAnchor.constraint(equalTo: centerY),
            leadingAnchor.constraint(greaterThanOrEqualTo: column.leadingAnchor, constant: 32),
            trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor, constant: -32),
        ])
    }

    /// Shows `text` with Retry, or hides the view for nil
    func show(_ text: String?) {
        show(text, hasRetry: true)
    }

    /// Shows `text` without Retry, or hides the view for nil
    func showMessage(_ text: String?) {
        show(text, hasRetry: false)
    }

    private func show(_ text: String?, hasRetry: Bool) {
        label.text = text
        retryButton.isHidden = !hasRetry
        isHidden = text == nil
    }

    @objc private func retry() {
        onRetry?()
    }
}
