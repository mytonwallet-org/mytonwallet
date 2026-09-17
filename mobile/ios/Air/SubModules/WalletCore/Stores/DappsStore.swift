
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
        let dapps = try await Self.deleteAndVerify(accountId: accountId, dapp: dapp) {
            _ = try await Api.deleteDapp(accountId: accountId, url: dapp.url, uniqueId: uniqueId, dontNotifyDapp: nil)
        } load: {
            try await Api.getDapps(accountId: accountId)
        }
        updateDappCount(accountId: accountId, count: dapps.count)
        return dapps
    }

    @discardableResult
    public func deleteAllDapps(accountId: String) async throws -> [ApiDapp] {
        let dapps = try await Self.deleteAndVerify(accountId: accountId, dapp: nil) {
            try await Api.deleteAllDapps(accountId: accountId)
        } load: {
            try await Api.getDapps(accountId: accountId)
        }
        updateDappCount(accountId: accountId, count: 0)
        return dapps
    }

    static func deleteAndVerify(
        accountId: String,
        dapp: ApiDapp?,
        delete: () async throws -> Void,
        load: () async throws -> [ApiDapp]
    ) async throws -> [ApiDapp] {
        let uniqueId = dapp.map(getDappConnectionUniqueId)
        let context = "accountId=\(accountId) url=\(dapp?.url ?? "all") uniqueId=\(uniqueId ?? "all")"
        Log.api.info("dapp deletion start \(context, .public)")
        var deletionError: (any Error)?
        do {
            try await delete()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            deletionError = error
            let message = (error as? SdkError)?.backendMessage ?? error.localizedDescription
            Log.api.fault("dapp deletion failed phase=delete \(context, .public) error=\(message, .public)")
        }

        let dapps: [ApiDapp]
        do {
            dapps = try await load()
        } catch {
            let message = (error as? SdkError)?.backendMessage ?? error.localizedDescription
            Log.api.fault("dapp deletion failed phase=readBack \(context, .public) error=\(message, .public)")
            throw error
        }
        let remains = dapp.map { target in
            dapps.contains { $0.url == target.url && getDappConnectionUniqueId($0) == uniqueId }
        } ?? !dapps.isEmpty
        guard !remains else {
            Log.api.fault("dapp deletion failed phase=verify \(context, .public) remainingCount=\(dapps.count, .public)")
            throw deletionError ?? DisplayError(text: lang("Unexpected error"))
        }
        if deletionError != nil {
            Log.api.info("dapp deletion recovered after verification \(context, .public)")
        } else {
            Log.api.info("dapp deletion verified \(context, .public)")
        }
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
