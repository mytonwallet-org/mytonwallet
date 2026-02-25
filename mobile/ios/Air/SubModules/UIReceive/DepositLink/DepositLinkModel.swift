//
//  DepositLinkModel.swift
//  AirAsFramework
//
//  Created by nikstar on 01.08.2025.
//

import SwiftUI
import UIComponents
import WalletCore
import WalletContext
import Perception
import SwiftNavigation

@MainActor
@Perceptible
final class DepositLinkModel: TokenSelectionVCDelegate {
    
    @PerceptionIgnored
    let nativeToken: ApiToken
    var chain: ApiChain { nativeToken.chain }
    var account: MAccount
    var tokenAmount: TokenAmount
    var comment: String = ""
    var url: String? = nil
    var amountFocused: Bool = false
    var switchedToBaseCurrency: Bool = false
    var baseCurrencyAmount: BigInt? = nil
    
    @PerceptionIgnored
    private var tokenAmountObservation: ObserveToken?
    @PerceptionIgnored
    private var urlObservation: ObserveToken?
    
    init(nativeToken: ApiToken) {
        self.account = AccountStore.account!
        self.nativeToken = nativeToken
        self.tokenAmount = TokenAmount(0, nativeToken)
        tokenAmount.optionalAmount = nil
        
        tokenAmountObservation = observe { [weak self] in
            guard let self else { return }
            baseCurrencyAmount = tokenAmount
                .convertTo(TokenStore.baseCurrency, exchangeRate: tokenAmount.token.price ?? 0.0)
                .amount
        }
        
        urlObservation = observe { [weak self, chain] in
            guard let self else { return }
            url = chain.formatTransferUrl?(
                account.getAddress(chain: chain)!,
                tokenAmount.amount.nilIfZero,
                comment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                tokenAmount.token.tokenAddress
            ) ?? ""
        }
    }
    
    func onTokenTapped() {
        let tokenSelectionVC = TokenSelectionVC(
            showMyAssets: true,
            title: "Select Token",
            delegate: self,
            isModal: true,
            onlySupportedChains: true
        )
        topViewController()?.present(tokenSelectionVC, animated: true)
    }
    
    func didSelect(token: MTokenBalance) {
        if let token = token.token {
            didSelect(token: token)
        }
    }
    
    func didSelect(token: ApiToken) {
        tokenAmount = tokenAmount.switchKeepingDecimalValue(newType: token)
        topViewController()?.dismiss(animated: true)
    }
}
