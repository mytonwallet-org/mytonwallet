
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


public final class TonConnect {
    
    public static let shared = TonConnect()
    
    private let log = Log("TonConnect")
    
    init() {
        WalletCoreData.add(eventObserver: self)
    }
    
    public func start() {
        // nothing to do, just makes sure shared TonConnect is initialized
    }
    
    public func handleDeeplink(_ url: String) {
        Task { @MainActor in
            do {
                let identifier = "\(Date().timeIntervalSince1970)"
                let returnStrategy = try await Api.startSseConnection(params: ApiSseConnectionParams(
                        url: url,
                        isFromInAppBrowser: false,
                        identifier: identifier
                    )
                )
                if returnStrategy == .empty {
                    return
                } else if let returnStrategy, case .url(var str) = returnStrategy {
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
                topViewController()?.showAlert(error: error)
            }
        }
    }
    
    func presentConnect(request: ApiUpdate.DappConnect) {
        Task { @MainActor in
            let vc = ConnectDappVC(
                request: request,
                onConfirm: { [weak self] accountId, password in
                    self?.confirmConnect(request: request, accountId: accountId, passcode: password)
                },
                onCancel: { [weak self] in
                    self?.cancelConnect(request: request)
                })
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
    
    func presentSendTransactions(request: MDappSendTransactions) {
        Task { @MainActor in
            let vc = SendDappVC(
                request: request,
                onConfirm: { password in
                    if let password {
                        self.confirmSendTransactions(request: request, password: password)
                    } else {
                        self.cancelSendTransactions(request: request)
                    }
                }
            )
            let nc = WNavigationController(rootViewController: vc)
            if let sheet = nc.sheetPresentationController {
                sheet.detents = [.large()]
            }
            topViewController()?.present(nc, animated: true)
        }
    }
    
    func confirmSendTransactions(request: MDappSendTransactions, password: String) {
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
                try await Api.cancelDappRequest(promiseId: request.promiseId, reason: nil)
            } catch {
                log.error("cancelSendTransactions \(error, .public)")
            }
        }
    }
    
    func presentSignData(update: ApiUpdate.DappSignData) {
        Task { @MainActor in
            let vc = SignDataVC(
                update: update,
                onConfirm: { password in
                    self.confirmSignData(update: update, password: password)
                },
                onCancel: {
                    self.cancelSignData(update: update)
                }
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
}


extension TonConnect: WalletCoreData.EventsObserver {
    public nonisolated func walletCore(event: WalletCore.WalletCoreData.Event) {
        switch event {
        case .dappConnect(request: let request):
            presentConnect(request: request)
        case .dappSendTransactions(let request):
            presentSendTransactions(request: request)
        case .dappSignData(let update):
            presentSignData(update: update)
        default:
            break
        }
    }
}
