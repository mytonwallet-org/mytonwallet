import Foundation
import WalletCoreTypes

extension Api {
    public static func fetchWalletPermissions(accountId: String, chain: ApiChain) async throws -> [ApiWalletPermission] {
        try await bridge.callApi("fetchWalletPermissions", accountId, chain, decoding: [ApiWalletPermission].self)
    }

    public static func fetchWalletPlugins(accountId: String) async throws -> [ApiTonPlugin] {
        try await bridge.callApi("fetchWalletPlugins", accountId, decoding: [ApiTonPlugin].self)
    }

    public static func revokeWalletPermission(
        chain: ApiChain,
        options: ApiRevokeWalletPermissionOptions
    ) async throws -> ApiRevokeWalletPermissionResult {
        try await bridge.callApi("revokeWalletPermission", chain, options, decoding: ApiRevokeWalletPermissionResult.self)
    }
}
