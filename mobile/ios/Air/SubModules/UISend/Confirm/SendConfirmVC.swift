
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import UIPasscode
import Ledger

private let log = Log("SendConfirmVC")

class SendConfirmVC: WViewController, WalletCoreData.EventsObserver {

    let model: SendModel
    public init(model: SendModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        model.showToast = { [weak self] animationName, message in
            self?.showToast(animationName: animationName, message: message)
        }
        WalletCoreData.add(eventObserver: self)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .newLocalActivity(let update):
            if let activity = update.activities.first {
                AppActions.pushTransactionSuccess(activity: activity)
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

    private var goBackButton = WButton(style: .secondary)
    private var continueButton = WButton(style: .primary)
    private var continueBottomConstraint: NSLayoutConstraint!
    
    private func setupViews() {
        
        let title = switch model.nftSendMode {
        case .burn:
            lang("Burn")
        default:
            lang("Is it all ok?")
        }
        var backButtonAction: (() -> ())? = nil 
        if model.nftSendMode != .burn {
            backButtonAction = { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        addNavigationBar(
            centerYOffset: 1,
            title: title,
            closeIcon: true,
            addBackButton: backButtonAction)
        navigationBarProgressiveBlurDelta = 12
        
        let hostingController = UIHostingController(
            rootView: SendConfirmView(
                model: model,
                navigationBarInset: navigationBarHeight,
                onScrollPositionChange: { [weak self] y in self?.updateNavigationBarProgressiveBlur(y) }
            )
        )
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)

        continueButton.translatesAutoresizingMaskIntoConstraints = false
        let continueTitle = switch model.nftSendMode {
        case .send:
            lang("Send")
        case .burn:
            lang("Burn")
        case nil:
            lang("Confirm")
        }
        continueButton.setTitle(continueTitle, for: .normal)
        if model.nftSendMode == .burn {
            continueButton.backgroundColor = WTheme.error
        }
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        view.addSubview(continueButton)
        continueBottomConstraint = continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                                          constant: -16)
        
        goBackButton.translatesAutoresizingMaskIntoConstraints = false
        let goBackTitle = switch model.nftSendMode {
        case .burn:
            lang("Cancel")
        default:
            lang("Edit")
        }
        goBackButton.setTitle(goBackTitle, for: .normal)
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
        
        bringNavigationBarToFront()
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    @objc func continuePressed() {
        view.endEditing(true)
        guard let account = AccountStore.account else { return }
        if account.isHardware {
            Task {
                do {
                    try await sendLedger()
                } catch {
                    log.error("\(error)")
                }
            }
        } else {
            sendMnemonic()
        }
    }
    
    func sendMnemonic() {
        guard let token = model.token, let account = AccountStore.account else {
            return
        }
        let accountId = account.id
        var transferSuccessful = false
        var transferError: (any Error)? = nil
        var transferOptions: ApiSubmitTransferOptions? = nil
        
        let onAuthTask: (_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void = {
            [weak self] passcode,
            onTaskDone in
            guard let self else {
                return
            }
            // Send coins!
            Task { [model] in
                if model.nftSendMode == nil {
                    do {
                        transferOptions = try await model.makeSubmitTransferOptions(passcode: passcode, addressOrDomain: model.resolvedAddress!, amount: model.amount, comment: model.comment)!
                        let result = try await Api.submitTransfer(chain: token.chainValue, options: transferOptions!)
                        if let error = result.error {
                            transferError = BridgeCallError.customMessage(error, nil)
                            transferSuccessful = false
                        } else {
                            transferSuccessful = true
                        }
                        
                    } catch {
                        transferSuccessful = false
                        transferError = error
                    }

                } else {
                    do {
                        let fee = model.toAddressDraft?.realFee ?? BigInt(0)
                        _ = try await Api.submitNftTransfers(
                            accountId: accountId,
                            password: passcode,
                            nfts: model.nfts ?? [],
                            toAddress: model.addressOrDomain,
                            comment: model.comment.nilIfEmpty,
                            totalRealFee: fee
                        )
                        transferSuccessful = true
                    } catch {
                        transferSuccessful = false
                        transferError = error
                    }
                }
                onTaskDone()
            }
        }
        let onDone: (String) -> () = { [weak self] _ in
            guard let self else {
                return
            }
            if transferSuccessful {
                // handled by wallet core observer
            } else if let transferError {
                showAlert(error: transferError) { [weak self] in
                    guard let self else { return }
                    dismiss(animated: true)
                }
            }
        }
        
        let headerVC = UIHostingController(rootView: SendingHeaderView().environmentObject(model))
        headerVC.view.backgroundColor = .clear
        
        UnlockVC.pushAuth(
            on: self,
            title: lang("Confirm Sending"),
            customHeaderVC: headerVC,
            onAuthTask: onAuthTask,
            onDone: onDone
        )
    }
    
    func sendLedger() async throws {
        if model.isSendNft {
            try await sendLedgerNft()
        } else {
            try await sendLedgerNormal()
        }
    }
    
    func sendLedgerNormal() async throws {
        guard
            let account = AccountStore.account,
            let fromAddress = account.tonAddress?.nilIfEmpty,
            let ledger = account.ledger
        else { return }
        
        let transferOptions = try await model.makeSubmitTransferOptions(
            passcode: nil,
            addressOrDomain: model.resolvedAddress!,
            amount: model.amount,
            comment: model.comment
        ).orThrow()
        let signModel = await LedgerSignModel(
            accountId: account.id,
            fromAddress: fromAddress,
            ledger: ledger,
            signData: .signTransfer(
                transferOptions: transferOptions
            )
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: SendingHeaderView().environmentObject(self.model)
        )
        vc.onDone = { [model] vc in
            let sentVC = SentVC(model: model, transferOptions: transferOptions)
            vc.navigationController?.pushViewController(sentVC, animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func sendLedgerNft() async throws {
        guard
            let account = AccountStore.account,
            let fromAddress = account.tonAddress?.nilIfEmpty,
            let ledger = account.ledger,
            let nft = model.nfts?.first
        else { return }
        
        if model.nfts?.count != 1 {
            showAlert(title: "Error", text: "Sending more than one NFT isn't supported by Ledger", button: "OK")
        }
        
        let signModel = await LedgerSignModel(
            accountId: account.id,
            fromAddress: fromAddress,
            ledger: ledger,
            signData: .signNftTransfer(
                accountId: account.id,
                nft: nft,
                toAddress: model.addressOrDomain,
                comment: model.comment.nilIfEmpty,
                realFee: model.toAddressDraft?.realFee
            )
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: SendingHeaderView().environmentObject(self.model)
        )
        vc.onDone = { [model] vc in
            let sentVC = SentVC(model: model, transferOptions: nil)
            vc.navigationController?.pushViewController(sentVC, animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc func goBackPressed() {
        if model.nftSendMode == .burn {
            navigationController?.presentingViewController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
