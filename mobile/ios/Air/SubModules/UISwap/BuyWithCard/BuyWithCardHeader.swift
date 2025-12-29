//
//  BuyWithCardVC.swift
//  UISwap
//
//  Created by Sina on 5/14/24.
//

import WebKit
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception


struct BuyWithCardHeader: View {
    
    var model: BuyWithCardModel
    @State var menuContext = MenuContext()
    
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
            .contentShape(.rect)
            .menuSource(menuContext: menuContext)
            .onChange(of: model.selectedCurrency, perform: configureMenu)
            .onAppear { configureMenu(model.selectedCurrency) }
        }
    }
    
    func configureMenu(_ selection: MBaseCurrency) {
        menuContext.makeConfig = {
            let items: [MenuItem] = model.supportedCurrencies.map { currency in
                MenuItem.customView(
                    id: currency.rawValue,
                    view: {
                        AnyView(
                            SelectableMenuItem(id: "0-" + currency.rawValue, action: {
                                model.selectedCurrency = currency
                            }) {
                                HStack {
                                    Text(lang(currency.name))
                                        .fixedSize()
                                    Spacer()
                                    if selection == currency {
                                        Text(Image(systemName: "checkmark"))
                                    }
                                }
                            }
                            .frame(height: 44)
                        )
                    },
                    height: 44,
                )
            }
            return MenuConfig(menuItems: items)
        }
    }
}
