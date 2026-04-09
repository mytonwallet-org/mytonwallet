import WalletCore
import WalletContext

struct OnchainSwapLateInit {
    let isEnoughNative: Bool
    let isDiesel: Bool

    static func calculate(
        selling: TokenAmount,
        balances: [String: BigInt],
        networkFee: Double?
    ) -> OnchainSwapLateInit {
        let tokenInChain = selling.token.chain
        let nativeUserTokenIn = selling.token.isOnChain == true && tokenInChain.isSupported
            ? TokenStore.tokens[tokenInChain.nativeToken.slug]
            : nil
        let networkFeeData = FeeEstimationHelpers.networkFeeBigInt(
            sellToken: selling.token,
            swapType: .onChain,
            networkFee: networkFee
        )
        let totalNativeAmount = (networkFeeData?.fee ?? 0) + ((networkFeeData?.isNativeIn == true) ? selling.amount : 0)
        let nativeBalance = balances[nativeUserTokenIn?.slug ?? ""] ?? 0
        let isEnoughNative = nativeBalance >= totalNativeAmount
        let isDiesel = !isEnoughNative && DIESEL_TOKENS.contains(selling.token.tokenAddress ?? "")

        return OnchainSwapLateInit(
            isEnoughNative: isEnoughNative,
            isDiesel: isDiesel
        )
    }
}
