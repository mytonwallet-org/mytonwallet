import UIKit

/// The spinner under the header while a chat loads what came before its first row
final class AgentLoadingOlderIndicator: UIActivityIndicatorView {
    private static let topInset: CGFloat = 8

    init() {
        super.init(style: .medium)
        hidesWhenStopped = true
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityIdentifier = "agent_loading_older"
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Puts the spinner over `view`'s content just under its header, in the middle of `column`
    func install(in view: UIView, column: UILayoutGuide) {
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: column.centerXAnchor),
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Self.topInset),
        ])
    }

    func setLoading(_ isLoading: Bool) {
        guard isLoading != isAnimating else { return }
        if isLoading {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
}
