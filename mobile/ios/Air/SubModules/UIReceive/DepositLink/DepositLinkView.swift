//
//  DepositLinkView.swift
//  AirAsFramework
//
//  Created by nikstar on 01.08.2025.
//

import SwiftUI
import UIComponents
import WalletContext
import WalletCore

struct DepositLinkView: View {
    
    @StateObject private var model: DepositLinkModel = .init(nativeToken: .toncoin)
    
    var topPadding: CGFloat
    var onScroll: (CGFloat) -> ()
    
    @FocusState private var commentIsFocused: Bool
    
    @Namespace private var ns
    
    var body: some View {
        InsetList(topPadding: topPadding) {
            
            Text(lang("$receive_invoice_description"))
                .foregroundStyle(.secondary)
                .font13()
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .padding(.bottom, -8)
                .scrollPosition(ns: ns, offset: topPadding, callback: onScroll)

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
                        TappableDepositLink(depostitLink: url, ns: ns)
                    }
                } header: {
                    Text(lang("Share this URL to receive %token%", arg1: model.tokenAmount.token.symbol))
                }
            }
        }
        .onTapGesture {
            topViewController()?.view.endEditing(true)
        }
        .coordinateSpace(name: ns)
    }
}


struct TappableDepositLink: View {
    
    var depostitLink: String
    var ns: Namespace.ID
    @StateObject private var menuContext = MenuContext()
    
    var body: some View {
        let link = Text(depostitLink.map { "\($0)\u{200B}" }.joined() )
        let more: Text = Text(
            Image(systemName: "chevron.down")
        )
            .font(.system(size: 14))
            .foregroundColor(Color(WTheme.secondaryLabel))

        Text("\(link) \(more)")
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .menuSource(menuContext: menuContext)
            .task(id: depostitLink) {
                menuContext.makeConfig = {
                    var items: [MenuItem] = []
                    items += .button(id: "0-copy", title: lang("Copy"), trailingIcon: .air("SendCopy")) {
                        AppActions.copyString(depostitLink, toastMessage: "Link copied")
                    }
                    if let url = URL(string: depostitLink) {
                        items += .button(id: "0-share", title: lang("Share"), trailingIcon: .system("square.and.arrow.up")) {
                            AppActions.shareUrl(url)
                        }
                    }
                    return MenuConfig(menuItems: items)
                }
            }
    }
}
