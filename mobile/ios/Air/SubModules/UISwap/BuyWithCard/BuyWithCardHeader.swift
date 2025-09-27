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


struct BuyWithCardHeader: View {
    
    @ObservedObject var model: BuyWithCardModel
    @StateObject var menuContext = MenuContext()
    
    var body: some View {
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
        .menuSource(isEnabled: true, coordinateSpace: .global, menuContext: menuContext)
        .onChange(of: model.selectedCurrency, perform: setMenu)
        .onAppear { setMenu(model.selectedCurrency) }
    }
    
    func setMenu(_ selection: MBaseCurrency) {
        menuContext.setMenu {
            ScrollableMenuContent {
                DividedVStack {
                    ForEach(model.supportedCurrencies) { currency in
                        SelectableMenuItem(id: currency.rawValue, action: {
                            model.selectedCurrency = currency
                            menuContext.dismiss()
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
                    }
                }
            }
        }
    }
}
