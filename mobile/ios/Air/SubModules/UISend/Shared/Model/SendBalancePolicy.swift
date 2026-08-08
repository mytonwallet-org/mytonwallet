import WalletContext
import WalletCore

enum SendBalanceStatus: Equatable, Sendable {
    case unknown
    case sufficient
    case insufficientAmount
    case insufficientFee

    var isInsufficient: Bool {
        self == .insufficientAmount || self == .insufficientFee
    }
}

struct TokenSendBalanceEvaluation: Equatable, Sendable {
    let status: SendBalanceStatus
    let shouldShowFullFee: Bool
}

struct SendBalancePolicy {
    static func evaluate(
        tokenBalance: BigInt?,
        tokenSlug: String,
        isNativeToken: Bool,
        nativeTokenBalance: BigInt?,
        transferAmount: BigInt?,
        displayedFee: ExplainedTransferFee?,
        computationalFee: ExplainedTransferFee?,
        displayedDiesel: TokenSendDieselQuote?,
        computationalDiesel: TokenSendDieselQuote?,
        draftError: ApiAnyDisplayError?
    ) -> TokenSendBalanceEvaluation {
        let status = evaluate(
            tokenBalance: tokenBalance,
            tokenSlug: tokenSlug,
            isNativeToken: isNativeToken,
            nativeTokenBalance: nativeTokenBalance,
            transferAmount: transferAmount,
            explainedFee: computationalFee,
            diesel: computationalDiesel,
            draftError: draftError
        )
        let displayedStatus = evaluate(
            tokenBalance: tokenBalance,
            tokenSlug: tokenSlug,
            isNativeToken: isNativeToken,
            nativeTokenBalance: nativeTokenBalance,
            transferAmount: transferAmount,
            explainedFee: displayedFee,
            diesel: displayedDiesel,
            draftError: nil
        )
        return TokenSendBalanceEvaluation(
            status: status,
            shouldShowFullFee: displayedStatus == .insufficientFee
        )
    }

    static func evaluate(
        tokenBalance: BigInt?,
        tokenSlug: String,
        nativeTokenBalance: BigInt?,
        transferAmount: BigInt?,
        fullFee: MFee.FeeTerms?,
        canTransferFullBalance: Bool,
        draftError: ApiAnyDisplayError?
    ) -> SendBalanceStatus {
        guard let transferAmount, let tokenBalance else {
            return .unknown
        }
        guard transferAmount <= tokenBalance else {
            return .insufficientAmount
        }
        let maximumAmount = getMaxTransferAmount(.init(
            tokenBalance: tokenBalance,
            tokenSlug: tokenSlug,
            fullFee: fullFee,
            canTransferFullBalance: canTransferFullBalance
        ))
        if let maximumAmount, transferAmount > maximumAmount {
            return .insufficientFee
        }
        if draftError == .insufficientBalance {
            return .insufficientFee
        }

        // The web flow treats a missing fee as zero until the SDK returns a quote.
        guard let fullFee else {
            return .sufficient
        }
        guard let nativeTokenBalance else {
            return .unknown
        }

        let isSufficient = isBalanceSufficientForTransfer(.init(
            tokenBalance: tokenBalance,
            fullFee: fullFee,
            canTransferFullBalance: canTransferFullBalance,
            nativeTokenBalance: nativeTokenBalance,
            transferAmount: transferAmount
        ))
        return isSufficient == true ? .sufficient : .insufficientFee
    }

    private static func evaluate(
        tokenBalance: BigInt?,
        tokenSlug: String,
        isNativeToken: Bool,
        nativeTokenBalance: BigInt?,
        transferAmount: BigInt?,
        explainedFee: ExplainedTransferFee?,
        diesel: TokenSendDieselQuote?,
        draftError: ApiAnyDisplayError?
    ) -> SendBalanceStatus {
        guard let transferAmount, let tokenBalance else {
            return .unknown
        }
        guard transferAmount <= tokenBalance else {
            return .insufficientAmount
        }
        let fullFee = explainedFee?.fullFee
        let maximumAmount = getMaxTransferAmount(.init(
            tokenBalance: tokenBalance,
            tokenSlug: tokenSlug,
            fullFee: fullFee?.terms,
            canTransferFullBalance:
                explainedFee?.canTransferFullBalance ?? false
        ))
        if let maximumAmount, transferAmount > maximumAmount {
            return .insufficientFee
        }
        if draftError == .insufficientBalance {
            return .insufficientFee
        }

        guard let explainedFee, let fullFee else {
            return .sufficient
        }
        guard let nativeTokenBalance else {
            return .unknown
        }

        let isSufficient: Bool
        if isNativeToken,
           explainedFee.canTransferFullBalance,
           transferAmount == tokenBalance,
           let fullNativeFee = fullFee.nativeSum {
            isSufficient = fullNativeFee < nativeTokenBalance
        } else {
            let isFullFeeCovered =
                isBalanceSufficientForTransfer(.init(
                    tokenBalance: tokenBalance,
                    fullFee: fullFee.terms,
                    canTransferFullBalance:
                        explainedFee.canTransferFullBalance,
                    nativeTokenBalance: nativeTokenBalance,
                    transferAmount: transferAmount
                )) == true
            if explainedFee.isGasless,
               diesel?.status != .starsFee,
               let dieselAmount = diesel?.tokenAmount {
                isSufficient = isFullFeeCovered
                    && transferAmount + dieselAmount <= tokenBalance
            } else {
                isSufficient = isFullFeeCovered
            }
        }
        return isSufficient ? .sufficient : .insufficientFee
    }
}
