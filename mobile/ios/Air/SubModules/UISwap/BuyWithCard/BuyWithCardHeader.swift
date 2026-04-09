//
//  BuyWithCardVC.swift
//  UISwap
//
//  Created by Sina on 5/14/24.
//

import WebKit
import UIKit
import ContextMenuKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception


struct BuyWithCardHeader: View {
    
    var model: BuyWithCardModel
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var model = model
            VStack(alignment: .center, spacing: 0) {
                Text(lang("Buy with Card"))
                    .font(.system(size: 17, weight: .semibold))
                Text("\(lang(model.selectedCurrency.name)) \(Image(systemName: "chevron.down"))")
                    .font(.system(size: 13, weight: .regular))
                    .imageScale(.small)
                    .frame(minWidth: 200)
                    .foregroundStyle(.secondary)
            }
            .contextMenuSource {
                makeMenuConfiguration(selection: model.selectedCurrency)
            }
        }
    }
    
    private func makeMenuConfiguration(selection: MBaseCurrency) -> ContextMenuConfiguration {
        let items: [ContextMenuItem] = model.supportedCurrencies.map { currency in
            let icon: ContextMenuIcon = if selection == currency {
                .system("checkmark") ?? .placeholder
            } else {
                .placeholder
            }

            return ContextMenuItem.action(
                ContextMenuAction(
                    title: lang(currency.name),
                    icon: icon,
                    handler: {
                        model.selectedCurrency = currency
                    }
                )
            )
        }

        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: items),
            backdrop: .none,
            style: ContextMenuStyle(minWidth: 200.0)
        )
    }
}
