import Foundation
import WalletContext

private let log = Log("Api+Mfa")

extension Api {
    public static func fetchMfaRequest(hash: String) async throws -> ApiMfaRequest {
        do {
            return try await bridge.callApi("fetchMfaRequest", hash, decoding: ApiMfaRequest.self)
        } catch {
            log.error("fetchMfaRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func fetchInstallMfaRequest(reqId: String) async throws -> ApiInstallMfaRequest {
        do {
            return try await bridge.callApi("fetchInstallMfaRequest", reqId, decoding: ApiInstallMfaRequest.self)
        } catch {
            log.error("fetchInstallMfaRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func publishInstallMfaRequest(accountId: String) async throws -> ApiMfaRequestCreated {
        do {
            return try await bridge.callApi("publishInstallMfaRequest", accountId, decoding: ApiMfaRequestCreated.self)
        } catch {
            log.error("publishInstallMfaRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func installMfaFromRequest(
        accountId: String,
        user: AccountMfa.User,
        password: String?
    ) async throws -> String {
        do {
            return try await bridge.callApi("installMfaFromRequest", accountId, user, password, decoding: String.self)
        } catch {
            log.error("installMfaFromRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func publishRemoveMfaRequest(
        accountId: String,
        password: String?
    ) async throws -> ApiMfaRequestCreated {
        do {
            return try await bridge.callApi("publishRemoveMfaRequest", accountId, password, decoding: ApiMfaRequestCreated.self)
        } catch {
            log.error("publishRemoveMfaRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func confirmMfaRemovalRequest(accountId: String) async throws {
        do {
            try await bridge.callApiVoid("confirmMfaRemovalRequest", accountId)
        } catch {
            log.error("confirmMfaRemovalRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func createDappConnectMfaRequest(accountId: String, password: String?) async throws -> ApiMfaProtectedResult {
        do {
            return try await bridge.callApi("createDappConnectMfaRequest", accountId, password, decoding: ApiMfaProtectedResult.self)
        } catch {
            log.error("createDappConnectMfaRequest failed: \(error, .public)")
            throw error
        }
    }

    public static func refreshMfaState(accountId: String, password: String?) async throws -> ApiRefreshMfaStateResult {
        do {
            let result = try await bridge.callApi("refreshMfaState", accountId, password, decoding: ApiRefreshMfaStateResult.self)
            log.info("[mfa] refreshMfaState \(result.mfa != nil ? "set" : "delete", .public) changed: \(result.changed, .public)")
            return result
        } catch {
            log.error("refreshMfaState failed: \(error, .public)")
            throw error
        }
    }
}

public struct ApiMfaRequestCreated: Decodable, Sendable {
    public let reqId: String
}

public struct ApiMfaRequest: Decodable, Sendable {
    public let payload: String
    public let signature: String
    public let isConfirmed: Bool
    public let txHash: String
}

public struct ApiInstallMfaRequest: Decodable, Sendable {
    public let address: String
    public let user: AccountMfa.User?
}

public struct ApiRefreshMfaStateResult: Decodable, Sendable {
    public let changed: Bool
    public let mfa: AccountMfa?
}
