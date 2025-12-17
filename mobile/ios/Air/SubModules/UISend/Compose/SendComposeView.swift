

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

public struct SendComposeView: View {
    
    @ObservedObject var model: SendModel
    var isSensitiveDataHidden: Bool
            
    @State private var addressFocused: Bool = false
    @State private var amountFocused: Bool = false
    
    public var body: some View {
        InsetList {
            ToSection(isFocused: $addressFocused, onSubmit: onAddressSubmit)
            AmountSection(focused: $amountFocused)
            NftSection()
            CommentOrMemoSection(commentIsEnrypted: $model.isMessageEncrypted, commentOrMemo: $model.comment)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 60)
                }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 140)
        }
        .contentShape(.rect)
        .onTapGesture {
            model.onBackgroundTapped()
        }

        .navigationTitle(Text(lang("Send")))
        .environmentObject(model)

        .onChange(of: addressFocused) { focus in
            model.validateAddressOrDomain(nil, tokenSlug: nil)
        }
        .onAppear {
            if model.addressOrDomain != "" {
                model.validateAddressOrDomain(model.addressOrDomain, tokenSlug: model.tokenSlug)
            }
        }
    }
    
    func onAddressSubmit() {
        amountFocused = true
    }
}


// MARK: -


fileprivate struct ToSection: View {
    
    @Binding var isFocused: Bool
    var onSubmit: () -> ()
    
    @EnvironmentObject private var model: SendModel
    
    private var showName: Bool {
        if model.draftData.address == model.addressOrDomain,
           let name = model.draftData.transactionDraft?.addressName,
           !name.isEmpty,
           name != model.draftData.address
        {
            return true
        }
        return false
    }
    private var showResolvedAddress: Bool {
        if model.draftData.address == model.addressOrDomain,
           model.draftData.transactionDraft?.resolvedAddress != model.draftData.address {
            return true
        }
        return false
    }

    var body: some View {
        InsetSection {
            InsetCell {
                HStack {
                    AddressTextField(
                        value: $model.addressOrDomain,
                        isFocused: $isFocused,
                        onNext: {
                            onSubmit()
                        }
                    )
                    .offset(y: 1)
                    .background(alignment: .leading) {
                        if model.addressOrDomain.isEmpty {
                            Text(lang("Wallet address or domain"))
                                .foregroundStyle(Color(UIColor.placeholderText))
                        }
                    }
                    
                    if model.addressOrDomain.isEmpty {
                        HStack(spacing: 12) {
                            Button(action: { model.onAddressPastePressed() }) {
                                Text(lang("Paste"))
                            }
                            Button(action: { model.onScanPressed() }) {
                                Image("ScanIcon", bundle: AirBundle)
                                    .renderingMode(.template)
                            }
                        }
                        .offset(x: 4)
                        .padding(.vertical, -1)
                    } else {
                        Button(action: { model.addressOrDomain = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .tint(Color(WTheme.secondaryLabel))
                                .scaleEffect(0.9)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
            .contentShape(.rect)
            .onTapGesture {
                isFocused = true
            }
        } header: {
            Text(lang("Recipient Address"))
        } footer: {
            footer
        }
        .onAppear {
            if model.addressOrDomain.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    isFocused = true
                }
            }
        }
    }
    
    @ViewBuilder
    var footer: some View {
        if let name = model.toAddressDraft?.addressName, showName {
            Text(verbatim: name)
        } else if let resolvedAddress = model.resolvedAddress, showResolvedAddress {
            Text(AttributedString(formatAddressAttributed(
                resolvedAddress,
                startEnd: true,
                primaryFont: .systemFont(ofSize: 13, weight: .regular),
                secondaryFont: .systemFont(ofSize: 13, weight: .regular),
                primaryColor: WTheme.secondaryLabel,
                secondaryColor: WTheme.secondaryLabel
            )))
        }

    }
}


// MARK: -

fileprivate struct AmountSection: View {
    
    @Binding var focused: Bool
    
    @EnvironmentObject private var model: SendModel
    
    var body: some View {
        if model.nftSendMode == nil {
            TokenAmountEntrySection(
                amount: $model.amount,
                token: model.token,
                balance: model.maxToSend,
                insufficientFunds: model.insufficientFunds,
                amountInBaseCurrency: $model.amountInBaseCurrency,
                switchedToBaseCurrencyInput: $model.switchedToBaseCurrencyInput,
                fee: model.showingFee,
                explainedFee: model.explainedTransferFee,
                isFocused: $focused,
                onTokenSelect: model.onTokenTapped,
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


// MARK: -


internal struct NftSection: View {

    @EnvironmentObject private var model: SendModel

    var body: some View {
        if let nfts = model.nfts, nfts.count > 0 {
            InsetSection {
                ForEach(nfts, id: \.id) { nft in
                    NftPreviewRow(nft: nft)
                }
            } header: {
                Text("^[\(nfts.count) Assets](inflect: true)")
            } footer: {
                if let token = model.token, let nativeToken = token.availableChain?.nativeToken {
                    FeeView(token: token, nativeToken: nativeToken, fee: model.showingFee, explainedTransferFee: nil, includeLabel: true)
                }
            }
        }
    }
}

// MARK: -


private struct CommentOrMemoSection: View {

    @Binding var commentIsEnrypted: Bool
    @Binding var commentOrMemo: String
    
    @EnvironmentObject private var model: SendModel

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
                        model.validateAddressOrDomain(nil, tokenSlug: nil)
                    }) {
                        Text(lang("Comment or Memo"))
                            .textCase(nil)
                    }
                    
                    Button(action: {
                        commentIsEnrypted = true
                        model.validateAddressOrDomain(nil, tokenSlug: nil)
                    }) {
                        Text(lang("Encrypted Message"))
                            .textCase(nil)
                    }
                    
                } label: {
                    HStack(spacing: 2) {
                        Text(commentIsEnrypted == false ? lang("Comment or Memo") : lang("Encrypted Message"))
                        Image(systemName: "chevron.down")
                            .scaleEffect(0.8)
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
