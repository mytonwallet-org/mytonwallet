//
//  WalletSettingsViewModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import UIKit
import WalletContext
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

private let defaultPreferrsList = "walletSettingsPreferrsListLayout"
private let defaultCurrentFilter = "walletSettingsCurrentFilter"

@Perceptible
final class WalletSettingsViewModel {
    
    var currentFilter: WalletFilter = .ledger {
        didSet {
            UserDefaults.standard.set(currentFilter.rawValue, forKey: defaultCurrentFilter)
        }
    }
    
    var preferredLayout: WalletListLayout = .grid {
        didSet {
            UserDefaults.standard.set(preferredLayout == .list, forKey: defaultPreferrsList)
        }
    }
    
    var isReordering: Bool = false
    var segmentedControllerDidSwitchTrigger: Int = 0
    
    init() {
        self.currentFilter = if let s = UserDefaults.standard.string(forKey: "walletSettingsCurrentFilter"), let f = WalletFilter(rawValue: s) { f } else { .all }
        self.preferredLayout = UserDefaults.standard.bool(forKey: defaultPreferrsList) ? .list : .grid
    }
    
    var effectiveLayout: WalletListLayout {
        isReordering ? .list : preferredLayout
    }
    
    func setPreferredLayout(_ layout: WalletListLayout) {
        preferredLayout = layout
    }
    
    func startEditing() {
        isReordering = true
    }
    
    func stopEditing() {
        isReordering = false
    }
}
