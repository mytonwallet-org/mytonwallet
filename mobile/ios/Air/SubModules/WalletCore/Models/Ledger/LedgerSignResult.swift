
import WalletContext


public struct LedgerSignResult: Equatable, Hashable, Codable, Sendable {
    public var signedTransfer: ApiSignedTransfer
    public var pendingTransferId: String

    public init(signedTransfer: ApiSignedTransfer, pendingTransferId: String) {
        self.signedTransfer = signedTransfer
        self.pendingTransferId = pendingTransferId
    }
}
