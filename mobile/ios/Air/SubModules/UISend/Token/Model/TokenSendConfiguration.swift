import WalletContext
import WalletCore

enum TokenSendMode: Equatable, Sendable {
    case send
    case sellToMoonpay
}

struct TokenSendConfiguration: Equatable, Sendable {
    let mode: TokenSendMode
    let initialAddress: String?
    let initialAmount: BigInt?
    let initialTokenSlug: String?
    let jettonAddress: String?
    let initialComment: String
    let binaryPayload: String?
    let stateInit: String?
}
