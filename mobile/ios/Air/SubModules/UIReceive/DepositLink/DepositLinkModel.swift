//
//  DepositLinkModel.swift
//  AirAsFramework
//
//  Created by nikstar on 01.08.2025.
//

import Combine
import SwiftUI
import UIComponents
import WalletCore
import WalletContext

final class DepositLinkModel: ObservableObject, TokenSelectionVCDelegate {
    
    let nativeToken: ApiToken
    var chain: ApiChain { nativeToken.chainValue }
    @Published var account: MAccount
    @Published var tokenAmount: TokenAmount
    @Published var comment: String = ""
    @Published var url: String? = nil
    @Published var amountFocused: Bool = false
    @Published var switchedToBaseCurrency: Bool = false
    @Published var baseCurrencyAmount: BigInt? = nil
    
    var cancellables: Set<AnyCancellable> = []
    
    init(nativeToken: ApiToken) {
        self.account = AccountStore.account!
        self.nativeToken = nativeToken
        self.tokenAmount = TokenAmount(0, nativeToken)
        tokenAmount.optionalAmount = nil

        $tokenAmount
            .sink { tokenAmount in
                self.baseCurrencyAmount = tokenAmount.convertTo(TokenStore.baseCurrency, exchangeRate: tokenAmount.token.price ?? 0.0).amount
            }
            .store(in: &cancellables)
        
        $tokenAmount
            .combineLatest($comment, $account)
            .map { [chain] (tokenAmount, comment, account) -> String in
                chain.formatTransferUrl?(
                    account.addressByChain[chain.rawValue]!,
                    tokenAmount.amount.nilIfZero,
                    comment.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    tokenAmount.token.tokenAddress,
                ) ?? ""
            }
            .sink { [weak self] url in
                self?.url = url
            }
            .store(in: &cancellables)
    }
    
    func onTokenTapped() {
        let tokenSelectionVC = TokenSelectionVC(
            showMyAssets: true,
            title: "Select Token",
            delegate: self,
            isModal: true,
            onlyTonChain: true
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
