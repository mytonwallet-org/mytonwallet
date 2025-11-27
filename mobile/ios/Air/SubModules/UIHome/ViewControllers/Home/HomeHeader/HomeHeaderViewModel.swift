//
//  HomeHeaderViewModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies
import UIKitNavigation

private let log = Log("HomeCard")

@Perceptible
class HomeHeaderViewModel {
    var height: CGFloat = 0
    var state: WalletCardView.State = .expanded
    var topSafeAreaInset: CGFloat = 0
    let collapsedHeight: CGFloat = 111
    var cardIsHidden = false
    var width: CGFloat = 0
    
    @PerceptionIgnored
    var onSelect: (String) -> () = { _ in }
    
    @PerceptionIgnored
    @Dependency(\.accountStore.currentAccountId) var currentAccountId
    @PerceptionIgnored
    @Dependency(\.accountStore) var accountStore
    
    let currentAccountViewModel: AccountViewModel
    
    @PerceptionIgnored
    private var currentAccountObserver: AnyObject?
    
    init() {
        @Dependency(\.accountStore.currentAccountId) var currentAccountId
        currentAccountViewModel = AccountViewModel(accountId: currentAccountId)
        currentAccountObserver = observe { [weak self] in
            guard let self else { return }
            currentAccountViewModel.accountId = currentAccountId
        }
    }
    
    var isCollapsed: Bool { state == .collapsed }
}

