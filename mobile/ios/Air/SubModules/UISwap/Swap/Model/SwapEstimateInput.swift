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

    init(
        accountId: String,
        selling: TokenAmount,
        buying: TokenAmount,
        inputSource: SwapSide,
        isMaxAmount: Bool,
        maxAmount: BigInt?,
        slippage: Double,
        previousNetworkFee: MDouble? = nil
    ) {
        self.accountId = accountId
        self.selling = selling
        self.buying = buying
        self.inputSource = inputSource
        self.isMaxAmount = isMaxAmount
        self.maxAmount = maxAmount
        self.slippage = slippage
        self.previousNetworkFee = previousNetworkFee
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

struct SwapEstimateGate: Equatable {
    private(set) var inFlightInput: SwapEstimateInput?
    private var needsFollowUp = false

    var isInFlight: Bool {
        inFlightInput != nil
    }

    mutating func start(_ input: SwapEstimateInput) -> Bool {
        guard inFlightInput == nil else {
            needsFollowUp = true
            return false
        }
        inFlightInput = input
        return true
    }

    mutating func finish() -> Bool {
        inFlightInput = nil
        let shouldRunFollowUp = needsFollowUp
        needsFollowUp = false
        return shouldRunFollowUp
    }

    mutating func cancelFollowUp() {
        needsFollowUp = false
    }

    mutating func reset() {
        inFlightInput = nil
        needsFollowUp = false
    }
}
