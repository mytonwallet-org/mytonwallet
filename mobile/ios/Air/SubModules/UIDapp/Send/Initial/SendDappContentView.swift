
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext


struct SendDappContentView: View {
    
    var account: MAccount
    var request: MDappSendTransactions
    var onShowDetail: (ApiDappTransfer) -> ()
    var onScroll: (CGFloat) -> ()
    
    var transactionsCount: Int { request.transactions.count }
    
    @Namespace var ns
    
    var body: some View {
        InsetList {
            SendDappHeaderView(
                dapp: request.dapp,
                transactionsCount: transactionsCount,
                account: account,
                isDangerous: request.combinedInfo.isDangerous
            )
            .scrollPosition(ns: ns, offset: -88, callback: onScroll)
            
            if request.combinedInfo.isDangerous {
                SendDappWarningView()
                    .padding(.horizontal, 16)
            }
            
            totalAmountSection
            
            transfersSection
            
            previewSection
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 80)
        }
        .coordinateSpace(name: ns)
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
                TransferRow(transfer: tx, action: onShowDetail)
            }
        } header: {
            Text(lang("%lld transfer", arg1: transactionsCount))
        }
    }
    
    @ViewBuilder
    var previewSection: some View {
        if let emulation = request.emulation {
            InsetSection {
                ForEach(emulation.activities) { activity in
                    WPreviewActivityCell(activity: activity)
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
