
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Perception
import Dependencies

enum SendDappViewOrPlaceholderContent {
    case placeholder(TonConnectPlaceholder)
    case sendDapp(SendDappContentView)
}

struct SendDappViewOrPlaceholder: View {
    
    var content: SendDappViewOrPlaceholderContent
    
    var body: some View {
        switch content {
        case .placeholder(let view):
            view
                .transition(.opacity.animation(.default))
        case .sendDapp(let view):
            view
                .transition(.opacity.animation(.default))
        }
    }
}

struct SendDappContentView: View {
    
    var accountContext: AccountContext
    var request: ApiUpdate.DappSendTransactions
    var operationChain: ApiChain
    var onShowDetail: (ApiDappTransfer) -> ()
    
    var transactionsCount: Int { request.transactions.count }
    
    @Dependency(\.tokenStore) private var tokenStore
    
    var body: some View {
        WithPerceptionTracking {
            InsetList {
                DappHeaderView(
                    dapp: request.dapp,
                    accountContext: accountContext,
                )
                
                if request.combinedInfo.isDangerous {
                    SendDappWarningView()
                        .padding(.horizontal, 16)
                }
                
                if request.shouldHideTransfers != true {
                    totalAmountSection
                    
                    transfersSection
                }
                
                previewSection
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 80)
            }
        }
    }
    
    @ViewBuilder
    var totalAmountSection: some View {
        if transactionsCount > 1 {
            InsetSection {
                TotalAmountRow(info: request.combinedInfo)
                    .padding(.vertical, -1)
            } header: {
                Text(lang("Total Amount"))
            }
        }
    }
    
    var transfersSection: some View {
        InsetSection {
            ForEach(request.transactions, id: \.self) { tx in
                TransferRow(transfer: tx, chain: operationChain, action: onShowDetail)
            }
        } header: {
            Text(lang("transfer", arg1: transactionsCount))
        }
    }
    
    @ViewBuilder
    var previewSection: some View {
        if let emulation = request.emulation {
            InsetSection {
                ForEach(emulation.activities) { activity in
                    WithPerceptionTracking {
                        WPreviewActivityCell(.init(activity: activity, accountContext: accountContext, tokenStore: tokenStore))
                    }
                }
            } header: {
                let preview = Text(lang("Preview"))
                let warning = Text(Image(systemName: "exclamationmark.circle.fill"))
                    .foregroundColor(Color.orange)
                Text("\(preview) \(warning)")
                    .imageScale(.medium)
                    .overlay(alignment: .trailing) {
                        Button {
                            topWViewController()?.showTip(title: lang("Preview"), wide: false) {
                                Text(langMd("$preview_not_guaranteed"))
                                    .multilineTextAlignment(.center)
                            }
                        } label: {
                            Color.clear.contentShape(.rect)
                        }
                        .frame(width: 44, height: 44)
                        .offset(x: 10)
                    }
                
            }
        } else {
            InsetSection {
                Text(lang("Preview is currently unavailable."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .font(.system(size: 13))
            }
        }
    }
}
