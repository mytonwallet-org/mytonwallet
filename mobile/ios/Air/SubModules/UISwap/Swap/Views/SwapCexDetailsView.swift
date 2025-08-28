//
//  SwapDetailsView.swift
//  UISwap
//
//  Created by Sina on 5/10/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Combine


struct SwapCexDetailsView: View {

    @ObservedObject var swapVM: SwapVM
    @ObservedObject var selectorsVM: SwapSelectorsVM
    
    var sellingToken: ApiToken { selectorsVM.sellingToken }
    var buyingToken: ApiToken { selectorsVM.buyingToken }
    var exchangeRate: SwapRate? { displayExchangeRate }
    var swapEstimate: MSwapEstimate? { swapVM.cexEstimate }
    var displayEstimate: MSwapEstimate? { swapEstimate }

    var displayExchangeRate: SwapRate? {
        if let est = swapEstimate {
            return ExchangeRateHelpers.getSwapRate(
                fromAmount: est.fromAmount,
                toAmount: est.toAmount,
                fromToken: sellingToken,
                toToken: buyingToken
            )
        }
        return nil
    }

    @State private var fee: TransferHelpers.ExplainedTransferFee?
    @State private var isExpanded = false
    
    var body: some View {
        
        InsetSection(horizontalPadding: 0) {
            header
                
            if isExpanded {
                pricePerCoinRow
                blockchainFeeRow
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: isExpanded ? nil : 44, alignment: .top)
        .clipShape(.rect(cornerRadius: 12))
        .frame(height: 400, alignment: .top)
        .tint(Color(WTheme.tint))
        .animation(.spring(duration: isExpanded ? 0.45 : 0.3), value: isExpanded)
        .task(id: selectorsVM.sellingTokenAmount) {
            await fetchEstimate()
        }
    }
    
    func fetchEstimate() async {
        do {
            if let amnt = selectorsVM.sellingTokenAmount, let account = AccountStore.account {
                let token = amnt.type
                let chain = token.chainValue
                let draft: MTransactionDraft = try await Api.checkTransactionDraft(
                    chain: chain.rawValue,
                    options: .init(
                        accountId: account.id,
                        toAddress: chain == .ton ? (AccountStore.account?.tonAddress ?? "") : "TW2LXSebZ7Br1zHaiA2W1zRojDkDwjGmpw",
                        amount: BigInt(1),
                        tokenAddress: token.tokenAddress,
                        data: nil,
                        stateInit: nil,
                        shouldEncrypt: nil,
                        isBase64Data: nil,
                        forwardAmount: nil,
                        allowGasless: nil
                    )
                )
                let fee = TransferHelpers.explainApiTransferFee(chain: chain.rawValue, isNativeToken: token.isNative, input: draft)
                self.fee = fee
            }
        } catch {
            print(error)
        }
    }
    
    var header: some View {
        Button(action: { isExpanded.toggle() }) {
            InsetCell {
                HStack {
                    Text(lang("Swap Details"))
                        .textCase(.uppercase)
                    Spacer()
                    Image.airBundle("RightArrowIcon")
                        .renderingMode(.template)
                        .rotationEffect(isExpanded ? .radians(-0.5 * .pi) : .radians(0.5 * .pi))
                }
                .font13()
                .tint(Color(WTheme.secondaryLabel))
                .foregroundStyle(Color(WTheme.secondaryLabel))
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(InsetButtonStyle())
    }
    
    @ViewBuilder
    var pricePerCoinRow: some View {
        
        if let exchangeRate = exchangeRate, displayEstimate != nil {
            InsetCell {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(lang("Price per") + " 1 " + exchangeRate.toToken.symbol)
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                        Spacer(minLength: 4)
                        Text("~\(formatAmountText(amount: exchangeRate.price, decimalsCount: min(6, sellingToken.decimals))) \(exchangeRate.fromToken.symbol)")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var blockchainFeeRow: some View {
        if let amnt = selectorsVM.sellingTokenAmount, let fee = self.fee, let nativeToken = TokenStore.tokens[amnt.token.chainValue.tokenSlug] {
            InsetDetailCell {
                Text(lang("Blockchain Fee"))
                    .foregroundStyle(Color(WTheme.secondaryLabel))
            } value: {
                FeeView(
                    token: amnt.type,
                    nativeToken: nativeToken,
                    fee: fee.realFee,
                    explainedTransferFee: nil,
                    includeLabel: false
                )
            }
        }
        
        // TODO: Swap fee
//        if let displayEstimate {
//            InsetDetailCell {
//                Text(lang("Blockchain Fee"))
//                    .foregroundStyle(Color(WTheme.secondaryLabel))
//            } value: {
//                let fee = displayEstimate.swapFee
//                let token = sellingToken.chain == "ton" ?  "TON" : "TRX"
//                Text("~\(formatAmountText(amount: fee, currency: token, decimalsCount: 6))")
//            }
//        }
    }
}
