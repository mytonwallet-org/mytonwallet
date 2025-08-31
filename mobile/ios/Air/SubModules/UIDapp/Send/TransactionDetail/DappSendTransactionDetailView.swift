
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext


struct DappSendTransactionDetailView: View {
    
    var message: ApiDappTransfer
    var onScroll: (CGFloat) -> ()
    
    @Namespace var ns
    
    var isScam: Bool { message.isScam == true }
    
    var body: some View {
        InsetList(topPadding: 0, spacing: 16) {
            if isScam {
                Image.airBundle("ScamBadge")
                    .scaleEffect(1.2)
                    .offset(y: -3)
                    .padding(.bottom, 2)
            }
            
            InsetSection {
                InsetCell {
                    TappableAddressFull(address: message.toAddress)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(lang("Receiving address"))
            }
            .scrollPosition(ns: ns, offset: isScam ? 32 : 0, callback: onScroll)

            InsetSection {
                TransactionAmountRow(transfer: message)
            } header: {
                Text(lang("Amount"))
            }
            
            InsetSection {
                TransactionFeeRow(transfer: message)
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
                    Text(lang("StateInit"))
                }
            }
            
            if message.isDangerous {
                SendDappWarningView()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .coordinateSpace(name: ns)
        .navigationBarInset(68)
    }
}
