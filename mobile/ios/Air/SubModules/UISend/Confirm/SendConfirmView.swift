

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext


struct SendConfirmView: View {
    
    @ObservedObject var model: SendModel
    var navigationBarInset: CGFloat
    var onScrollPositionChange: (CGFloat) -> ()
    
    @Namespace private var ns
    
    var body: some View {
        InsetList {
            ToSection()
                .scrollPosition(ns: ns, offset: 8, callback: onScrollPositionChange)
            NftSection()
            AmountSection()
            CommentSection()
        }
        .coordinateSpace(name: ns)
        .environmentObject(model)
        .navigationBarInset(navigationBarInset)
    }
}


fileprivate struct ToSection: View {
    @EnvironmentObject private var model: SendModel
    
    var body: some View {
        InsetSection {
            AddressCellView()
        } header: {
            Text(lang("Send to"))
        } footer: {}
    }
}


fileprivate struct AddressCellView: View {
    
    @EnvironmentObject private var model: SendModel
    
    var body: some View {
        Menu {
            AddressActions(address: model.resolvedAddress ?? model.addressOrDomain, showSaveToFavorites: true)
        } label: {
            InsetCell {
                let more: Text = Text(
                    Image(systemName: "chevron.down")
                )
                    .font(.system(size: 14))
                    .foregroundColor(Color(WTheme.secondaryLabel))
            
                Group {
                    if let resolvedAddress = model.resolvedAddress, resolvedAddress != model.addressOrDomain {
                        let addr = Text(model.addressOrDomain).foregroundColor(Color(WTheme.primaryLabel))
                        let resolvedAddress = Text(
                            formatAddressAttributed(
                                resolvedAddress,
                                startEnd: false,
                                primaryColor: WTheme.secondaryLabel
                            )
                        )
                
                        Text("\(addr)\u{A0}·\u{A0}\(resolvedAddress) \(more)") // non-breaking spaces
                        
                    } else {
                        let addr = Text(
                            formatAddressAttributed(
                                model.addressOrDomain,
                                startEnd: false
                            )
                        )
                        
                        Text("\(addr) \(more)")
                    }

                }
                .multilineTextAlignment(.leading)
                .font16h22()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(.rect)
        }
    }
}


fileprivate struct AmountSection: View {
    
    @EnvironmentObject private var model: SendModel
    
    var body: some View {
        if let amount = model.amount {
            InsetSection {
                AmountCell(amount: amount, token: model.token!)
            } header: {
                Text(lang("Amount"))
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    if let amount = model.amountInBaseCurrency, let baseCurrency = TokenStore.baseCurrency {
                        Text(
                            amount: DecimalAmount(amount, baseCurrency),
                            format: .init()
                        )
                    }
                    Spacer()
                    if let token = model.token, let nativeToken = model.nativeToken {
                        FeeView(token: token, nativeToken: nativeToken, fee: model.showingFee, explainedTransferFee: nil, includeLabel: true)
                    }
                }
            }
        }
    }
}



fileprivate struct CommentSection: View {

    @EnvironmentObject private var model: SendModel

    var body: some View {
        if model.binaryPayload?.nilIfEmpty != nil {
            binaryPayloadSection
        } else {
            commentSection
        }
    }
    
    @ViewBuilder
    var commentSection: some View {
        if !model.comment.isEmpty {
            InsetSection {
                InsetCell {
                    Text(verbatim: model.comment)
                        .font17h22()
                }
            } header: {
                Text(model.isMessageEncrypted ? lang("Encrypted Message") : lang("Comment or Memo"))
            } footer: {}
                .padding(.top, -8)
        }
    }
    
    @ViewBuilder
    var binaryPayloadSection: some View {
        if let binaryPayload = model.binaryPayload {
            InsetSection {
                InsetExpandableCell(content: binaryPayload)
            } header: {
                Text(lang("Signing Data"))
            } footer: {
                WarningView(text: "Signing custom data is very dangerous. Use it only if you trust the source of it.")
                    .padding(.vertical, 11)
                    .padding(.horizontal, -16)
            }
        }
    }
}
