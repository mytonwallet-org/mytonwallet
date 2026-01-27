
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

enum SignDataViewOrPlaceholderContent {
    case placeholder(TonConnectPlaceholder)
    case signData(SignDataView)
}

struct SignDataViewOrPlaceholder: View {
    
    var content: SignDataViewOrPlaceholderContent
    
    var body: some View {
        switch content {
        case .placeholder(let view):
            view
                .transition(.opacity.animation(.default))
        case .signData(let view):
            view
                .transition(.opacity.animation(.default))
        }
    }
}

struct SignDataView: View {

    var update: ApiUpdate.DappSignData
    var accountContext: AccountContext
    var onConfirm: () -> ()
    var onCancel: () -> ()
    
    @Namespace private var ns

    var body: some View {
        InsetList {
            DappHeaderView(
                dapp: update.dapp,
                accountContext: accountContext,
            )
            .padding(.bottom, 16)
            switch update.payloadToSign {
            case .text(let text):
                makeText(payload: text)
            case .binary(let binary):
                makeBinary(payload: binary)
            case .cell(let cell):
                makeCell(payload: cell)
            }

        }
        .coordinateSpace(name: ns)
        .safeAreaInset(edge: .bottom) {
            buttons
        }
    }
    
    @ViewBuilder
    func makeText(payload: SignDataPayloadText) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: payload.text)
                    .font17h22()
            }
        } header: {
            Text(lang("Message"))
        }
    }

    @ViewBuilder
    func makeBinary(payload: SignDataPayloadBinary) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: payload.bytes)
                    .font17h22()
            }
        } header: {
            Text(lang("Binary Data"))
        }
        warningView
    }

    @ViewBuilder
    func makeCell(payload: SignDataPayloadCell) -> some View {
        InsetSection {
            InsetCell {
                Text(verbatim: payload.schema)
                    .font17h22()
            }
        } header: {
            Text(lang("Cell Schema"))
        }
        InsetSection {
            InsetCell {
                Text(verbatim: payload.cell)
                    .font17h22()
            }
        } header: {
            Text(lang("Cell Data"))
        }
        warningView
    }

    var warningView: some View {
        WarningView(
            text: lang("The binary data content is unclear. Sign it only if you trust the service."),
            kind: .warning,
        )
        .padding(.horizontal, 16)
    }

    var buttons: some View {

        HStack(spacing: 16) {
            Button(action: onCancel) {
                Text(lang("Cancel"))
            }
            .buttonStyle(.airSecondary)
            Button(action: onConfirm) {
                Text(lang("Sign"))
            }
            .buttonStyle(.airPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}
