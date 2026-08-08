import ProtectedAction
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

private let nftBatchSize = 4
private let burnChunkDurationSeconds = 30

final class NftSendReviewViewController: WViewController {
    private let model: NftSendModel
    private let confirmed: ConfirmedNftSend?
    private var confirmButton: WButton

    init(
        model: NftSendModel,
        confirmed: ConfirmedNftSend? = nil
    ) {
        self.model = model
        self.confirmed = confirmed
        self.confirmButton = WButton(
            style: model.configuration.mode == .burn
                || (confirmed?.isScamRecipient
                    ?? model.isScamRecipient)
                ? .destructive
                : .primary
        )
        super.init(nibName: nil, bundle: nil)
        model.onDraftFailure = presentSendDraftError
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private func setupViews() {
        switch model.configuration.mode {
        case .send:
            navigationItem.title = lang("Is it all ok?")
            confirmButton.setTitle(lang("Continue"), for: .normal)
        case .burn:
            navigationItem.title = model.configuration.nfts.count > 1
                ? lang("Burn Collectibles")
                : lang("Burn NFT")
            confirmButton.setTitle(lang("Confirm"), for: .normal)
        }
        addCloseNavigationItemIfNeeded()

        let accountContext = confirmed.map {
            AccountContext(source: .constant($0.account))
        } ?? model.$account
        _ = addHostingController(
            NftSendReviewView(
                model: model,
                confirmed: confirmed,
                accountContext: accountContext
            ),
            constraints: .fill
        )
        setupConfirmButton()
        if confirmed == nil {
            observe { [weak self] in
                guard let self else { return }
                _ = model.continueState
                updateConfirmButton()
            }
            updateConfirmButton()
        }
        if model.configuration.mode == .burn {
            setupBurnWarning()
        }
        view.backgroundColor = .air.sheetBackground
    }

    private func setupConfirmButton() {
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        confirmButton.addTarget(
            self,
            action: #selector(confirmPressed),
            for: .touchUpInside
        )
        view.addSubview(confirmButton)
        NSLayoutConstraint.activate([
            confirmButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16
            ),
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

    private func setupBurnWarning() {
        let warning = BurnNftWarningTile(text: burnWarningText)
        warning.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(warning)
        NSLayoutConstraint.activate([
            warning.bottomAnchor.constraint(
                equalTo: confirmButton.topAnchor,
                constant: -32
            ),
            warning.centerXAnchor.constraint(
                equalTo: view.centerXAnchor
            ),
        ])
    }

    private var burnWarningText: String {
        guard model.configuration.nfts.count > 1 else {
            return lang(
                "Are you sure you want to burn this NFT? It will be lost forever."
            )
        }
        return lang(
            "$multi_burn_nft_warning",
            arg1: localizedIntegerString(model.configuration.nfts.count),
            arg2: burnDurationText
        )
    }

    private var burnDurationText: String {
        let chunkCount = (
            model.configuration.nfts.count + nftBatchSize - 1
        ) / nftBatchSize
        let durationSeconds = chunkCount * burnChunkDurationSeconds
        let durationMinutes = (durationSeconds + 59) / 60
        return lang("$duration_minutes", arg1: durationMinutes)
    }

    @objc private func confirmPressed() {
        view.endEditing(true)
        if confirmed == nil, model.continueState.canRetryDraft {
            model.retryDraft()
            return
        }
        let confirmedSend: ConfirmedNftSend
        do {
            confirmedSend = try confirmed ?? model.makeConfirmedSend()
        } catch {
            AppActions.showError(error: error)
            return
        }
        Task {
            await confirmAction(confirmedSend)
        }
        Haptics.prepare(.success)
    }

    private func confirmAction(
        _ confirmed: ConfirmedNftSend
    ) async {
        let action = ProtectedAction.nftSend(
            confirmed: confirmed
        )
        _ = await ProtectedActionExecutor.execute(action, on: self)
    }

    private func updateConfirmButton() {
        let state = model.continueState
        confirmButton.showLoading = state.isDraftLoading
        confirmButton.isEnabled =
            state.canContinue || state.canRetryDraft
        let title = state.canRetryDraft
            ? lang("Retry")
            : defaultConfirmButtonTitle
        if confirmButton.title(for: .normal) != title {
            confirmButton.setTitle(title, for: .normal)
        }
    }

    private var defaultConfirmButtonTitle: String {
        switch model.configuration.mode {
        case .send:
            lang("Continue")
        case .burn:
            lang("Confirm")
        }
    }
}
