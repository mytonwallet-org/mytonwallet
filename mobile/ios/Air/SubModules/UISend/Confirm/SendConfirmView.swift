

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
                InsetCell {
                    TappableAddressFull(accountContext: model.$account, model: model.addressViewModel, compactAddressWithName: false)
                }
            } header: {
                Text(lang("Recipient Address"))
            } footer: {}
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
                        FeeView(token: model.token, nativeToken: tokenStore.getNativeToken(chain: model.token.chain), fee: model.showingFee, explainedTransferFee: nil, includeLabel: true)
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
