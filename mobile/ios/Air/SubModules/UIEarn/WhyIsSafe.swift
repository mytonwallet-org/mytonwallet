//
//  WhyIsSafe.swift
//  UIEarn
//
//  Created by nikstar on 28.07.2025.
//

import UIKit
import SwiftUI
import WalletContext
import UIComponents

@MainActor
func showWhyIsSafe(config: StakingConfig) {
    
    if let vc = topWViewController() {
        let lines = config.explainContent
        
        vc.showTip(title: config.explainTitle) {            
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 4, verticalSpacing: 12) {
                ForEach(Array(lines.indices), id: \.self) { i in
                    GridRow {
                        Text("\(i + 1).")
                        Text(LocalizedStringKey(lines[i]))
                    }
                }
            }
        }
    }
}
