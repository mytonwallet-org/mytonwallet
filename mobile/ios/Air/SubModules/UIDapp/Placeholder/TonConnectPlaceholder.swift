
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct TonConnectPlaceholder: View {

    var account: MAccount?
    var connectionType: ApiDappConnectionType
    var extraBottomPadding: CGFloat = 16
    
    var body: some View {
        Group {
            switch connectionType {
            case .connect:
                connectView
            case .sendTransaction:
                sendTransactionView
                    .safeAreaInset(edge: .bottom) {
                        buttons
                            .padding(.top, 16)
                    }
            case .signData:
                 signDataView
                    .safeAreaInset(edge: .bottom) {
                        buttons
                            .padding(.top, 16)
                    }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var sendTransactionView: some View {
        InsetList {
            HeaderView2(account: account)
            
            InsetSection {
                InsetCell(horizontalPadding: 12) {
                    ActivityPlaceholderRow(balance: .none)
                }
            } header: {
                SectionHeaderPlaceholder()
            }

            InsetSection {
                InsetCell(horizontalPadding: 12) {
                    ActivityPlaceholderRow(balance: .double)
                    PlaceholderView(size: .init(width: 155, height: 16))
                }
            } header: {
                SectionHeaderPlaceholder()
            }
        }
    }
    
    @ViewBuilder
    private var connectView: some View {
        VStack(spacing: 24) {
            ConnectHeaderView(account: account)
                .padding(.top, 40)
                .padding(.bottom, 16)

            InsetSection {
                InsetCell(horizontalPadding: 12) {
                    ActivityPlaceholderRow(balance: .single)
                }
            } header: {
                SectionHeaderPlaceholder()
            }

            buttons
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var signDataView: some View {
        InsetList {
            HeaderView2(account: account)
            
            InsetSection {
                InsetCell {
                    PlaceholderView(size: .init(width: 200, height: 12))
                }
            } header: {
                SectionHeaderPlaceholder()
            }
        }
    }
            
    private var buttons: some View {
        HStack(spacing: 16) {
            switch connectionType {
            case .connect:
                Button(action: {}) {
                    Text(lang("Connect Wallet"))
                }
                .buttonStyle(.airPrimary)
                .padding(.horizontal, 14)
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
        .padding(.bottom, extraBottomPadding)
        .disabled(true)
    }
}

private struct HeaderView2: View {
    var account: MAccount?
    
    var body: some View {
        InsetSection {
            InsetCell(horizontalPadding: 0, verticalPadding: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let accountName = account?.displayName {
                            Text(accountName)
                                .foregroundColor(.secondary)
                                .font(.system(size: 16, weight: .medium))
                        } else {
                            PlaceholderView(size: .init(width: 80, height: 16))
                        }
                        PlaceholderView(size: .init(width: 60, height: 14))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        PlaceholderView(size: .init(width: 80, height: 16))
                        PlaceholderView(size: .init(width: 60, height: 14))
                    }
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.air.groupedBackground)
                        .frame(width: 40, height: 40)
                }
                .padding(.trailing, 12)
                .padding(.leading, 16)
                .padding(.vertical, 14)
            }
        }
    }
}

private struct SectionHeaderPlaceholder: View {
    var body: some View {
        let height: CGFloat = IOS_26_MODE_ENABLED ? 17 : 13
        PlaceholderView(size: .init(width: 55, height: height), tint: .onDarkSurface)
    }
}

private struct ActivityPlaceholderRow: View {
    enum BalanceMode {
        case none, single, double
    }
    
    var balance: BalanceMode
        
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.air.groupedBackground)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 6) {
                PlaceholderView(size: .init(width: 80, height: 16))
                PlaceholderView(size: .init(width: 60, height: 12))
            }
            
            switch balance {
            case .none:
                EmptyView()
            case .single:
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    PlaceholderView(size: .init(width: 80, height: 16))
                }
            case .double:
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    PlaceholderView(size: .init(width: 80, height: 16))
                    PlaceholderView(size: .init(width: 50, height: 12))
                }
            }
        }
    }
}

private struct PlaceholderView: View {
    enum Tint {
        case onLightSurface
        case onDarkSurface
    }
    
    let size: CGSize
    let tint: Tint
    
    init(size: CGSize, tint: Tint = Tint.onLightSurface) {
        self.size = size
        self.tint = tint
    }

    var body: some View {
        let color: Color = switch tint {
        case .onLightSurface: .air.groupedBackground
        case .onDarkSurface: .air.groupedItem
        }
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(color)
            .frame(width: size.width, height: size.height)
    }
}

private struct ConnectHeaderView: View {
    
    var account: MAccount?
    
    var body: some View {
        VStack(spacing: 16) {
            icon
            VStack(spacing: 8) {
                title
                transfer
            }
        }
    }
    
    private var icon: some View {
        Rectangle()
            .fill(Color.air.groupedItem)
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var title: some View {
        PlaceholderView(size: .init(width: 165, height: 24), tint: .onDarkSurface)
    }
    
    @ViewBuilder
    private var transfer: some View {
        let wallet = Text(displayName)
            .foregroundColor(.secondary)
            .redacted(reason: account == nil ? .placeholder : [])
        let chevron = Text("›")
            .foregroundColor(.secondary)
        let dapp = PlaceholderView(size: .init(width: 55, height: 17), tint: .onDarkSurface)
        HStack(spacing: 4) {
            wallet
            chevron
            dapp
        }
    }
    
    private var displayName: String { account?.displayName ?? "Account" }
}

#if DEBUG
@available(iOS 18, *)
private struct TonConnectPlaceholderPreview: View {
    var account: MAccount
    var connectionType: ApiDappConnectionType

    var body: some View {
        ScrollView {
            TonConnectPlaceholder(account: account, connectionType: connectionType)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(Color.air.sheetBackground)
    }
}

@available(iOS 18, *)
#Preview("Connect") {
    @Previewable @AccountContext(source: .current) var account: MAccount
    TonConnectPlaceholderPreview(account: account, connectionType: .connect)
}

@available(iOS 18, *)
#Preview("Send Transaction") {
    @Previewable @AccountContext(source: .current) var account: MAccount
    TonConnectPlaceholderPreview(account: account, connectionType: .sendTransaction)
}

@available(iOS 18, *)
#Preview("Sign Data") {
    @Previewable @AccountContext(source: .current) var account: MAccount
    TonConnectPlaceholderPreview(account: account, connectionType: .signData)
}
#endif
