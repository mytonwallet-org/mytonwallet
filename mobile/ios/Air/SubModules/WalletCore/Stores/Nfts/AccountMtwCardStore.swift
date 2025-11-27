//
//  AccountMtwCardStore.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/30/24.
//

import Foundation
import WalletContext
import OrderedCollections
import Dependencies
import Perception
import UIKit

@Perceptible
@MainActor public final class AccountMtwCardStore {
    
    public let accountId: String
    
    public init(accountId: String) {
        self.accountId = accountId
    }
}



