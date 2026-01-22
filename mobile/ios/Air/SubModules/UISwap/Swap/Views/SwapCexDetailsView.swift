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
import Perception

private let log = Log("SwapCexDetailsView")

struct SwapCexDetailsView: View {

    var swapVM: SwapVM
    var selectorsVM: SwapSelectorsVM
    
    var sellingToken: ApiToken { selectorsVM.sellingToken }
    var buyingToken: ApiToken { selectorsVM.buyingToken }
    var exchangeRate: SwapRate? { displayExchangeRate }
    var swapEstimate: ApiSwapCexEstimateResponse? { swapVM.cexEstimate }
    var displayEstimate: ApiSwapCexEstimateResponse? { swapEstimate }

    var displayExchangeRate: SwapRate? {
        if let est = swapEstimate {
            return ExchangeRateHelpers.getSwapRate(
                fromAmount: est.fromAmount.value,
                toAmount: est.toAmount.value,
                fromToken: sellingToken,
                toToken: buyingToken
            )
        }
        return nil
    }

    @State private var fee: TransferHelpers.ExplainedTransferFee?
    @State private var isExpanded = false
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection(horizontalPadding: 0) {
                header
                    
                if isExpanded {
                    pricePerCoinRow
                    blockchainFeeRow
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: isExpanded ? nil : 44, alignment: .top)
            .frame(height: 400, alignment: .top)
            .tint(Color(WTheme.tint))
            .animation(.spring(duration: isExpanded ? 0.45 : 0.3), value: isExpanded)
            .task(id: selectorsVM.sellingTokenAmount) {
                await fetchEstimate()
            }
        }
    }
    
    func fetchEstimate() async {
        do {
            if let amnt = selectorsVM.sellingTokenAmount, let tokenAddress = amnt.token.tokenAddress {
                let token = amnt.token
                let chain = token.chainValue
                let dieselEstimate = try await Api.fetchEstimateDiesel(accountId: swapVM.account.id, chain: token.chainValue, tokenAddress: tokenAddress)
                if let dieselEstimate {
                    let fee = TransferHelpers.explainDieselEstimate(chain: chain.rawValue, isNativeToken: token.isNative, dieselEstimate: dieselEstimate)
                    self.fee = fee
                }
            }
        } catch {
            log.error("\(error)")
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
                        Text(lang("Exchange Rate"))
                            .foregroundStyle(Color(WTheme.secondaryLabel))
                        Spacer(minLength: 4)
                        let priceAmount = DecimalAmount.fromDouble(exchangeRate.price, exchangeRate.fromToken)
                        Text("\(exchangeRate.toToken.symbol) ≈ \(priceAmount.formatted(.none, maxDecimals: min(6, sellingToken.decimals)))")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var blockchainFeeRow: some View {
        if let amnt = selectorsVM.sellingTokenAmount, let fee = self.fee, let nativeToken = TokenStore.tokens[amnt.token.nativeTokenSlug] {
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
    }
}
