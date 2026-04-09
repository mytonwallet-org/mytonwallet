import SwiftUI
import ContextMenuKit
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
            let bottomSpacerHeight: CGFloat = model.addressInput.isFocused ? 0 : 200
            InsetList {
                if model.mode.isNftRelated {
                    NftSection(model: self.model)
                }
                RecipientAddressSection(model: model.addressInput, onPasteAction: onAddressPaste)
                if !model.addressInput.isFocused {
                    Group {
                        if model.shouldShowDomainScamWarning {
                            WarningView(
                                text: lang("$domain_like_scam_warning", arg1: "[\(lang("$help_center_prepositional"))](\(model.domainScamHelpUrl.absoluteString))"),
                                kind: .error
                            )
                            .padding(.horizontal, 16)
                        }
                        if model.shouldShowMultisigWarning {
                            MultisigWalletWarning()
                        }
                        if !model.mode.isNftRelated {
                            AmountSection(model: self.model, focused: $amountFocused)
                        }
                        if model.shouldShowGasWarning {
                            WarningView(
                                text: lang("$seed_phrase_scam_warning", arg1: "[\(lang("$help_center_prepositional"))](\(model.seedPhraseScamHelpUrl.absoluteString))"),
                                kind: .warning
                            )
                            .padding(.horizontal, 16)
                        }
                        CommentOrMemoSection(model: self.model, commentIsEncrypted: $model.isMessageEncrypted, commentOrMemo: $model.comment)
                    }
                    .transition(.opacity.combined(with: .offset(y: 20)))
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: bottomSpacerHeight)
                    .allowsHitTesting(false)
            }
            .animation(.default, value: model.addressInput.isFocused)
            .contentShape(.rect)
            .onTapGesture {
                endEditing()
            }
        }
    }
    
    func onAddressSubmit() {
        amountFocused = true
    }
    
    func onAddressPaste() -> Bool {
        guard !model.mode.isNftRelated, model.amount == nil, model.amountInBaseCurrency == nil else {
            return false
        }
        
        model.addressInput.isFocused = false
        DispatchQueue.main.async {
            amountFocused = true
        }
        return true
    }
}

// MARK: -

struct SendComposeTitleView: View {
    var onSellTapped: () -> Void
    var onMultisendTapped: () -> Void

    private let titleFont = Font.system(size: 14, weight: .medium)

    var body: some View {
        
        let showSell = !ConfigStore.shared.shouldRestrictSell
        
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(lang("Send"))
                Image.airBundle("ArrowUpDownSmall").opacity(0.5)
            }
            .fixedSize(horizontal: true, vertical: false)
            .font(titleFont)
            .foregroundColor(.air.primaryLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.air.secondaryLabel.opacity(0.12))
            .clipShape(Capsule())
            .contextMenuSource {
                makeTitleMenuConfiguration()
            }
            
            if showSell {
                Button(action: onSellTapped) {
                    Text(lang("Sell"))
                        .font(titleFont)
                        .foregroundStyle(Color.air.secondaryLabel)
                }
            }
        }
    }
    
    private func makeTitleMenuConfiguration() -> ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(
                    ContextMenuAction(
                        title: lang("Multisend"),
                        icon: .airBundle("MenuMultisend26"),
                        handler: {
                            onMultisendTapped()
                        }
                    )
                )
            ]),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 180.0)
        )
    }
}

// MARK: -

fileprivate struct AmountSection: View {
    
    let model: SendModel
    @Binding var focused: Bool
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            if !model.mode.isNftRelated {
                TokenAmountEntrySection(
                    amount: $model.amount,
                    token: model.token,
                    balance: model.maxToSend?.amount,
                    insufficientFunds: model.insufficientFunds,
                    amountInBaseCurrency: $model.amountInBaseCurrency,
                    switchedToBaseCurrencyInput: $model.switchedToBaseCurrencyInput,
                    fee: model.showingFee,
                    explainedFee: model.explainedFee,
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


private struct CommentOrMemoSection: View {
    
    let model: SendModel

    @Binding var commentIsEncrypted: Bool
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
            let commentTitle = lang("Comment or Memo")
            let encryptedTitle = lang("Encrypted Message")
            
            if model.isEncryptedMessageAvailable {
                let chevron = Text(Image(systemName: "chevron.down"))
                                   .font(.system(size: 11, weight: .semibold))
                                   .baselineOffset(1)
                
                Text("\(commentIsEncrypted ? encryptedTitle : commentTitle) \(chevron)")
                    .contextMenuSource {
                        makeCommentMenuConfiguration(commentTitle: commentTitle, encryptedTitle: encryptedTitle)
                    }
            } else {
                Text(commentTitle)
            }
        } footer: {}
    }

    private func makeCommentMenuConfiguration(
        commentTitle: String,
        encryptedTitle: String
    ) -> ContextMenuConfiguration {
        let items: [ContextMenuItem] = [
            .action(
                ContextMenuAction(
                    title: commentTitle,
                    icon: commentIsEncrypted ? .placeholder : (.system("checkmark") ?? .placeholder),
                    handler: {
                        commentIsEncrypted = false
                    }
                )
            ),
            .action(
                ContextMenuAction(
                    title: encryptedTitle,
                    icon: commentIsEncrypted ? (.system("checkmark") ?? .placeholder) : .placeholder,
                    handler: {
                        commentIsEncrypted = true
                    }
                )
            ),
        ]

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 180.0, maxWidth: 300.0)
        )
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
