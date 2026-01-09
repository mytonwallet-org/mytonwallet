

import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import Dependencies

struct SendConfirmView: View {
    
    let model: SendModel
    
    var body: some View {
        WithPerceptionTracking {
            InsetList {
                ToSection(model: model)
                NftSection(model: model)
                AmountSection(model: model)
                CommentSection(model: model)
            }
        }
    }
}


fileprivate struct ToSection: View {
    let model: SendModel
    
    var body: some View {
        WithPerceptionTracking {
            InsetSection {
                AddressCellView(model: model)
            } header: {
                Text(lang("Recipient Address"))
            } footer: {}
        }
    }
}


fileprivate struct AddressCellView: View {
    
    let model: SendModel
    
    @State private var menuContext = MenuContext()
    
    var body: some View {
        WithPerceptionTracking {
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
            .menuSource(menuContext: menuContext)
            .task {
                menuContext.makeConfig = makeTappableAddressMenu(accountContext: model.$account, displayName: nil, chain: model.token.chain, address: model.addressOrDomain)
            }
        }
    }
}


fileprivate struct AmountSection: View {
    
    let model: SendModel
    
    @Dependency(\.tokenStore) private var tokenStore
    
    var body: some View {
        WithPerceptionTracking {
            if let amount = model.amount {
                InsetSection {
                    AmountCell(amount: amount, token: model.token)
                } header: {
                    Text(lang("Amount"))
                } footer: {
                    HStack(alignment: .firstTextBaseline) {
                        if let amount = model.amountInBaseCurrency {
                            Text(
                            amount: DecimalAmount(amount, model.baseCurrency),
                                format: .init()
                            )
                        }
                        Spacer()
                        FeeView(token: model.token, nativeToken: tokenStore.getNativeToken(chain: model.token.chainValue), fee: model.showingFee, explainedTransferFee: nil, includeLabel: true)
                    }
                }
            }
        }
    }
}



fileprivate struct CommentSection: View {
    
    let model: SendModel
    
    var body: some View {
        WithPerceptionTracking {
            if model.binaryPayload?.nilIfEmpty != nil {
                binaryPayloadSection
            } else {
                commentSection
            }
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
                WarningView(text: lang("$signature_warning"))
                    .padding(.vertical, 11)
                    .padding(.horizontal, -16)
            }
        }
    }
}
