import UIComponents
import UIKit
import WalletContext
import WalletCore

final class TokenSendComposeViewController:
    WViewController {
    private let model: TokenSendModel
    private var continueButton: WButton?

    private lazy var accountSwitcher = AccountSwitcher(
        configuration: .init(accountSupport: .send)
    ) { [weak self] accountId in
        self?.selectAccount(accountId: accountId)
    }

    init(model: TokenSendModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.onDraftFailure = presentSendDraftError
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        setupViews()
        setupObservers()
    }

    @objc private func appDidBecomeActive() {
        guard navigationController?.topViewController === self else {
            return
        }
        model.refreshWalletState()
    }

    private func setupViews() {
        _ = addHostingController(
            makeView(),
            constraints: .fill
        )
        setupNavigation()
        setupContinueButton()
        view.backgroundColor = .air.sheetBackground
        addCustomNavigationBarBackground(color: .air.sheetBackground)
    }

    private func setupNavigation() {
        navigationItem.titleView = HostingView {
            TokenSendComposeTitleView(
                model: model,
                onSellTapped: { [weak self] in
                    self?.showSell()
                },
                onMultisendTapped: { [weak self] in
                    self?.showMultisend()
                }
            )
        }
        addCloseNavigationItemIfNeeded()
    }

    private func setupContinueButton() {
        let button = addBottomButton(bottomConstraint: false)
        continueButton = button
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
            _ = model.account.id
            updateLeftNavigationItem()
            updateContinueButton()
        }
    }

    private func makeView() -> TokenSendComposeView {
        TokenSendComposeView(
            model: model,
            onTokenSelect: { [weak self] in
                self?.showTokenPicker()
            }
        )
    }

    private func updateContinueButton() {
        guard let continueButton else { return }
        let action = model.primaryAction
        setSendContinueButtonHidden(
            continueButton,
            hidden: model.recipient.isFocused
        )
        continueButton.showLoading = action.isLoading
        continueButton.isEnabled = action.isEnabled
        let title = switch action {
        case .unavailable(.invalidRecipient):
            lang("Invalid address")
        case .unavailable(.insufficientAmount):
            lang("Insufficient Balance")
        case .unavailable(.insufficientFee):
            lang("Insufficient Fee")
        case .authorizeDiesel:
            lang(
                "Authorize %token% Fee",
                arg1: model.token.symbol
            )
        case .awaitingPreviousDiesel:
            lang("Awaiting Previous Fee")
        case .retryDraft, .retryMaximum:
            lang("Retry")
        case .unavailable, .validating, .continueToReview:
            lang("Continue")
        }
        if continueButton.title(for: .normal) != title {
            continueButton.setTitle(title, for: .normal)
        }
    }

    @objc private func continuePressed() {
        view.endEditing(true)
        switch model.primaryAction {
        case .authorizeDiesel(let url):
            UIApplication.shared.open(url)
            return
        case .retryDraft:
            model.retryDraft()
            return
        case .retryMaximum:
            model.retryMaximum()
            return
        case .continueToReview:
            break
        case .unavailable, .validating, .awaitingPreviousDiesel:
            return
        }
        do {
            let confirmed = try model.makeConfirmedSend()
            if model.shouldConfirmDomainScamWarning {
                showDomainScamWarning(confirmed: confirmed)
            } else if model.token.isPricelessToken
                        || model.token.isStakedToken {
                showServiceTokenWarning(confirmed: confirmed)
            } else {
                showReview(confirmed: confirmed)
            }
        } catch {
            AppActions.showError(error: error)
        }
    }

    private func showReview(confirmed: ConfirmedTokenSend) {
        endEditing()
        navigationController?.pushViewController(
            TokenSendReviewViewController(
                model: model,
                confirmed: confirmed
            ),
            animated: true
        )
    }

    private func showServiceTokenWarning(
        confirmed: ConfirmedTokenSend
    ) {
        let alert = UIAlertController(
            title: lang("Warning"),
            message: lang("$service_token_transfer_warning"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: lang("Cancel"),
            style: .cancel
        ))
        alert.addAction(UIAlertAction(
            title: lang("OK"),
            style: .default
        ) { [weak self] _ in
            self?.showReview(confirmed: confirmed)
        })
        present(alert, animated: true)
    }

    private func showDomainScamWarning(
        confirmed: ConfirmedTokenSend
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

    private func showTokenPicker() {
        let picker = TokenPickerViewController(
            accountId: model.account.id,
            isMultichain: model.account.isMultichain,
            presentation: model.$account.walletTokenPresentation,
            currentTokenSlug: model.token.slug,
            onSelect: { [weak self] token in
                self?.model.selectToken(token, source: .user)
                topViewController()?.dismiss(animated: true)
            }
        )
        present(
            WNavigationController(rootViewController: picker),
            animated: true
        )
    }

    private func showSell() {
        let accountContext = model.$account
        let tokenSlug = model.token.slug
        dismiss(animated: true) {
            AppActions.showSell(
                accountContext: accountContext,
                tokenSlug: tokenSlug
            )
        }
    }

    private func showMultisend() {
        dismiss(animated: true)
        AppActions.showMultisend()
    }

    private func updateLeftNavigationItem() {
        if model.recipient.isFocused {
            let backItem = UIBarButtonItem(
                title: "",
                image: UIImage(systemName: "chevron.backward"),
                primaryAction: UIAction { _ in
                    endEditing()
                }
            )
            backItem.accessibilityLabel = lang("Back")
            navigationItem.setLeftBarButtonItems([
                backItem,
            ], animated: true)
            return
        }

        guard model.isAccountSwitchingAllowed else {
            navigationItem.setLeftBarButtonItems(
                nil,
                animated: true
            )
            return
        }

        accountSwitcher.update(
            selectedAccountId: model.account.id
        )
        let items = accountSwitcher.hasAlternativeAccounts(
            selectedAccountId: model.account.id
        ) ? [accountSwitcher.barButtonItem] : nil
        navigationItem.setLeftBarButtonItems(
            items,
            animated: true
        )
    }

    private func selectAccount(accountId: String) {
        Task {
            do {
                try await model.selectAccount(accountId: accountId)
            } catch {
                AppActions.showError(error: error)
            }
        }
    }
}
