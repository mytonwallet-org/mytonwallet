import SwiftUI
import WalletCore

/// Compatibility boundary for the UI lab; live navigation presents the native controller.
public struct PerpsOperationView: UIViewControllerRepresentable {
    let store: PerpsStore
    let accountId: String
    let operationId: String
    let onWithdraw: () -> Void
    let onReceipt: () -> Void

    public init(store: PerpsStore, accountId: String, operationId: String, onWithdraw: @escaping () -> Void, onReceipt: @escaping () -> Void) {
        self.store = store
        self.accountId = accountId
        self.operationId = operationId
        self.onWithdraw = onWithdraw
        self.onReceipt = onReceipt
    }

    public func makeUIViewController(context: Context) -> PerpsOperationVC {
        PerpsOperationVC(store: store, accountId: accountId, operationId: operationId,
                         onWithdraw: onWithdraw, onReceipt: onReceipt)
    }

    public func updateUIViewController(_ uiViewController: PerpsOperationVC, context: Context) {}
}
