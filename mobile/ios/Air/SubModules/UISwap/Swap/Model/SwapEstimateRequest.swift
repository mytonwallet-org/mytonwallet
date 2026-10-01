import WalletContext
import WalletCore

enum SwapEstimateAmount: Equatable, Sendable {
    /// The user typed this amount on the input side.
    case exact(BigInt)
    /// The user chose Max. The backend computes the effective amount, so
    /// the request keys on the balance: the computed amount written back
    /// into the form cannot move the request, while a balance change does.
    case max(balance: BigInt?)
}

/// The estimate's identity: user intent only. The estimated opposite-side
/// amount and the backend-adjusted maximum are outputs — they are written
/// back into the form but never into this request, so applying an estimate
/// cannot trigger another one.
struct SwapEstimateRequest: Equatable, Sendable {
    let accountId: String
    let sellingSlug: String
    let buyingSlug: String
    let side: SwapSide
    let amount: SwapEstimateAmount
    let slippage: Double
}

extension SwapEstimateRequest {
    @MainActor static func derive(
        accountId: String,
        input: SwapInputModel,
        isValidPair: Bool,
        slippage: Double
    ) -> SwapEstimateRequest? {
        guard isValidPair, let selling = input.sellingToken, let buying = input.buyingToken else { return nil }
        let side: SwapSide = input.buyingAmountInputDisabled
            ? .selling
            : input.inputSource
        let amount: SwapEstimateAmount
        switch side {
        case .selling:
            if input.isUsingMax {
                amount = .max(balance: input.tokenBalance)
            } else {
                guard let value = input.sellingAmount, value > 0 else { return nil }
                amount = .exact(value)
            }
        case .buying:
            guard let value = input.buyingAmount, value > 0 else { return nil }
            amount = .exact(value)
        }
        return SwapEstimateRequest(
            accountId: accountId,
            sellingSlug: selling.slug,
            buyingSlug: buying.slug,
            side: side,
            amount: amount,
            slippage: slippage
        )
    }
}
