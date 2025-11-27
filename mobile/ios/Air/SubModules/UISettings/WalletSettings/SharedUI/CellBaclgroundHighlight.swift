//
//  CellBaclgroundHighlight.swift
//  MyTonWalletAir
//
//  Created by nikstar on 18.11.2025.
//

import SwiftUI
import WalletContext

struct CellBaclgroundHighlight: View {
    
    var isHighlighted: Bool
    
    var body: some View {
        Rectangle()
            .fill(isHighlighted ? Color.air.highlight : Color.air.groupedItem)
            .animation(.linear(duration: isHighlighted ? 0.1 : 0.5), value: isHighlighted)
    }
}
