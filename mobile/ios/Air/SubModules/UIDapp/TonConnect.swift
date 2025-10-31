
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext

public let TonConnectErrorCodes: [Int: String] = [
    0: "unknownError",
    1: "badRequestError",
    2: "manifestNotFoundError",
    3: "manifestContentError",
    100: "unknownAppError",
    300: "userRejectsError",
    400: "methodNotSupported",
]

private let log = Log("TonConnect")


public final class TonConnect: WalletCoreData.EventsObserver {
    
    public static let shared = TonConnect()
    
    private weak var placeholderNc: WNavigationController?
    
    init() {
        WalletCoreData.add(eventObserver: self)
    }
    
    public func start() {
        // nothing to do, just makes sure shared TonConnect is initialized
    }
    
    public func handleDeeplink(_ url: String) {
        Task { @MainActor in
            do {
                showOverlay()
                let identifier = "\(Date().timeIntervalSince1970)"
                let returnStrategy = try await Api.startSseConnection(params: ApiSseConnectionParams(
                        url: url,
                        isFromInAppBrowser: false,
                        identifier: identifier
                    )
                )
                
                if returnStrategy == .empty {
                    return
                }
                
                dismissOverlayIfNeeded()
                if let returnStrategy, case .url(var str) = returnStrategy {
                    if !str.contains("://") {
                        str = "https://" + str
                    }
                    if let url = URL(string: str) {
                        DispatchQueue.main.async {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } catch {
                log.error("failed to handle deeplink: \(error, .public)")
                dismissOverlayIfNeeded()
                topViewController()?.showAlert(error: error)
            }
        }
    }

    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        Task {
            await handleEvent(event: event)
        }
    }
    
    func handleEvent(event: WalletCoreData.Event) async {
        switch event {
        case .dappLoading(let update):
            await handleLoading(update: update)
        case .dappConnect(let update):
            await handleConnect(update: update)
        case .dappSendTransactions(let update):
            await handleSendTransactions(update: update)
        case .dappSignData(let update):
            await handleSignData(update: update)
        default:
            break
        }
    }
    
    @MainActor func showOverlay() {
        if let window = UIApplication.shared.sceneKeyWindow, !window.subviews.any({ $0 is TonConnectOverlayView }) {
            let overlay = TonConnectOverlayView()
            window.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: window.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: window.bottomAnchor),
                overlay.leadingAnchor.constraint(equalTo: window.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            ])
        }
    }
    
    @MainActor func dismissOverlayIfNeeded() {
        if let window = UIApplication.shared.sceneKeyWindow, let overlay = window.subviews.compactMap({ $0 as? TonConnectOverlayView }).first {
            overlay.isUserInteractionEnabled = false
            overlay.dismissSelf()
        }
    }
    
    @MainActor func handleLoading(update: ApiUpdate.DappLoading) async {
        dismissOverlayIfNeeded()
        if let accountId = update.accountId {
            await switchAccountIfNeeded(accountId: accountId)
        }
        let vc: UIViewController
        switch update.connectionType {
        case .connect:
            vc = ConnectDappVC(placeholderAccountId: update.accountId)
        case .sendTransaction:
            vc = SendDappVC(placeholderAccountId: update.accountId)
        case .signData:
            vc = SignDataVC(placeholderAccountId: update.accountId)
        }
        let nc = WNavigationController(rootViewController: vc)
        self.placeholderNc = nc
        topViewController()?.present(nc, animated: true)
    }
    
    @MainActor func handleConnect(update: ApiUpdate.DappConnect) async {
        dismissOverlayIfNeeded()
        await switchAccountIfNeeded(accountId: update.accountId)
        if let vc = placeholderNc?.visibleViewController as? ConnectDappVC {
            vc.replacePlaceholder(
                request: update,
                onConfirm: { [weak self] accountId, password in self?.confirmConnect(request: update, accountId: accountId, passcode: password) },
                onCancel: { [weak self] in self?.cancelConnect(request: update) }
            )
            self.placeholderNc = nil
        } else {
            let vc = ConnectDappVC(
                request: update,
                onConfirm: { [weak self] accountId, password in self?.confirmConnect(request: update, accountId: accountId, passcode: password) },
                onCancel: { [weak self] in self?.cancelConnect(request: update) }
            )
            topViewController()?.present(vc, animated: true)
        }
    }
    
    func confirmConnect(request: ApiUpdate.DappConnect, accountId: String, passcode: String) {
        Task {
            do {
                var result: ApiSignTonProofResult?
                if let proof = request.proof {
                    result = try await Api.signTonProof(
                        accountId: accountId,
                        proof: proof,
                        password: passcode
                    )
                }
                try await Api.confirmDappRequestConnect(
                    promiseId: request.promiseId,
                    data: .init(
                        accountId: accountId,
                        proofSignature: result?.signature
                    )
                )
            } catch {
                log.error("confirmConnect \(error, .public)")
            }
        }
    }
    
    func cancelConnect(request: ApiUpdate.DappConnect) {
        Task {
            do {
                try await Api.cancelDappRequest(promiseId: request.promiseId, reason: "Cancel")
            } catch {
                log.error("cancelConnect \(error, .public)")
            }
        }
    }
    
    @MainActor  func handleSendTransactions(update: MDappSendTransactions) async {
        dismissOverlayIfNeeded()
        await switchAccountIfNeeded(accountId: update.accountId)
        if let vc = placeholderNc?.visibleViewController as? SendDappVC {
            vc.replacePlaceholder(
                request: update,
                onConfirm: { password in self.confirmSendTransactions(request: update, password: password) },
                onCancel: { self.cancelSendTransactions(request: update) }
            )
            self.placeholderNc = nil
        } else {
            let vc = SendDappVC(
                request: update,
                onConfirm: { password in self.confirmSendTransactions(request: update, password: password) },
                onCancel: { self.cancelSendTransactions(request: update) }
            )
            let nc = WNavigationController(rootViewController: vc)
            if let sheet = nc.sheetPresentationController {
                sheet.detents = [.large()]
            }
            topViewController()?.present(nc, animated: true)
        }
    }
    
    func confirmSendTransactions(request: MDappSendTransactions, password: String?) {
        Task {
            do {
                let signedMessages = try await Api.signTransfers(
                    accountId: request.accountId,
                    messages: request.transactions.map(ApiTransferToSign.init),
                    options: .init(
                        password: password,
                        vestingAddress: request.vestingAddress,
                        validUntil: request.validUntil,
                    )
                )
                try await Api.confirmDappRequestSendTransaction(
                    promiseId: request.promiseId,
                    data: signedMessages
                )
            } catch {
                log.error("confirmSendTransactions \(error, .public)")
            }
        }
    }
    
    func cancelSendTransactions(request: MDappSendTransactions) {
        Task {
            do {
                try await Api.cancelDappRequest(promiseId: request.promiseId, reason: lang("Canceled by the user"))
            } catch {
                log.error("cancelSendTransactions \(error, .public)")
            }
        }
    }
    
    @MainActor func handleSignData(update: ApiUpdate.DappSignData) async {
        dismissOverlayIfNeeded()
        await switchAccountIfNeeded(accountId: update.accountId)
        if let vc = placeholderNc?.visibleViewController as? SignDataVC {
            vc.replacePlaceholder(
                update: update,
                onConfirm: { password in self.confirmSignData(update: update, password: password) },
                onCancel: { self.cancelSignData(update: update) }
            )
            self.placeholderNc = nil
        } else {
            let vc = SignDataVC(
                update: update,
                onConfirm: { password in self.confirmSignData(update: update, password: password) },
                onCancel: { self.cancelSignData(update: update) }
            )
            let nc = WNavigationController(rootViewController: vc)
            topViewController()?.present(nc, animated: true)
        }
    }
    
    func confirmSignData(update: ApiUpdate.DappSignData, password: String?) {
        Task {
            do {
                let result = try await Api.signData(accountId: update.accountId, dappUrl: update.dapp.url, payloadToSign: update.payloadToSign, password: password)
                let dict = try (result as? [String: Any]).orThrow()
                try await Api.confirmDappRequestSignData(promiseId: update.promiseId, data: AnyEncodable(dict: dict))
            } catch {
                log.error("confirmSignData: \(error)")
            }
        }
    }
    
    func cancelSignData(update: ApiUpdate.DappSignData) {
        Task {
            do {
                try await Api.cancelDappRequest(promiseId: update.promiseId, reason: nil)
            } catch {
                log.error("cancelSignData: \(error)")
            }
        }
    }
    
    func switchAccountIfNeeded(accountId: String) async {
        do {
            if AccountStore.accountId != accountId {
                _ = try await AccountStore.activateAccount(accountId: accountId)
            }
        } catch {
            log.fault("failed to switch to account \(accountId, .public) error:\(error, .public)")
        }
    }
}
