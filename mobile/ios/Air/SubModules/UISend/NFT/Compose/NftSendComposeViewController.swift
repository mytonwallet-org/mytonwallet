import UIComponents
import UIKit
import WalletContext
import WalletCore

final class NftSendComposeViewController:
    WViewController {
    private let model: NftSendModel
    private var continueButton: WButton?
    private var continueButtonPresenter: DraftButtonPresenter?

    init(model: NftSendModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.onDraftFailure = presentSendDraftError
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupObservers()
    }

    private func setupViews() {
        _ = addHostingController(
            NftSendComposeView(model: model),
            constraints: .fill
        )
        navigationItem.title = lang("Send")
        addCloseNavigationItemIfNeeded()
        addCustomNavigationBarBackground(color: .air.sheetBackground)
        setupContinueButton()
        view.backgroundColor = .air.sheetBackground
    }

    private func setupContinueButton() {
        let button = addBottomButton(bottomConstraint: false)
        continueButton = button
        continueButtonPresenter = DraftButtonPresenter(button: button)
        button.setTitle(lang("Continue"), for: .normal)
        button.isEnabled = false
        button.addTarget(
            self,
            action: #selector(continuePressed),
            for: .touchUpInside
        )
        NSLayoutConstraint.activate([
            button.bottomAnchor.constraint(
                equalTo: view.keyboardLayoutGuide.topAnchor,
                constant: -16
            ),
            button.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            )
            .withPriority(.defaultHigh),
        ])
    }

    private func setupObservers() {
        observe { [weak self] in
            guard let self else { return }
            _ = model.primaryAction
            updateContinueButton()
        }
        observe { [weak self] in
            guard let self else { return }
            _ = model.recipient.isFocused
            updateLeftNavigationItem()
            updateContinueButton()
        }
    }

    private func updateContinueButton() {
        guard let continueButton,
              let continueButtonPresenter else {
            return
        }
        continueButtonPresenter.apply(
            buttonConfiguration(for: model.primaryAction)
        )
        // Visibility last: hiding disables interaction and must not be
        // overridden by the presenter's reassertion.
        setSendContinueButtonHidden(
            continueButton,
            hidden: model.recipient.isFocused
        )
    }

    private func buttonConfiguration(
        for action: NftSendPrimaryAction
    ) -> DraftButtonConfiguration {
        let title = switch action {
        case .retryDraft:
            lang("Retry")
        case .invalidAddress:
            model.recipientValidationState == .sendToSelf
                ? lang("$send_recipient_self_transfer")
                : lang("Invalid address")
        case .insufficientBalance:
            lang("Insufficient Balance")
        case .incomplete, .validating, .continueToReview:
            lang("Continue")
        }
        return DraftButtonConfiguration(
            title: .text(title),
            isEnabled: action.isEnabled,
            showLoading: action.isLoading
        )
    }

    @objc private func continuePressed() {
        if model.primaryAction == .retryDraft {
            model.retryDraft()
            return
        }
        guard model.primaryAction == .continueToReview else { return }
        do {
            let confirmed = try model.makeConfirmedSend()
            view.endEditing(true)
            if model.shouldConfirmDomainScamWarning {
                showDomainScamWarning(confirmed: confirmed)
            } else {
                showReview(confirmed: confirmed)
            }
        } catch {
            AppActions.showError(error: error)
        }
    }

    private func showReview(confirmed: ConfirmedNftSend) {
        endEditing()
        navigationController?.pushViewController(
            NftSendReviewViewController(
                model: model,
                confirmed: confirmed
            ),
            animated: true
        )
    }

    private func showDomainScamWarning(
        confirmed: ConfirmedNftSend
    ) {
        guard model.isAllowSuspiciousActions else {
            showAlert(
                title: lang("Warning!"),
                text: SendWarningContent.domainScamPlainText,
                button: lang("Close")
            )
            return
        }
        showAlert(
            title: lang("Warning!"),
            text: SendWarningContent.domainScamPlainText,
            button: lang("Continue"),
            buttonStyle: .destructive,
            buttonPressed: { [weak self] in
                self?.model.confirmDomainScamWarning()
                self?.showReview(confirmed: confirmed)
            },
            secondaryButton: lang("Close"),
            preferPrimary: false
        )
    }

    private func updateLeftNavigationItem() {
        if model.recipient.isFocused {
            navigationItem.setLeftBarButtonItems([
                UIBarButtonItem(
                    title: "",
                    image: UIImage(systemName: "chevron.backward"),
                    primaryAction: UIAction { _ in
                        endEditing()
                    }
                ),
            ], animated: true)
        } else {
            navigationItem.setLeftBarButtonItems(
                nil,
                animated: true
            )
        }
    }
}
