import WalletContext
import WalletCore

struct SendValidatedRecipient: Equatable, Sendable {
    let resolvedAddress: String?
    let addressName: String?
    let isScam: Bool
    let error: ApiAnyDisplayError?
}
