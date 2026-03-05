
import WalletContext

public struct ApiLedgerWalletInfo: Codable, Sendable {
    public var balance: BigInt
    public var wallet: ApiAnyChainWallet
}
