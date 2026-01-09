//
//  AccountIdProvider.swift
//  MyTonWalletAir
//
//  Created by nikstar on 11.12.2025.
//

import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies
import SwiftNavigation

@Perceptible
public final class AccountIdProvider {
    
    public let source: AccountSource
    
    /// Setting overrides currentAccountId observation until the next change
    public var accountId: String
    
    @PerceptionIgnored
    private var observeToken: ObserveToken?
    
    /// Providing accountId == nil will track currentAccountId
    public init(source: AccountSource) {
        self.source = source
        switch source {
        case .accountId(let accountId):
            self.accountId = accountId
        case .current:
            @Dependency(\.accountStore.currentAccountId) var currentAccountId

            self.accountId = currentAccountId
            observeToken = observe { [weak self] in
                guard let self else { return }
                self.accountId = currentAccountId
            }
        case .constant(let account):
            self.accountId  = account.id
        }
    }
}
