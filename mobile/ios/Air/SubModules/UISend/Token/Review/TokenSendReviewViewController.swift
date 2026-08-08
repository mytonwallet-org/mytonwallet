import ProtectedAction
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

final class TokenSendReviewViewController: WViewController {
    private let model: TokenSendModel
    private let confirmed: ConfirmedTokenSend?
    private var confirmButton = WButton(style: .primary)
    private var editButton: WButton?

    init(
        model: TokenSendModel,
        confirmed: ConfirmedTokenSend? = nil
    ) {
        self.model = model
        self.confirmed = confirmed
        super.init(nibName: nil, bundle: nil)
        model.onDraftFailure = presentSendDraftError
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if confirmed == nil {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(appDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }
        setupViews()
    }

    @objc private func appDidBecomeActive() {
        guard confirmed == nil,
              navigationController?.topViewController === self else {
            return
        }
        model.refreshWalletState()
    }

    private func setupViews() {
        if model.isScamRecipient {
            confirmButton = WButton(style: .destructive)
        }

        switch model.configuration.mode {
        case .send:
            navigationItem.title = lang("Is it all ok?")
            confirmButton.setTitle(lang("Confirm"), for: .normal)
            let editButton = WButton(style: .secondary)
            editButton.setTitle(lang("Edit"), for: .normal)
            self.editButton = editButton
        case .sellToMoonpay:
            navigationItem.title = lang("Sell")
            confirmButton.setTitle(
                lang("Sell %symbol%", arg1: model.token.symbol),
                for: .normal
            )
        }
        addCloseNavigationItemIfNeeded()

        let accountContext = confirmed.map {
            AccountContext(source: .constant($0.account))
        } ?? model.$account
        _ = addHostingController(
            TokenSendReviewView(
                model: model,
                confirmed: confirmed,
                accountContext: accountContext
            ),
            constraints: .fill
        )
        setupButtons()
        if confirmed == nil {
            observe { [weak self] in
                guard let self else { return }
                _ = model.primaryAction
                updateConfirmButton()
            }
            updateConfirmButton()
        }
        view.backgroundColor = .air.sheetBackground
    }

    private func setupButtons() {
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(
            self,
            action: #selector(confirmPressed),
            for: .touchUpInside
        )
        view.addSubview(confirmButton)
        let bottom = confirmButton.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -16
        )

        if canGoBack, let editButton {
            editButton.translatesAutoresizingMaskIntoConstraints = false
            editButton.addTarget(
                self,
                action: #selector(editPressed),
                for: .touchUpInside
            )
            view.addSubview(editButton)
            NSLayoutConstraint.activate([
                bottom,
                editButton.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor,
                    constant: 16
                ),
                confirmButton.leadingAnchor.constraint(
                    equalTo: editButton.trailingAnchor,
                    constant: 16
                ),
                confirmButton.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor,
                    constant: -16
                ),
                editButton.bottomAnchor.constraint(
                    equalTo: confirmButton.bottomAnchor
                ),
                editButton.widthAnchor.constraint(
                    equalTo: confirmButton.widthAnchor
                ),
            ])
        } else {
            NSLayoutConstraint.activate([
                bottom,
                confirmButton.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor,
                    constant: 16
                ),
                confirmButton.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor,
                    constant: -16
                ),
            ])
        }
    }

    @objc private func confirmPressed() {
        view.endEditing(true)
        let confirmedSend: ConfirmedTokenSend
        do {
            if let confirmed {
                confirmedSend = confirmed
            } else {
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
                    confirmedSend = try model.makeConfirmedSend()
                case .unavailable, .validating,
                     .awaitingPreviousDiesel:
                    return
                }
            }
        } catch {
            AppActions.showError(error: error)
            return
        }
        Task {
            await confirmAction(confirmedSend)
        }
        Haptics.prepare(.success)
    }

    @objc private func editPressed() {
        navigationController?.popViewController(animated: true)
    }

    private func confirmAction(
        _ confirmed: ConfirmedTokenSend
    ) async {
        let action = ProtectedAction.tokenSend(
            confirmed: confirmed
        )
        _ = await ProtectedActionExecutor.execute(action, on: self)
    }

    private func updateConfirmButton() {
        let action = model.primaryAction
        confirmButton.showLoading = action.isLoading
        confirmButton.isEnabled = action.isEnabled
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
            defaultConfirmButtonTitle
        }
        if confirmButton.title(for: .normal) != title {
            confirmButton.setTitle(title, for: .normal)
        }
    }

    private var defaultConfirmButtonTitle: String {
        switch model.configuration.mode {
        case .send:
            lang("Confirm")
        case .sellToMoonpay:
            lang("Sell %symbol%", arg1: model.token.symbol)
        }
    }
}
