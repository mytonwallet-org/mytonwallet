
import Foundation
import WalletContext

public let DappsStore = _DappsStore.shared

public final class _DappsStore {
    
    public static let shared = _DappsStore()
    
    private let _dappsCount: UnfairLock<[String: Int]> = .init(initialState: [:])
    public var dappsCount: Int? {
        if let accountId = AccountStore.accountId {
            return _dappsCount.withLock { $0[accountId] }
        }
        return nil
    }
    
    public func updateDappCount() {
        guard let accountId = AccountStore.accountId else { return }
        Task {
            do {
                let dapps = try await Api.getDapps(accountId: accountId)
                _dappsCount.withLock { $0[accountId] = dapps.count }
                if AccountStore.accountId == accountId {
                    WalletCoreData.notify(event: .dappsCountUpdated(accountId: accountId))
                }
            } catch {
                Log.api.error("\(error, .public)")
            }
            
        }
    }
    
    public func deleteDapp(dapp: ApiDapp) async throws {
        guard let accountId = AccountStore.accountId else { return }
        let uniqueId = getDappConnectionUniqueId(dapp)
        _ = try await Api.deleteDapp(accountId: accountId, url: dapp.url, uniqueId: uniqueId, dontNotifyDapp: nil)
        updateDappCount()
    }

    public func deleteAllDapps(accountId: String) async throws {
        try await Api.deleteAllDapps(accountId: accountId)
        _dappsCount.withLock { $0[accountId] = 0 }
        WalletCoreData.notify(event: .dappsCountUpdated(accountId: accountId))
    }
}

public func getDappConnectionUniqueId(_ dapp: ApiDapp) -> String {
    dapp.sse?.appClientId ?? JSBRIDGE_IDENTIFIER
}
