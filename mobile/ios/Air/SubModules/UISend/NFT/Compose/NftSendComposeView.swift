import Perception
import SwiftUI
import UIComponents
import WalletContext

struct NftSendComposeView: View {
    let model: NftSendModel

    var body: some View {
        WithPerceptionTracking {
            InsetList {
                NftPreviewSection(nfts: model.configuration.nfts)
                RecipientAddressSection(
                    model: model.recipient,
                    validationState: model.recipient.validationState(
                        validatedRecipient:
                            model.currentValidatedDraft?.recipient,
                        showsIncompatibleError: true
                    )
                )
                if !model.recipient.isFocused {
                    NftSendFormSections(model: model)
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
}

private struct NftSendFormSections: View {
    let model: NftSendModel

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
            NftSendPayloadSection(model: model)
        }
    }
}

private struct NftSendPayloadSection: View {
    let model: NftSendModel

    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            if model.isTransferPayloadAvailable {
                SendPayloadInputSection(
                    isCommentRequired: model.isCommentRequired,
                    isEncryptedMessageAvailable: false,
                    binaryPayload: nil,
                    stateInit: nil,
                    isMessageEncrypted: .constant(false),
                    comment: $model.comment
                )
            }
        }
    }
}
