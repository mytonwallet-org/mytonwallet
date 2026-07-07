import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("MfaFlowModel")
private let installStartAppPrefix = "i-"

@MainActor
final class MfaFlowModel: ObservableObject {
    static let installFee: BigInt = 150_000_000

    @Published private(set) var installRequestId: String?
    @Published private(set) var installCandidateUser: AccountMfa.User?
    @Published private(set) var removeRequestId: String?
    @Published private(set) var isRefreshingMfa = false

    var onInstallConfirmationRequested: ((AccountMfa.User) -> Void)?
    var onRemoveConfirmationRequested: ((AccountMfa.User?) -> Void)?

    let accountContext: AccountContext

    private var didPresentInstallConfirmation = false
    private var didRunOpeningMfaRefresh = false
    private var mfaRefreshGeneration = 0

    init(accountContext: AccountContext) {
        self.accountContext = accountContext
    }

    var isWaitingForTelegramInstall: Bool {
        installRequestId != nil && installCandidateUser == nil
    }

    var isWaitingForTelegramRemoval: Bool {
        removeRequestId != nil
    }

    func primaryAction(mfa: AccountMfa?) async {
        if let mfa {
            guard removeRequestId == nil else { return }
            onRemoveConfirmationRequested?(mfa.user)
            return
        }

        if let installCandidateUser {
            invalidateOpeningMfaRefresh()
            onInstallConfirmationRequested?(installCandidateUser)
            return
        }
        if let installRequestId {
            openInstallTelegram(requestId: installRequestId)
            return
        }

        do {
            invalidateOpeningMfaRefresh()
            let request = try await Api.publishInstallMfaRequest(accountId: accountContext.accountId)
            installRequestId = request.reqId
            openInstallTelegram(requestId: request.reqId)
        } catch {
            log.error("publishInstallMfaRequest failed: \(error, .public)")
            topWViewController()?.showAlert(error: error)
        }
    }

    func confirmInstall(passcode: String) async throws {
        guard let installCandidateUser, installCandidateUser.id?.nilIfEmpty != nil else {
            let error = DisplayError(text: "Telegram account is missing required id.")
            log.error("confirmInstall failed: \(error, .public)")
            throw error
        }

        invalidateOpeningMfaRefresh()
        do {
            let address = try await Api.installMfaFromRequest(
                accountId: accountContext.accountId,
                user: installCandidateUser,
                password: passcode
            )
            try await AccountStore.updateMfa(
                accountId: accountContext.accountId,
                mfa: AccountMfa(address: address, user: installCandidateUser)
            )
        } catch {
            log.error("confirmInstall failed: \(error, .public)")
            throw error
        }

        self.installCandidateUser = nil
        didPresentInstallConfirmation = false
    }

    func confirmRemove(passcode: String) async throws {
        do {
            let request = try await Api.publishRemoveMfaRequest(
                accountId: accountContext.accountId,
                password: passcode
            )
            removeRequestId = request.reqId
            openTelegram(startApp: request.reqId)
        } catch {
            log.error("confirmRemove failed: \(error, .public)")
            throw error
        }
    }

    func refreshStoredMfaOnOpenIfNeeded() async {
        guard !didRunOpeningMfaRefresh else {
            return
        }
        didRunOpeningMfaRefresh = true
        let generation = mfaRefreshGeneration
        log.info("[mfa] Flow: refreshStoredMfaOnOpen")
        isRefreshingMfa = true
        defer { isRefreshingMfa = false }
        do {
            let result = try await Api.refreshMfaState(accountId: accountContext.accountId, password: nil)
            guard generation == mfaRefreshGeneration else {
                return
            }
            if result.changed || result.mfa != nil {
                try await AccountStore.updateMfa(accountId: accountContext.accountId, mfa: result.mfa)
            }
        } catch {
            log.error("refreshStoredMfa failed: \(error, .public)")
        }
    }

    func pollIfNeeded() async {
        if let installRequestId, installCandidateUser == nil {
            do {
                let request = try await Api.fetchInstallMfaRequest(reqId: installRequestId)
                if let user = request.user {
                    self.installCandidateUser = user
                    self.installRequestId = nil
                    invalidateOpeningMfaRefresh()
                    requestInstallConfirmationIfNeeded()
                }
            } catch {
                log.error("fetchInstallMfaRequest failed: \(error, .public)")
            }
        }

        if let removeRequestId {
            do {
                let request = try await Api.fetchMfaRequest(hash: removeRequestId)
                guard request.isConfirmed else { return }

                try await Api.confirmMfaRemovalRequest(accountId: accountContext.accountId)
                try await AccountStore.updateMfa(accountId: accountContext.accountId, mfa: nil)
                self.removeRequestId = nil
            } catch {
                log.error("updateRemoveMfaRequest failed: \(error, .public)")
            }
        }
    }

    private func requestInstallConfirmationIfNeeded() {
        guard !didPresentInstallConfirmation, let installCandidateUser else {
            return
        }
        didPresentInstallConfirmation = true
        onInstallConfirmationRequested?(installCandidateUser)
    }

    private func invalidateOpeningMfaRefresh() {
        mfaRefreshGeneration += 1
        didRunOpeningMfaRefresh = true
    }

    private func openTelegram(startApp: String) {
        guard let url = buildMfaBotUrl(startApp: startApp) else {
            log.error("Failed to build MFA bot url for startApp: \(startApp, .public)")
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private func openInstallTelegram(requestId: String) {
        openTelegram(startApp: "\(installStartAppPrefix)\(requestId)")
    }
}
