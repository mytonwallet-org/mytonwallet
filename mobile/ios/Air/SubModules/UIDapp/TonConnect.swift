
import SwiftUI
import UIKit
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

struct DappConnectSubmitResult: Sendable, MfaProtectedActionResult {
    let promiseId: String
    let accountId: String
    let proofSignatures: [String]?
    let mfaRequestHash: String?
    let didConfirmImmediately: Bool
}

@MainActor public final class TonConnect: WalletCoreData.EventsObserver {
    
    public static let shared = TonConnect()
    
    private weak var placeholderNc: WNavigationController?
    private weak var lastPresented: UIViewController?
    
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
                if let returnStrategy, case .url(let str) = returnStrategy {
                    openReturnUrl(str)
                }
            } catch {
                log.error("failed to handle deeplink: \(error, .public)")
                AppActions.showError(error: error)
            }
        }
    }

    @MainActor func openReturnUrl(_ returnUrl: String) {
        var str = returnUrl
        if !str.contains("://") {
            str = "https://" + str
        }
        guard let url = URL(string: str) else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
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
        case .dappCloseLoading(let update):
            await handleCloseLoading(update: update)
        case .dappConnect(let update):
            await handleConnect(update: update)
        case .dappSendTransactions(let update):
            await handleSendTransactions(update: update)
        case .dappSignData(let update):
            await handleSignData(update: update)
        case .dappAlreadyConnected(let update):
            await handleAlreadyConnected(update: update)
        case .dappDisconnected(let update):
            await handleDisconnected(update: update)
        default:
            break
        }
    }

    @MainActor func handleLoading(update: ApiUpdate.DappLoading) async {
        // The SSE request event may arrive before the wake deeplink; if a request modal is already shown, ignore the placeholder.
        if update.isWaitingForRequest == true, lastPresented != nil {
            return
        }
        if let accountId = update.accountId {
            await switchAccountIfNeeded(accountId: accountId)
        }
        // The real request emits a typed `dappLoading` of its own; keep the matching placeholder, or swap it on a type change.
        if let nc = placeholderNc, let top = nc.visibleViewController {
            let matchesType = switch update.connectionType {
            case .connect: top is ConnectDappVC
            case .sendTransaction: top is SendDappVC
            case .signData: top is SignDataVC
            }
            if matchesType {
                return
            }
            placeholderNc = nil
            await withCheckedContinuation { continuation in
                nc.dismiss(animated: false) { continuation.resume() }
            }
        }
        let vc: UIViewController
        switch update.connectionType {
        case .connect:
            vc = ConnectDappVC(placeholderAccountId: update.accountId)
        case .sendTransaction:
            vc = SendDappVC(
                placeholderAccountId: update.accountId,
                isWaitingForRequest: update.isWaitingForRequest == true,
                returnUrl: update.returnUrl
            )
        case .signData:
            vc = SignDataVC(placeholderAccountId: update.accountId)
        }
        let nc = WNavigationController(rootViewController: vc)
        self.placeholderNc = nc
        presentAndRecord(nc)
    }

    @MainActor func handleCloseLoading(update: ApiUpdate.DappCloseLoading) async {
        guard let nc = placeholderNc,
              isPlaceholder(nc.visibleViewController, for: update.connectionType) else {
            return
        }
        placeholderNc = nil
        if lastPresented === nc {
            lastPresented = nil
        }
        await withCheckedContinuation { continuation in
            nc.dismiss(animated: true) {
                continuation.resume()
            }
        }
    }

    @MainActor private func isPlaceholder(_ vc: UIViewController?, for connectionType: ApiDappConnectionType) -> Bool {
        switch connectionType {
        case .connect:
            guard let vc = vc as? ConnectDappVC else { return false }
            return vc.viewModel.update == nil
        case .sendTransaction:
            guard let vc = vc as? SendDappVC else { return false }
            return vc.request == nil
        case .signData:
            guard let vc = vc as? SignDataVC else { return false }
            return vc.update == nil
        }
    }

    @MainActor func handleAlreadyConnected(update: ApiUpdate.DappAlreadyConnected) async {
        let url = update.url
        topViewController()?.showAlert(
            title: lang("Already Connected"),
            text: lang("Return to the dapp to proceed, or reconnect."),
            button: lang("OK"),
            buttonPressed: { [weak self] in
                if let url {
                    self?.openReturnUrl(url)
                }
            },
            secondaryButton: url != nil ? lang("Cancel") : nil
        )
    }

    @MainActor func handleDisconnected(update: ApiUpdate.DappDisconnected) async {
        let url = update.url
        topViewController()?.showAlert(
            title: lang("Dapp Disconnected"),
            text: lang("Please reconnect your wallet from the dapp."),
            button: lang("OK"),
            buttonPressed: { [weak self] in
                if let url {
                    self?.openReturnUrl(url)
                }
            },
            secondaryButton: url != nil ? lang("Cancel") : nil
        )
    }

    @MainActor func handleConnect(update: ApiUpdate.DappConnect) async {
        await switchAccountIfNeeded(accountId: update.accountId)
        Api.recordTonConnectEvent(eventName: "wallet-connect-request-ui-displayed", promiseId: update.promiseId)
        if let vc = placeholderNc?.visibleViewController as? ConnectDappVC {
            vc.replacePlaceholder(
                request: update,
                onCancel: { [weak self] in self?.cancelConnect(request: update) }
            )
            self.placeholderNc = nil
        } else {
            let vc = ConnectDappVC(
                request: update,
                onCancel: { [weak self] in self?.cancelConnect(request: update) }
            )
            presentAndRecord(WNavigationController(rootViewController: vc))
        }
    }
    
    func submitConnect(request: ApiUpdate.DappConnect, accountId: String, passcode: String) async throws -> DappConnectSubmitResult {
        Api.recordTonConnectEvent(eventName: "wallet-connect-accepted", promiseId: request.promiseId)
        var signatures: [String]? = nil
        let account = AccountStore.get(accountId: accountId)
        if let proof = request.proof {
            let tonAddress = account.getAddress(chain: .ton) ?? ""
            let dappChains = [
                ApiDappSessionChain(chain: .ton, address: tonAddress, network: account.network),
            ]
            let result = try await Api.signDappProof(
                dappChains: dappChains,
                accountId: accountId,
                proof: proof,
                password: passcode
            )
            signatures = result.signatures
        }
        if account.getChainInfo(chain: .ton)?.mfa != nil {
            let result = try await Api.createDappConnectMfaRequest(accountId: accountId, password: passcode)
            if let error = result.error {
                throw SdkError.apiReturnedError(error: error, context: result)
            }
            guard let mfaRequestHash = result.mfaRequestHash else {
                throw SdkError.unexpected(message: "Missing dapp connect MFA request hash", context: result)
            }
            return DappConnectSubmitResult(
                promiseId: request.promiseId,
                accountId: accountId,
                proofSignatures: signatures,
                mfaRequestHash: mfaRequestHash,
                didConfirmImmediately: false
            )
        }
        try await Api.confirmDappRequestConnect(
            promiseId: request.promiseId,
            data: .init(
                accountId: accountId,
                proofSignatures: signatures
            )
        )
        return DappConnectSubmitResult(
            promiseId: request.promiseId,
            accountId: accountId,
            proofSignatures: signatures,
            mfaRequestHash: nil,
            didConfirmImmediately: true
        )
    }

    func finishConnect(_ result: DappConnectSubmitResult) async throws {
        guard !result.didConfirmImmediately else {
            return
        }
        do {
            try await Api.confirmDappRequestConnect(
                promiseId: result.promiseId,
                data: .init(
                    accountId: result.accountId,
                    proofSignatures: result.proofSignatures
                )
            )
        } catch {
            log.error("finishConnect MFA confirmation failed: \(error, .public)")
            throw error
        }
    }
    
    func cancelConnect(request: ApiUpdate.DappConnect) {
        Api.recordTonConnectEvent(eventName: "wallet-connect-rejected", promiseId: request.promiseId)
        Task {
            do {
                try await Api.cancelDappRequest(promiseId: request.promiseId, reason: "Cancel")
            } catch {
                log.error("cancelConnect \(error, .public)")
            }
        }
    }
    
    @MainActor  func handleSendTransactions(update: ApiUpdate.DappSendTransactions) async {
        await switchAccountIfNeeded(accountId: update.accountId)
        Api.recordTonConnectEvent(eventName: "wallet-transaction-confirmation-ui-displayed", promiseId: update.promiseId)
        if let vc = placeholderNc?.visibleViewController as? SendDappVC {
            vc.replacePlaceholder(
                request: update,
                onCancel: { self.cancelSendTransactions(request: update) }
            )
            self.placeholderNc = nil
        } else {
            let vc = SendDappVC(
                request: update,
                onCancel: { self.cancelSendTransactions(request: update) }
            )
            let nc = WNavigationController(rootViewController: vc)
            if let sheet = nc.sheetPresentationController {
                sheet.detents = [.large()]
            }
            presentAndRecord(nc)
        }
    }
    
    func submitSendTransactions(request: ApiUpdate.DappSendTransactions, password: String?) async throws -> ApiSignDappTransfersResult {
        Api.recordTonConnectEvent(eventName: "wallet-transaction-accepted", promiseId: request.promiseId)
        let account = AccountStore.get(accountId: request.accountId)
        let chain = request.operationChain
        guard let address = account.getAddress(chain: chain) else {
            throw DisplayError(text: lang("No matching chains"))
        }
        guard request.transactions.allSatisfy({ $0.chain == nil || $0.chain == chain }) else {
            throw DisplayError(text: lang("Unexpected error"))
        }
        let dappChain = ApiDappSessionChain(chain: chain, address: address, network: account.network)
        let result = try await Api.signDappTransfersProtected(
            dappChain: dappChain,
            accountId: request.accountId,
            messages: request.transactions.map { ApiTransferToSign($0, chain: chain) },
            options: .init(
                password: password,
                vestingAddress: request.vestingAddress,
                validUntil: request.validUntil,
                isLegacyOutput: request.isLegacyOutput,
            )
        )
        if let signedTransfers = result.signedTransfers {
            try await Api.confirmDappRequestSendTransaction(
                promiseId: request.promiseId,
                data: signedTransfers
            )
        } else if let mfaRequestHash = result.mfaRequestHash {
            do {
                try await Api.confirmDappRequestSendTransactionMfa(
                    promiseId: request.promiseId,
                    mfaRequestHash: mfaRequestHash
                )
            } catch {
                log.error("submitSendTransactions MFA confirmation handoff failed: \(error, .public)")
                throw error
            }
        }
        return result
    }
    
    func cancelSendTransactions(request: ApiUpdate.DappSendTransactions) {
        Api.recordTonConnectEvent(eventName: "wallet-transaction-declined", promiseId: request.promiseId)
        Task {
            do {
                try await Api.cancelDappRequest(promiseId: request.promiseId, reason: lang("Canceled by the user"))
            } catch {
                log.error("cancelSendTransactions \(error, .public)")
            }
        }
    }
    
    @MainActor func handleSignData(update: ApiUpdate.DappSignData) async {
        await switchAccountIfNeeded(accountId: update.accountId)
        Api.recordTonConnectEvent(eventName: "wallet-sign-data-confirmation-ui-displayed", promiseId: update.promiseId)
        if let vc = placeholderNc?.visibleViewController as? SignDataVC {
            vc.replacePlaceholder(
                update: update,
                onCancel: { self.cancelSignData(update: update) }
            )
            self.placeholderNc = nil
        } else {
            let vc = SignDataVC(
                update: update,
                onCancel: { self.cancelSignData(update: update) }
            )
            let nc = WNavigationController(rootViewController: vc)
            presentAndRecord(nc)
        }
    }
    
    func submitSignData(update: ApiUpdate.DappSignData, password: String?) async throws -> ApiMfaProtectedResult {
        Api.recordTonConnectEvent(eventName: "wallet-sign-data-accepted", promiseId: update.promiseId)
        let account = AccountStore.get(accountId: update.accountId)
        let chain = update.operationChain
        guard let address = account.getAddress(chain: chain) else {
            throw DisplayError(text: lang("No matching chains"))
        }
        let dappChain = ApiDappSessionChain(chain: chain, address: address, network: account.network)
        let result = try await Api.signDappData(
            dappChain: dappChain,
            accountId: update.accountId,
            dappUrl: update.dapp.url,
            payloadToSign: update.payloadToSign,
            password: password
        )
        try await Api.confirmDappRequestSignData(promiseId: update.promiseId, data: AnyEncodable(result))
        return ApiMfaProtectedResult()
    }
    
    func cancelSignData(update: ApiUpdate.DappSignData) {
        Api.recordTonConnectEvent(eventName: "wallet-sign-data-declined", promiseId: update.promiseId)
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
    
    @MainActor func presentAndRecord(_ vc: UIViewController) {
        // Only one dapp request modal at a time: if one is still on screen (e.g. a connect deeplink
        // tapped twice in a row), replace it instead of stacking a second sheet.
        if let previous = lastPresented, previous.presentingViewController != nil {
            previous.dismiss(animated: false) { [weak self] in
                self?.lastPresented = vc
                topViewController()?.present(vc, animated: true)
            }
        } else {
            lastPresented = vc
            topViewController()?.present(vc, animated: true)
        }
    }
}
