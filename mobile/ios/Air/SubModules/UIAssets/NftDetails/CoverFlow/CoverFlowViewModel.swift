//
//  CoverFlowViewModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 01.07.2025.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import SwiftUIIntrospect

public enum CoverFlowDefaults {
    static let itemSpacing: Double = -60
    static let rotationSensitivity: Double = 2.7
    static let rotationAngle: Double = -15
    static let offsetSensitivity: Double = 1
    static let offsetMultiplier: Double = 4
    static let offsetMultiplier2: Double = -50
}

final class CoverFlowViewModel<Item: Identifiable>: ObservableObject {
    
    @Published var items: [Item]
    @Published var selectedItem: Item.ID
    
    var onTap: () -> ()
    var onLongTap: () -> ()
    
    init(items: [Item], selectedItem: Item.ID, onTap: @escaping () -> Void, onLongTap: @escaping () -> Void) {
        self.items = items
        self.selectedItem = selectedItem
        self.onTap = onTap
        self.onLongTap = onLongTap
    }
}

extension EnvironmentValues {
    @Entry var coverFlowItemSize: CGFloat = 144.0
    @Entry var coverFlowIsCurrent: Bool = false
    @Entry var coverFlowDistance: CGFloat = 1
}

enum CoverFlowIsScrollingPreference: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

