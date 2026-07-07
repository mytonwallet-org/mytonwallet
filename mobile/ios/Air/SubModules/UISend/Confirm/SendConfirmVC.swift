
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("SendConfirmVC")
private let nftBatchSize = 4
private let burnChunkDurationSeconds = 30

class SendConfirmVC: WViewController, WalletCoreData.EventsObserver {

    let model: SendModel
    private var awaitingActivity = false
    private var confirmationSucceeded = false
    private var pendingLocalActivities: [ApiActivity] = []

    public init(model: SendModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        WalletCoreData.add(eventObserver: self)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .newLocalActivity(let update):
            guard awaitingActivity, update.accountId == model.account.id else { return }
            for activity in matchingLocalActivities(update.activities) {
                if !pendingLocalActivities.contains(where: { activityCompletionKey($0) == activityCompletionKey(activity) }) {
                    pendingLocalActivities.append(activity)
                }
            }
            if !pendingLocalActivities.isEmpty {
                showPendingActivityIfReady()
            }
        default:
            break
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    private var goBackButton: WButton?
    private var continueButton = WButton(style: .primary)
    private var continueBottomConstraint: NSLayoutConstraint!

    private var activityDetailsContext: ActivityDetailsContext {
        switch model.mode {
        case .sendNft:
            .sendNftConfirmation
        case .burnNft:
            .burnNftConfirmation
        case .regular, .sellToMoonpay:
            .sendConfirmation
        }
    }
    
    private func setupViews() {        
        var continueTitle: String
        var title: String

        if model.isScamRecipient {
            continueButton = WButton(style: .destructive)
        }
                
        switch model.mode {
        case .sendNft:
            title = lang("Is it all ok?")
            continueTitle = lang("Continue")
        case .burnNft:
            continueButton = WButton(style: .destructive)
            continueTitle = lang("Confirm")
            title = model.nfts.count > 1 ? lang("Burn Collectibles") : lang("Burn NFT")
        case .regular:
            title = lang("Is it all ok?")
            continueTitle = lang("Confirm")
            goBackButton = WButton(style: .secondary)
            goBackButton?.setTitle(lang("Edit"), for: .normal)
        case .sellToMoonpay:
            title = lang("Sell")
            continueTitle = lang("Sell %symbol%", arg1: model.token.symbol)
        }

        navigationItem.title = title
        addCloseNavigationItemIfNeeded()
        
        _ = addHostingController(SendConfirmView(model: model), constraints: .fill)
                
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(continueTitle, for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        view.addSubview(continueButton)
        continueBottomConstraint = continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        
        if canGoBack, let goBackButton {
            goBackButton.translatesAutoresizingMaskIntoConstraints = false
            goBackButton.addTarget(self, action: #selector(goBackPressed), for: .touchUpInside)
            view.addSubview(goBackButton)
            
            NSLayoutConstraint.activate([
                continueBottomConstraint,
                goBackButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                continueButton.leadingAnchor.constraint(equalTo: goBackButton.trailingAnchor, constant: 16),
                continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
                goBackButton.bottomAnchor.constraint(equalTo: continueButton.bottomAnchor),
                goBackButton.widthAnchor.constraint(equalTo: continueButton.widthAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                continueBottomConstraint,
                continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
        }
        
        // The very special warning tile for nft burning, sticked to the bottom of the screen.
        // It was hard to achieve this in SwiftUI so do it here
        if model.mode == .burnNft {
            let burnNftWarningTile = BurnNftWarningTile(text: burnNftWarningText)
            burnNftWarningTile.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(burnNftWarningTile)
            
            NSLayoutConstraint.activate([
                burnNftWarningTile.bottomAnchor.constraint(equalTo: continueButton.topAnchor, constant: -32),
                burnNftWarningTile.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
        }
        
        view.backgroundColor = .air.sheetBackground
    }

    private var burnNftWarningText: String {
        if model.nfts.count > 1 {
            return lang(
                "$multi_burn_nft_warning",
                arg1: String(model.nfts.count),
                arg2: burnDurationText
            )
        }

        return lang("Are you sure you want to burn this NFT? It will be lost forever.")
    }

    private var burnDurationText: String {
        let chunkCount = (model.nfts.count + nftBatchSize - 1) / nftBatchSize
        let durationSeconds = chunkCount * burnChunkDurationSeconds
        let durationMinutes = (durationSeconds + 59) / 60

        return lang("$duration_minutes", arg1: durationMinutes)
    }
    
    @objc func continuePressed() {
        view.endEditing(true)
        Task {
            do {
                try await confirmAction()
            } catch is CancellationError {
                resetActivityCompletionState()
            } catch {
                resetActivityCompletionState()
                log.error("\(error)")
                showAlert(error: error) { [weak self] in
                    self?.dismiss(animated: true)
                }
            }
        }
        Haptics.prepare(.success)
    }

    private func confirmAction() async throws {
        resetActivityCompletionState()
        awaitingActivity = true
        _ = try await AppActions.authorizeProtectedAction(
            on: self,
            account: model.account,
            title: lang("Confirm Sending"),
            headerView: SendingHeaderView(model: model),
            passwordAction: { [weak self] password in
                guard let self else { throw CancellationError() }
                return try await self.model.submit(password: password)
            },
            ledgerSignData: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.model.makeLedgerPayload()
            },
            ledgerFromAddress: model.account.getAddress(chain: model.token.chain),
            completionBehavior: .keepAuthForReplacement,
            mfaTitle: lang("Confirm Sending")
        )

        confirmationSucceeded = true
        showPendingActivityIfReady()
    }

    private func showPendingActivityIfReady() {
        guard awaitingActivity, confirmationSucceeded else { return }
        if model.mode.isNftRelated {
            resetActivityCompletionState()
            Haptics.play(.success)
            showNftSuccess()
            return
        }

        guard let activity = pendingLocalActivities.first else { return }
        resetActivityCompletionState()
        Haptics.play(.success)
        AppActions.showActivityDetails(accountId: model.account.id, activity: activity, context: activityDetailsContext)
    }

    private func matchingLocalActivities(_ activities: [ApiActivity]) -> [ApiActivity] {
        guard model.mode.isNftRelated else {
            return Array(activities.prefix(1))
        }
        let nftAddresses = Set(model.nfts.map(\.address))
        return activities.filter { activity in
            guard let nft = activity.transaction?.nft else { return false }
            return nftAddresses.contains(nft.address)
        }
    }

    private func activityCompletionKey(_ activity: ApiActivity) -> String {
        if let nftAddress = activity.transaction?.nft?.address {
            return "\(activity.id):\(nftAddress)"
        }
        return activity.id
    }

    private func showNftSuccess() {
        guard let navigationController else { return }
        let vc = ActionSuccessVC(variant: .sendNft(model))
        vc.navigationItem.hidesBackButton = true
        let coordinator = ContentReplaceAnimationCoordinator()
        coordinator.replaceNavigationTop(with: vc, in: navigationController) {
            vc.animateToCollapsed()
        }
    }

    private func resetActivityCompletionState() {
        awaitingActivity = false
        confirmationSucceeded = false
        pendingLocalActivities = []
    }
    
    @objc func goBackPressed() {
        if model.mode == .burnNft {
            navigationController?.presentingViewController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
