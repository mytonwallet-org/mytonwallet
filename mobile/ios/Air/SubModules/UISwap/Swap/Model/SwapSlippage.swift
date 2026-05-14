import WalletContext

let DEFAULT_SLIPPAGE = BigInt(5_0)
let MAX_SLIPPAGE_VALUE = BigInt(50_0)
let SLIPPAGE_DECIMALS = 1

func normalizedSwapSlippage(_ draftSlippage: BigInt?) -> BigInt {
    if let draftSlippage, draftSlippage > BigInt(0), draftSlippage <= MAX_SLIPPAGE_VALUE {
        return draftSlippage
    }
    return DEFAULT_SLIPPAGE
}
