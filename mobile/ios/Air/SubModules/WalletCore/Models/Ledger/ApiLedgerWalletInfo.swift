
import WalletContext

public struct ApiLedgerWalletInfo: Codable {
    public var balance: BigInt
    public var wallet: ApiAnyChainWallet
}
