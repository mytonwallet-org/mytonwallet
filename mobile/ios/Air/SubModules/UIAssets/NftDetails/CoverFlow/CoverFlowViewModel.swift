//
//  CoverFlowViewModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 01.07.2025.
//

import SwiftUI
import Perception

@Perceptible
final class CoverFlowViewModel<Item: Identifiable> {
    
    var items: [Item]
    var selectedItem: Item.ID
    
    @PerceptionIgnored
    var onTap: () -> ()
    @PerceptionIgnored
    var onLongTap: () -> ()
    
    init(items: [Item], selectedItem: Item.ID, onTap: @escaping () -> Void, onLongTap: @escaping () -> Void) {
        self.items = items
        self.selectedItem = selectedItem
        self.onTap = onTap
        self.onLongTap = onLongTap
    }
}

enum CoverFlowIsScrollingPreference: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
