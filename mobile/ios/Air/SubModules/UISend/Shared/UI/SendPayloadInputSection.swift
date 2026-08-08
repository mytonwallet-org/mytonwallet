import ContextMenuKit
import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct SendPayloadInputSection: View {
    let isCommentRequired: Bool
    let isEncryptedMessageAvailable: Bool
    let binaryPayload: String?
    let stateInit: String?

    @Binding var isMessageEncrypted: Bool
    @Binding var comment: String

    @FocusState private var isFocused: Bool

    var body: some View {
        let signingData = SendSigningData(
            binaryPayload: binaryPayload,
            stateInit: stateInit
        )
        if signingData.isPresent {
            SendSigningDataSection(signingData: signingData)
        } else {
            SendCommentInputSection(
                isCommentRequired: isCommentRequired,
                isEncryptedMessageAvailable: isEncryptedMessageAvailable,
                isMessageEncrypted: $isMessageEncrypted,
                comment: $comment,
                isFocused: $isFocused
            )
        }
    }
}

private struct SendCommentInputSection: View {
    let isCommentRequired: Bool
    let isEncryptedMessageAvailable: Bool

    @Binding var isMessageEncrypted: Bool
    @Binding var comment: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        InsetSection {
            InsetCell {
                TextField(
                    isCommentRequired ? lang("Required") : lang("Optional"),
                    text: $comment,
                    axis: .vertical
                )
                .writingToolsDisabled()
                .focused(isFocused)
            }
            .contentShape(.rect)
            .onTapGesture {
                isFocused.wrappedValue = true
            }
        } header: {
            SendCommentInputTitle(
                isEncryptedMessageAvailable:
                    isEncryptedMessageAvailable,
                isMessageEncrypted: $isMessageEncrypted
            )
        } footer: {}
    }
}

private struct SendCommentInputTitle: View {
    let isEncryptedMessageAvailable: Bool

    @Binding var isMessageEncrypted: Bool

    var body: some View {
        if isEncryptedMessageAvailable {
            Text(
                "\(selectedTitle) \(Text(Image(systemName: "chevron.down")).textStyle(.caption2Strong, content: .technical).baselineOffset(1))"
            )
            .contextMenuSource {
                menuConfiguration
            }
        } else {
            Text(commentTitle)
        }
    }

    private var commentTitle: String {
        lang("Comment or Memo")
    }

    private var encryptedTitle: String {
        lang("Encrypted Message")
    }

    private var selectedTitle: String {
        isMessageEncrypted ? encryptedTitle : commentTitle
    }

    private var menuConfiguration: ContextMenuConfiguration {
        ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [
                menuItem(
                    title: commentTitle,
                    isSelected: !isMessageEncrypted,
                    action: { isMessageEncrypted = false }
                ),
                menuItem(
                    title: encryptedTitle,
                    isSelected: isMessageEncrypted,
                    action: { isMessageEncrypted = true }
                ),
            ]),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 180, maxWidth: 300)
        )
    }

    private func menuItem(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> ContextMenuItem {
        .action(ContextMenuAction(
            title: title,
            icon: isSelected
                ? (.system("checkmark") ?? .placeholder)
                : .placeholder,
            handler: action
        ))
    }
}

struct SendSigningDataSection: View {
    let signingData: SendSigningData

    var body: some View {
        if let binaryPayload = signingData.binaryPayload {
            InsetSection {
                InsetExpandableCell(content: binaryPayload)
            } header: {
                Text(lang("Signing Data"))
            } footer: {
                if signingData.stateInit == nil {
                    signatureWarning
                }
            }
        }
        if let stateInit = signingData.stateInit {
            InsetSection {
                InsetExpandableCell(content: stateInit)
            } header: {
                Text(lang("Contract Initialization Data"))
            } footer: {
                signatureWarning
            }
        }
    }

    private var signatureWarning: some View {
        WarningView(text: lang("$signature_warning"))
            .padding(.vertical, 11)
            .padding(.horizontal, -16)
    }
}
