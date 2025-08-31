//
//  TransferHelpers.swift
//  MyTonWalletAir
//
//  Created by Sina on 12/20/24.
//

import WalletContext


public class TransferHelpers {
    private init() {}
    
    public struct ExplainedTransferFee {
        /** Whether the result implies paying the fee with a diesel */
        public let isGasless: Bool;
        /**
         * The fee that will be sent with the transfer. The wallet must have it on the balance to send the transfer.
         * Show this in the transfer form when the input amount is ≤ the balance, but the remaining balance can't cover the
         * full fee; show `realFee` otherwise. Undefined means that it's unknown.
         */
        public let fullFee: MFee?
        /**
         * The real fee (the full fee minus the excess). Undefined means that it's unknown. There is no need to fall back to
         * `fullFee` when `realFee` is undefined (because it's undefined too in this case).
         */
        public let realFee: MFee?
        /**
         * Whether the full token balance can be transferred despite the fee.
         * If yes, the fee will be taken from the transferred amount.
         */
        public let canTransferFullBalance: Bool
    };

    public static func shouldUseDiesel(input: MTransactionDraft) -> Bool {
        return input.diesel != nil && input.diesel?.status != .notAvailable
    }

    public static func explainApiTransferFee(chain: String, isNativeToken: Bool, input: MTransactionDraft) -> ExplainedTransferFee {
        return shouldUseDiesel(input: input) ? explainGaslessTransferFee(diesel: input.diesel!) : explainGasfullTransferFee(chain: chain,
                                                                                                                            isNativeToken: isNativeToken,
                                                                                                                            input: input)
    }
    
    // TODO: replace with normal impl without ?? 
    private static func explainGaslessTransferFee(diesel: MDiesel) -> ExplainedTransferFee {
        let isStarsDiesel = diesel.status == .starsFee
        let realFeeInDiesel = convertFee(amount: diesel.realFee, exampleFromAmount: diesel.nativeAmount, exampleToAmount: (isStarsDiesel ? diesel.starsAmount : diesel.tokenAmount) ?? 0);
        // Cover as much displayed real fee as possible with diesel, because in the excess it will return as the native token.
        let dieselRealFee = min(diesel.tokenAmount ?? 0, realFeeInDiesel);
        // Cover the remaining real fee with the native token.
        let nativeRealFee = convertFee(amount: realFeeInDiesel - dieselRealFee,
                                       exampleFromAmount: diesel.tokenAmount ?? 0,
                                       exampleToAmount: diesel.nativeAmount);

        return ExplainedTransferFee(
            isGasless: true,
            fullFee: MFee(
                precision: .lessThan,
                terms: .init(
                    token: diesel.tokenAmount,
                    native: diesel.remainingFee,
                    stars: diesel.starsAmount
                ),
                nativeSum: diesel.realFee
            ),
            realFee: MFee(
                precision: .approximate,
                terms: .init(token: isStarsDiesel ? nil : dieselRealFee,
                             native: nativeRealFee,
                             stars: isStarsDiesel ? dieselRealFee : nil),
                nativeSum: diesel.realFee
            ),
            canTransferFullBalance: false
        )
    }
    
    private static func explainGasfullTransferFee(chain: String, isNativeToken: Bool, input: MTransactionDraft) -> ExplainedTransferFee {
        let fullFee = MFee(precision: input.realFee == input.fee ? .exact : .lessThan,
                           terms: .init(token: nil,
                                        native: input.fee,
                                        stars: nil),
                           nativeSum: input.fee ?? 0)

        return ExplainedTransferFee(isGasless: false,
                                    fullFee: input.fee != nil ? fullFee : nil,
                                    realFee: input.realFee != nil ? MFee(precision: input.realFee == input.fee ? .exact : .approximate,
                                                                         terms: .init(token: nil,
                                                                                      native: input.realFee,
                                                                                      stars: nil),
                                                                         nativeSum: input.fee ?? 0) : fullFee,
                                    canTransferFullBalance: chain == "ton" && isNativeToken)
    }
    
    private static func convertFee(amount: BigInt,
                                   exampleFromAmount: BigInt,
                                   exampleToAmount: BigInt) -> BigInt {
        if exampleFromAmount == 0 {
            return 0
        }
        return amount * exampleToAmount / exampleFromAmount
    }

    public static func getMaxTransferAmount(tokenBalance: BigInt?,
                                            isNativeToken: Bool,
                                            fullFee: MFee.FeeTerms?,
                                            canTransferFullBalance: Bool) -> BigInt? {
        guard let tokenBalance, tokenBalance > 0 else {
            return nil
        }

        // Returning the full balance when the fee is unknown for a better UX
        if canTransferFullBalance || fullFee == nil {
            return tokenBalance
        }
        
        var fee = fullFee?.token ?? 0
        if isNativeToken {
            fee += fullFee?.native ?? 0
        }
        return max(tokenBalance - fee, 0)
    }
}
