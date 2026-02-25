
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


struct DappSendTransactionDetailView: View {
    
    var accountContext: AccountContext
    var message: ApiDappTransfer
    var chain: ApiChain
    
    var isScam: Bool { message.isScam == true }
    
    var body: some View {
        InsetList(topPadding: 0, spacing: 16) {
            if isScam {
                Image.airBundle("ScamBadge")
                    .scaleEffect(1.2)
                    .offset(y: -3)
                    .padding(.bottom, 2)
            }
            
            if !message.toAddress.isEmpty {
                InsetSection {
                    InsetCell {
                        TappableAddressFull(accountContext: accountContext, model: .init(chain: chain, apiAddress: message.toAddress))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text(lang("Receiving address"))
                }
            }

            InsetSection {
                TransactionAmountRow(transfer: message, chain: chain)
            } header: {
                Text(lang("Amount"))
            }
            
            InsetSection {
                TransactionFeeRow(transfer: message, chain: chain)
            } header: {
                Text(lang("Fee"))
            }
            
            if let payload = message.rawPayload {
                InsetSection {
                    InsetExpandableCell(content: payload)
                } header: {
                    Text(lang("Payload"))
                }
            }
            
            if let stateInit = message.stateInit {
                InsetSection {
                    InsetExpandableCell(content: stateInit)
                } header: {
                    Text("StateInit")
                }
            }
            
            if message.isDangerous {
                SendDappWarningView()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .navigationBarInset(12)
    }
}
