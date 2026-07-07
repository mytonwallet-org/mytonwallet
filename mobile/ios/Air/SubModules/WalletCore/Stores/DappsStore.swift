
import Foundation
import WalletContext

public let DappsStore = _DappsStore.shared

public final class _DappsStore: Sendable {
    
    public static let shared = _DappsStore()
    
    private let _dappsCount: UnfairLock<[String: Int]> = .init(initialState: [:])
    public var dappsCount: Int? {
        if let accountId = AccountStore.accountId {
            return _dappsCount.withLock { $0[accountId] }
        }
        return nil
    }
    
    public func updateDappCount(accountId: String? = nil) {
        guard let accountId = accountId ?? AccountStore.accountId else { return }
        Task {
            do {
                let dapps = try await Api.getDapps(accountId: accountId)
                updateDappCount(accountId: accountId, count: dapps.count)
            } catch {
                Log.api.error("\(error, .public)")
            }
            
        }
    }
    
    @discardableResult
    public func deleteDapp(accountId: String? = nil, dapp: ApiDapp) async throws -> [ApiDapp] {
        guard let accountId = accountId ?? AccountStore.accountId else { return [] }
        let uniqueId = getDappConnectionUniqueId(dapp)
        let didDelete = try await Api.deleteDapp(accountId: accountId, url: dapp.url, uniqueId: uniqueId, dontNotifyDapp: nil)
        guard didDelete else {
            Log.api.error("deleteDapp returned false url=\(dapp.url, .public) uniqueId=\(uniqueId, .public)")
            throw DisplayError(text: lang("Unexpected error"))
        }
        let dapps = try await Api.getDapps(accountId: accountId)
        guard !dapps.contains(where: { $0.url == dapp.url && getDappConnectionUniqueId($0) == uniqueId }) else {
            updateDappCount(accountId: accountId, count: dapps.count)
            Log.api.error("deleteDapp verification failed url=\(dapp.url, .public) uniqueId=\(uniqueId, .public)")
            throw DisplayError(text: lang("Unexpected error"))
        }
        updateDappCount(accountId: accountId, count: dapps.count)
        return dapps
    }

    @discardableResult
    public func deleteAllDapps(accountId: String) async throws -> [ApiDapp] {
        try await Api.deleteAllDapps(accountId: accountId)
        let dapps = try await Api.getDapps(accountId: accountId)
        guard dapps.isEmpty else {
            updateDappCount(accountId: accountId, count: dapps.count)
            Log.api.error("deleteAllDapps verification failed count=\(dapps.count, .public)")
            throw DisplayError(text: lang("Unexpected error"))
        }
        updateDappCount(accountId: accountId, count: 0)
        return dapps
    }

    private func updateDappCount(accountId: String, count: Int) {
        _dappsCount.withLock { $0[accountId] = count }
        if AccountStore.accountId == accountId {
            WalletCoreData.notify(event: .dappsCountUpdated(accountId: accountId))
        }
    }
}

public func getDappConnectionUniqueId(_ dapp: ApiDapp) -> String {
    dapp.sse?.appClientId.nilIfEmpty
        ?? dapp.wcPairingTopic?.nilIfEmpty
        ?? JSBRIDGE_IDENTIFIER
}
