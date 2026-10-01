import WalletCore
import WalletContext

struct SwapEstimateInput: Equatable, Sendable {
    let accountId: String
    let selling: TokenAmount
    let buying: TokenAmount
    let inputSource: SwapSide
    let isMaxAmount: Bool
    let maxAmount: BigInt?
    let slippage: Double
    let previousNetworkFee: MDouble?
    let cexLabel: ApiSwapCexLabel?

    init(
        accountId: String,
        selling: TokenAmount,
        buying: TokenAmount,
        inputSource: SwapSide,
        isMaxAmount: Bool,
        maxAmount: BigInt?,
        slippage: Double,
        previousNetworkFee: MDouble? = nil,
        cexLabel: ApiSwapCexLabel? = nil
    ) {
        self.accountId = accountId
        self.selling = selling
        self.buying = buying
        self.inputSource = inputSource
        self.isMaxAmount = isMaxAmount
        self.maxAmount = maxAmount
        self.slippage = slippage
        self.previousNetworkFee = previousNetworkFee
        self.cexLabel = cexLabel
    }

    var inputAmount: BigInt {
        switch inputSource {
        case .selling:
            selling.amount
        case .buying:
            buying.amount
        }
    }

    func matchesCurrent(_ current: SwapEstimateInput?) -> Bool {
        guard let current else { return false }
        return accountId == current.accountId
            && selling.token.slug == current.selling.token.slug
            && buying.token.slug == current.buying.token.slug
            && inputSource == current.inputSource
            && isMaxAmount == current.isMaxAmount
            && (!isMaxAmount || maxAmount == current.maxAmount)
            && slippage == current.slippage
            && (isMaxAmount || inputAmount == current.inputAmount)
    }
}
