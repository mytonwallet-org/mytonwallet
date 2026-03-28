import UIKit
import UIComponents
import WalletCore
import WalletContext

@MainActor
final class StartupFailureVC: WViewController {
    private let log = Log("StartupFailureVC")
    private let failure: StartupFailure
    private let onRetry: () -> Void

    private let iconView = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let detailsLabel = UILabel()
    private let retryButton = WButton(style: .primary)
    private let moreDetailsButton = WButton(style: .clearBackground)
    private let exportLogsButton = WButton(style: .secondary)
    private let supportButton = WButton(style: .clearBackground)

    init(failure: StartupFailure, onRetry: @escaping () -> Void) {
        self.failure = failure
        self.onRetry = onRetry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .air.error
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.text = failure.title

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 17, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.text = failure.message

        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        detailsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsLabel.textColor = .tertiaryLabel
        detailsLabel.textAlignment = .center
        detailsLabel.numberOfLines = 0
        detailsLabel.text = "Code: \(failure.technicalCode)"

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle(lang("Try Again"), for: .normal)
        retryButton.addTarget(self, action: #selector(onRetryPressed), for: .touchUpInside)

        moreDetailsButton.translatesAutoresizingMaskIntoConstraints = false
        moreDetailsButton.setTitle(lang("More Details"), for: .normal)
        moreDetailsButton.addTarget(self, action: #selector(onMoreDetailsPressed), for: .touchUpInside)

        exportLogsButton.translatesAutoresizingMaskIntoConstraints = false
        exportLogsButton.setTitle(lang("Export Logs"), for: .normal)
        exportLogsButton.addTarget(self, action: #selector(onExportLogsPressed), for: .touchUpInside)

        supportButton.translatesAutoresizingMaskIntoConstraints = false
        supportButton.setTitle(lang("Get Support"), for: .normal)
        supportButton.addTarget(self, action: #selector(onSupportPressed), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            iconView,
            titleLabel,
            messageLabel,
            detailsLabel,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16

        var actionViews: [UIView] = [retryButton, moreDetailsButton, exportLogsButton]
        if ConfigStore.shared.config?.supportAccountsCount ?? 1 > 0 {
            actionViews.append(supportButton)
        }
        let actionStack = UIStackView(arrangedSubviews: actionViews)
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.axis = .vertical
        actionStack.alignment = .fill
        actionStack.spacing = 12

        view.addSubview(stack)
        view.addSubview(actionStack)

        NSLayoutConstraint.activate([
            iconView.heightAnchor.constraint(equalToConstant: 40),

            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -72),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: actionStack.topAnchor, constant: -24),

            actionStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            actionStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            actionStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    @objc private func onRetryPressed() {
        retryButton.isEnabled = false
        retryButton.showLoading = true
        onRetry()
    }

    @objc private func onMoreDetailsPressed() {
        showAlert(
            title: lang("More Details"),
            text: failure.detailsText,
            button: lang("OK")
        )
    }

    @objc private func onExportLogsPressed() {
        exportLogsButton.isEnabled = false
        exportLogsButton.showLoading = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.exportLogsButton.showLoading = false
                self.exportLogsButton.isEnabled = true
            }
            do {
                let logs = try await SupportDiagnostics.prepareLogsExportFile()
                let vc = UIActivityViewController(activityItems: [logs], applicationActivities: nil)
                vc.popoverPresentationController?.sourceView = self.exportLogsButton
                self.present(vc, animated: true)
            } catch {
                self.log.fault("startup log export failed \(error, .public)")
                self.showAlert(
                    title: lang("Error"),
                    text: lang("Couldn't prepare logs for export. Please try again."),
                    button: lang("OK")
                )
            }
        }
    }

    @objc private func onSupportPressed() {
        UIApplication.shared.open(SupportDiagnostics.supportURL, options: [:]) { [weak self] didOpen in
            guard !didOpen else { return }
            Task { @MainActor in
                self?.showAlert(
                    title: lang("Error"),
                    text: lang("Couldn't open support chat. Please try again."),
                    button: lang("OK")
                )
            }
        }
    }
}
