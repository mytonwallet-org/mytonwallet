import ContextMenuKit
import Dependencies
import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct TokenSendComposeView: View {
    let model: TokenSendModel
    let onTokenSelect: () -> Void

    @State private var isAmountFocused = false

    var body: some View {
        WithPerceptionTracking {
            InsetList {
                RecipientAddressSection(
                    model: model.recipient,
                    validationState: model.recipientValidationState,
                    onPasteAction: handleAddressPaste
                )
                if !model.recipient.isFocused {
                    TokenSendFormSections(
                        model: model,
                        isAmountFocused: $isAmountFocused,
                        onTokenSelect: onTokenSelect
                    )
                    .transition(
                        .opacity.combined(with: .offset(y: 20))
                    )
                }
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: bottomSpacerHeight)
                    .allowsHitTesting(false)
            }
            .animation(.default, value: model.recipient.isFocused)
            .contentShape(.rect)
            .onTapGesture {
                endEditing()
            }
        }
    }

    private var bottomSpacerHeight: CGFloat {
        model.recipient.isFocused ? 0 : 200
    }

    private func handleAddressPaste() -> Bool {
        guard intentHasNoAmount else { return false }
        model.recipient.isFocused = false
        DispatchQueue.main.async {
            isAmountFocused = true
        }
        return true
    }

    private var intentHasNoAmount: Bool {
        model.amount == nil
            && model.amountInBaseCurrency == nil
    }
}

private struct TokenSendFormSections: View {
    let model: TokenSendModel
    @Binding var isAmountFocused: Bool
    let onTokenSelect: () -> Void

    var body: some View {
        WithPerceptionTracking {
            if model.shouldShowDomainScamWarning {
                WarningView(
                    text: SendWarningContent.domainScamMarkdown,
                    kind: .error
                )
                .padding(.horizontal, 16)
            }
            if model.shouldShowMultisigWarning {
                MultisigWalletWarning()
            }
            TokenSendAmountSection(
                model: model,
                isFocused: $isAmountFocused,
                onTokenSelect: onTokenSelect
            )
            if model.shouldShowGasWarning {
                WarningView(
                    text: SendWarningContent.seedPhraseScamMarkdown,
                    kind: .warning
                )
                .padding(.horizontal, 16)
            }
            TokenSendPayloadSection(model: model)
        }
    }
}

private struct TokenSendAmountSection: View {
    let model: TokenSendModel
    @Binding var isFocused: Bool
    let onTokenSelect: () -> Void

    var body: some View {
        WithPerceptionTracking {
            TokenAmountEntrySection(
                amount: model.amount,
                onAmountChange: model.setTokenAmount,
                token: model.token,
                balance: model.maxToSend?.amount,
                insufficientFunds: model.hasInsufficientAmount,
                isFeeError: model.hasInsufficientFee,
                amountInBaseCurrency:
                    model.amountInBaseCurrency,
                onBaseCurrencyAmountChange:
                    model.setBaseCurrencyAmount,
                switchedToBaseCurrencyInput:
                    model.switchedToBaseCurrencyInput,
                onInputCurrencyChange:
                    model.setBaseCurrencyInputEnabled,
                fee: model.showingFee,
                explainedFee: model.explainedFee,
                isFocused: $isFocused,
                onTokenSelect: onTokenSelect,
                onUseAll: selectAll
            )
        }
    }

    private func selectAll() {
        model.selectAll()
        endEditing()
    }
}

private struct TokenSendPayloadSection: View {
    let model: TokenSendModel

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            if model.isPayloadSectionVisible {
                SendPayloadInputSection(
                    isCommentRequired: model.isCommentRequired,
                    isEncryptedMessageAvailable:
                        model.isEncryptedMessageAvailable,
                    binaryPayload: model.binaryPayload,
                    stateInit: model.configuration.stateInit,
                    isMessageEncrypted: $model.isMessageEncrypted,
                    comment: $model.comment
                )
            }
        }
    }
}

struct TokenSendComposeTitleView: View {
    let model: TokenSendModel
    let onSellTapped: () -> Void
    let onMultisendTapped: () -> Void

    var body: some View {
        WithPerceptionTracking {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text(lang("Send"))
                    Image.airBundle("ArrowUpDownSmall")
                        .opacity(0.5)
                }
                .fixedSize(horizontal: true, vertical: false)
                .textStyle(.supportingEmphasized)
                .foregroundColor(.air.primaryLabel)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.air.secondaryLabel.opacity(0.12))
                .clipShape(Capsule())
                .contextMenuSource {
                    titleMenu
                }

                if shouldShowSell {
                    Button(action: onSellTapped) {
                        Text(lang("Sell"))
                            .textStyle(.supportingEmphasized)
                            .foregroundStyle(Color.air.secondaryLabel)
                    }
                }
            }
        }
    }

    private var shouldShowSell: Bool {
        model.isSellSupported
            && !ConfigStore.shared.shouldRestrictSell
    }

    private var titleMenu: ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                .action(ContextMenuAction(
                    title: lang("Multisend"),
                    icon: .airBundle("MenuMultisend26"),
                    handler: onMultisendTapped
                )),
            ]),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 180)
        )
    }
}
