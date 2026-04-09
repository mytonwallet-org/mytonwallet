//
//  DepositLinkView.swift
//  AirAsFramework
//
//  Created by nikstar on 01.08.2025.
//

import SwiftUI
import ContextMenuKit
import UIComponents
import WalletContext
import WalletCore
import Perception

struct DepositLinkView: View {
    
    @State private var model: DepositLinkModel
    
    @FocusState private var commentIsFocused: Bool

    init(accountContext: AccountContext, nativeToken: ApiToken) {
        _model = State(initialValue: DepositLinkModel(accountContext: accountContext, nativeToken: nativeToken))
    }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            InsetList {
                
                Text(lang("$receive_invoice_description"))
                    .foregroundStyle(.secondary)
                    .font13()
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, -8)
    
                TokenAmountEntrySection(
                    amount: $model.tokenAmount.optionalAmount,
                    token: model.tokenAmount.token,
                    balance: nil,
                    showMaxAmount: false,
                    insufficientFunds: false,
                    amountInBaseCurrency: $model.baseCurrencyAmount,
                    switchedToBaseCurrencyInput: $model.switchedToBaseCurrency,
                    allowSwitchingToBaseCurrency: false,
                    fee: nil,
                    explainedFee: nil,
                    isFocused: $model.amountFocused,
                    onTokenSelect: model.onTokenTapped,
                    onUseAll: {}
                )
                .padding(.bottom, -8)
                
                InsetSection {
                    InsetCell {
                        TextField(
                            lang("Optional"),
                            text: $model.comment,
                            axis: .vertical
                        )
                        .writingToolsDisabled()
                        .focused($commentIsFocused)
                    }
                    .contentShape(.rect)
                    .onTapGesture {
                        commentIsFocused = true
                    }
                } header: {
                    Text(lang("Comment"))
                }
                
                if let url = model.url {
                    InsetSection {
                        InsetCell {
                            TappableDepositLink(depostitLink: url)
                        }
                    } header: {
                        Text(lang("Share this URL to receive %token%", arg1: model.tokenAmount.token.symbol))
                    }
                }
            }
            .onTapGesture {
                topViewController()?.view.endEditing(true)
            }
        }
    }
}


struct TappableDepositLink: View {
    
    var depostitLink: String
    
    var body: some View {
        let link = Text(depostitLink.map { "\($0)\u{200B}" }.joined() )
        let more = Text(Image.airBundle("ArrowUpDownSmall"))
            .foregroundColor(.air.secondaryLabel.opacity(0.8))
            .baselineOffset(-1)

        Text("\(link) \(more)")
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .contextMenuSource {
                makeMenuConfiguration()
            }
    }

    private func makeMenuConfiguration() -> ContextMenuConfiguration {
        var items: [ContextMenuItem] = []
        items.append(
            .action(
                ContextMenuAction(
                    title: lang("Copy"),
                    icon: .airBundle("SendCopy"),
                    handler: {
                        AppActions.copyString(depostitLink, toastMessage: "Link copied")
                    }
                )
            )
        )
        if let url = URL(string: depostitLink) {
            items.append(
                .action(
                    ContextMenuAction(
                        title: lang("Share"),
                        icon: .system("square.and.arrow.up"),
                        handler: {
                            AppActions.shareUrl(url)
                        }
                    )
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 180.0)
        )
    }
}
