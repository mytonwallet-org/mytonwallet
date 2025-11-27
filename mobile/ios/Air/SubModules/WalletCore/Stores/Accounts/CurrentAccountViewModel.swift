

import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies
import SwiftNavigation

@Perceptible
public final class CurrentAccountViewModel: AccountViewModel {
    
    private var currentAccountObservation: ObserveToken?
    
    public init() {
        @Dependency(\.accountStore.currentAccountId) var currentAccountId
        super.init(accountId: currentAccountId)
        currentAccountObservation = observe { [weak self] in
            guard let self else { return }
            let currentAccountId = currentAccountId
            if currentAccountId != self.accountId {
                self.accountId = currentAccountId
            }
        }
    }
}
