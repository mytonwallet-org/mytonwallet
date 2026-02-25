
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
        WalletCoreData.add(eventObserver: self)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .newLocalActivity(let update):
            if let activity = update.activities.first {
                Haptics.play(.success)
                AppActions.showActivityDetails(accountId: model.account.id, activity: activity, context: model.mode.isNftRelated ? .sendNftConfirmation : .sendConfirmation)
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
        var continueTitle: String
        var goBackTitle = lang("Edit")
        var canGoBack = true
        var title: String
        
        switch model.mode {
        case .sendNft:
            title = lang("Is it all ok?")
            continueTitle = lang("Send")
        case .burnNft:
            continueTitle = lang("Burn")
            continueButton.backgroundColor = WTheme.error
            goBackTitle = lang("Cancel")
            title = lang("Burn")
        case .regular:
            title = lang("Is it all ok?")
            continueTitle = lang("Confirm")
        case .sellToMoonpay:
            title = lang("Sell")
            continueTitle = lang("Sell %symbol%", arg1: model.token.symbol)
            canGoBack = false
        }

        navigationItem.title = title
        addCloseNavigationItemIfNeeded()
        
        _ = addHostingController(SendConfirmView(model: model), constraints: .fill)
                
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setTitle(continueTitle, for: .normal)
        continueButton.addTarget(self, action: #selector(continuePressed), for: .touchUpInside)
        view.addSubview(continueButton)
        continueBottomConstraint = continueButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        
        if canGoBack {
            goBackButton.translatesAutoresizingMaskIntoConstraints = false
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
        } else {
            NSLayoutConstraint.activate([
                continueBottomConstraint,
                continueButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
                continueButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            ])
        }
        
        updateTheme()
    }
    
    public override func updateTheme() {
        view.backgroundColor = WTheme.sheetBackground
    }
    
    @objc func continuePressed() {
        let account = model.account
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
        Haptics.prepare(.success)
    }
    
    func sendMnemonic() {
        var transferSuccessful = false
        var transferError: (any Error)? = nil
        
        let onAuthTask: (_ passcode: String, _ onTaskDone: @escaping () -> Void) -> Void = { [weak self] password, onTaskDone in
            guard let self else { return }
            Task {
                do {
                    try await self.model.submit(password: password)
                    transferSuccessful = true
                } catch {
                    transferSuccessful = false
                    transferError = error
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
        
        let headerVC = UIHostingController(rootView: SendingHeaderView(model: model))
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
        let account = model.account
        guard let fromAddress = account.getAddress(chain: model.token.chain) else { return }
        
        let signData = try await model.makeLedgerPayload()
        
        let signModel = await LedgerSignModel(
            accountId: model.account.id,
            fromAddress: fromAddress,
            signData: signData
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: SendingHeaderView(model: self.model)
        )
        vc.onDone = { _ in
            // handled by observer
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc func goBackPressed() {
        if model.mode == .burnNft {
            navigationController?.presentingViewController?.dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
