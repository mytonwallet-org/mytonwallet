import WalletCore
import WalletContext

struct SwapAccountSnapshot: Sendable {
    let account: MAccount
    let balances: [String: BigInt]
    let version: String?

    init(account: MAccount, balances: [String: BigInt]) {
        self.account = account
        self.balances = balances
        self.version = account.version
    }

    var id: String {
        account.id
    }

    var supportedChains: Set<ApiChain> {
        account.supportedChains
    }

    var crosschainIdentifyingFromAddress: String? {
        account.crosschainIdentifyingFromAddress
    }

    func getAddress(chain: ApiChain?) -> String? {
        account.getAddress(chain: chain)
    }

    func supports(chain: ApiChain?) -> Bool {
        account.supports(chain: chain)
    }

    func getNativeBalanceForEstimate(chain: ApiChain) -> String? {
        guard supports(chain: chain) else { return nil }
        let token = chain.nativeToken
        guard let balance = balances[token.slug] else { return nil }
        return balance == 0 || token.decimals == 0 ? balance.description : bigIntToDoubleString(balance, decimals: token.decimals)
    }
}
