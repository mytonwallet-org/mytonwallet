import Foundation

extension Api {
    public static func confirmWalletConnectPaySignTransaction(promiseId: String, data: [ApiSignedTransfer]) async throws {
        try await bridge.callApiVoid("confirmWalletConnectPaySignTransaction", promiseId, data)
    }

    public static func confirmWalletConnectPaySignData(promiseId: String, data: AnyEncodable) async throws {
        try await bridge.callApiVoid("confirmWalletConnectPaySignData", promiseId, data)
    }

    public static func completeWalletConnectPayDataCollection(promiseId: String) async throws {
        try await bridge.callApiVoid("completeWalletConnectPayDataCollection", promiseId)
    }

    public static func confirmWalletConnectPayOptionSelection(promiseId: String, optionId: String) async throws {
        try await bridge.callApiVoid("confirmWalletConnectPayOptionSelection", promiseId, optionId)
    }

    public static func refreshWalletConnectPayOptionSelection(paymentLink: String, accountId: String, promiseId: String) async throws {
        try await bridge.callApiVoid("refreshWalletConnectPayOptionSelection", paymentLink, accountId, promiseId)
    }

    public static func cancelWalletConnectPay(promiseId: String, reason: String?) async throws {
        try await bridge.callApiVoid("cancelWalletConnectPay", promiseId, reason)
    }
}
