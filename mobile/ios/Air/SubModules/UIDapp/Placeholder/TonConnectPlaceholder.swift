
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct TonConnectPlaceholder: View {

    var account: MAccount?
    var connectionType: ApiDappConnectionType
    
    var body: some View {
        InsetList {
            TonConnectHeaderPlaceholder(account: account, redacted: connectionType == .connect)
                .padding(.bottom, 16)
            
            switch connectionType {
            case .connect:
                textPlaceholder
            case .sendTransaction:
                textPlaceholder
                textPlaceholder
            case .signData:
                textPlaceholder
            }
        }
        .safeAreaInset(edge: .bottom) {
            buttons
                .disabled(true)
        }
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    var textPlaceholder: some View {
        InsetSection {
            InsetCell {
                Text("This is a placeholder")
                    .font17h22()
            }
        } header: {
            Text(lang("Message"))
        }
        .redacted(reason: .placeholder)
    }
    
    var buttons: some View {

        HStack(spacing: 16) {
            switch connectionType {
            case .connect:
                Button(action: {}) {
                    Text(lang("Connect Wallet"))
                }
                .buttonStyle(.airPrimary)
            case .sendTransaction:
                Button(action: {}) {
                    Text(lang("Cancel"))
                }
                .buttonStyle(.airSecondary)
                Button(action: {}) {
                    Text(lang("Send"))
                }
                .buttonStyle(.airPrimary)
            case .signData:
                Button(action: {}) {
                    Text(lang("Cancel"))
                }
                .buttonStyle(.airSecondary)
                Button(action: {}) {
                    Text(lang("Sign"))
                }
                .buttonStyle(.airPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
}

struct TonConnectHeaderPlaceholder: View {
    
    var account: MAccount?
    var redacted: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 8) {
                title
                transfer
            }
        }
    }
    
    var icon: some View {
        Rectangle()
            .fill(Color(WTheme.groupedItem))
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 16))
    }

    var title: some View {
        Text(lang("Confirm Action"))
            .font(.system(size: 24, weight: .semibold))
            .redacted(reason: redacted ? .placeholder : [])
    }
    
    @ViewBuilder
    var transfer: some View {
        let wallet = Text(displayName)
            .foregroundColor(.secondary)
            .redacted(reason: account == nil ? .placeholder : [])
        let chevron = Text("›")
            .foregroundColor(.secondary)
        let dapp = Text("Dapp Name")
            .foregroundColor(Color(WTheme.tint))
            .redacted(reason: .placeholder)
        HStack(spacing: 4) {
            wallet
            chevron
            dapp
        }
    }
    
    var displayName: String { account?.displayName ?? "Account" }
}
