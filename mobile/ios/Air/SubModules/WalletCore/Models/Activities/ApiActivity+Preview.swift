//
//  ApiActivity.swift
//  WalletCore
//
//  Created by Sina on 3/20/24.
//

import UIKit
import WalletContext

public extension ApiActivity {
    
    var shouldShowCenteredTitle: Bool {
        if type != nil {
            return true
        } else {
            return false
        }
    }
}
