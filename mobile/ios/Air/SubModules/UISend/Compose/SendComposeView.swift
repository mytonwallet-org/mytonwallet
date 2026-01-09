

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import Dependencies

public struct SendComposeView: View {
    
    let model: SendModel
    var isSensitiveDataHidden: Bool
            
    @State private var amountFocused: Bool = false
    
    public var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            InsetList {
                RecipientAddressSection(model: model.addressInput)
                if !model.addressInput.isFocused {
                    Group {
                        AmountSection(model: self.model, focused: $amountFocused)
                        NftSection(model: self.model)
                        CommentOrMemoSection(model: self.model, commentIsEnrypted: $model.isMessageEncrypted, commentOrMemo: $model.comment)
                    }
                    .transition(.opacity.combined(with: .offset(y: 20)))
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 60)
            }
            .animation(.default, value: model.addressInput.isFocused)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 140)
            }
            .contentShape(.rect)
            .onTapGesture {
                endEditing()
            }
            .navigationTitle(Text(lang("Send")))
        }
    }
    
    func onAddressSubmit() {
        amountFocused = true
    }
}

// MARK: -

fileprivate struct AmountSection: View {
    
    let model: SendModel
    @Binding var focused: Bool
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            if model.nftSendMode == nil {
                TokenAmountEntrySection(
                    amount: $model.amount,
                    token: model.token,
                    balance: model.maxToSend?.amount,
                    insufficientFunds: model.insufficientFunds,
                    amountInBaseCurrency: $model.amountInBaseCurrency,
                    switchedToBaseCurrencyInput: $model.switchedToBaseCurrencyInput,
                    fee: model.showingFee,
                    explainedFee: model.explainedTransferFee,
                    isFocused: $focused,
                    onTokenSelect: onTokenTapped,
                    onUseAll: model.onUseAll
                )
                .onChange(of: model.amount) { amount in
                    if let amount, model.switchedToBaseCurrencyInput == false {
                        model.updateBaseCurrencyAmount(amount)
                    }
                }
                .onChange(of: model.amountInBaseCurrency) { baseCurrencyAmount in
                    if let baseCurrencyAmount, model.switchedToBaseCurrencyInput == true {
                        model.updateAmountFromBaseCurrency(baseCurrencyAmount)
                    }
                }
            }
        }
    }
    
    func onTokenTapped() {
        let walletTokens = model.$account.balances.map { (key: String, value: BigInt) in
            MTokenBalance(tokenSlug: key, balance: value, isStaking: false)
        }
        let vc = SendCurrencyVC(accountId: model.account.id, isMultichain: model.account.isMultichain, walletTokens: walletTokens, currentTokenSlug: model.token.slug, onSelect: { token in })
        vc.onSelect = { [weak model] newToken in
            model?.onTokenSelected(newToken: newToken)
            topViewController()?.dismiss(animated: true)
        }
        let nav = WNavigationController(rootViewController: vc)
        topViewController()?.present(nav, animated: true)
    }
}


// MARK: -


internal struct NftSection: View {

    let model: SendModel

    @Dependency(\.tokenStore) private var tokenStore
    
    var body: some View {
        WithPerceptionTracking {
            if let nfts = model.nfts, nfts.count > 0 {
                InsetSection {
                    ForEach(nfts, id: \.id) { nft in
                        NftPreviewRow(nft: nft)
                    }
                } header: {
                    Text("^[\(nfts.count) Assets](inflect: true)")
                } footer: {
                    FeeView(token: model.token, nativeToken: tokenStore.getNativeToken(chain: model.token.chainValue), fee: model.showingFee, explainedTransferFee: nil, includeLabel: true)
                }
            }
        }
    }
}

// MARK: -


private struct CommentOrMemoSection: View {
    
    let model: SendModel

    @Binding var commentIsEnrypted: Bool
    @Binding var commentOrMemo: String

    @FocusState private var isFocused: Bool

    var body: some View {
        WithPerceptionTracking {
            if model.binaryPayload?.nilIfEmpty != nil {
                binaryPayloadSection
            } else {
                commentSection
            }
        }
    }
    
    @ViewBuilder
    var commentSection: some View {
        InsetSection {
            InsetCell {
                TextField(
                    model.isCommentRequired ? lang("Required") : lang("Optional"),
                    text: $commentOrMemo,
                    axis: .vertical
                )
                .writingToolsDisabled()
                .focused($isFocused)
            }
            .contentShape(.rect)
            .onTapGesture {
                isFocused = true
            }
        } header: {
            if model.isEncryptedMessageAvailable {
                Menu {
                    Button(action: {
                        commentIsEnrypted = false
                    }) {
                        Text(lang("Comment or Memo"))
                            .textCase(nil)
                    }
                    
                    Button(action: {
                        commentIsEnrypted = true
                    }) {
                        Text(lang("Encrypted Message"))
                            .textCase(nil)
                    }
                    
                } label: {
                    HStack(spacing: 2) {
                        Text(commentIsEnrypted == false ? lang("Comment or Memo") : lang("Encrypted Message"))
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                            .scaleEffect(0.8)
                            .offset(y: 1.333)
                    }
                    .padding(.trailing, 16)
                    .contentShape(.rect)
                    .foregroundStyle(.secondary)
                    .tint(.primary)
                    .padding(.vertical, 2)
                }
                .padding(.vertical, -2)
            } else {
                Text(lang("Comment or Memo"))
            }
        } footer: {}
    }
    
    @ViewBuilder
    var binaryPayloadSection: some View {
        if let binaryPayload = model.binaryPayload {
            InsetSection {
                InsetExpandableCell(content: binaryPayload)
            } header: {
                Text(lang("Signing Data"))
            } footer: {
                WarningView(text: "Signing custom data is very dangerous. Use it only if you trust the source of it.")
                    .padding(.vertical, 11)
                    .padding(.horizontal, -16)
            }
        }
    }
}
