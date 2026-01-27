//
//  ActivateBiometricViewModel.swift
//  UIPasscode
//
//  Created by Murad Kakabaev on 21.01.2026.
//

import Foundation
import Perception

@Perceptible
final class ActivateBiometricViewModel {
    enum State {
        case idle
        case authenticating
        case skipping
    }
    
    let biometryType: BiometryType
    
    var state: State = .idle
    
    init(biometryType: BiometryType) {
        self.biometryType = biometryType
    }
    
    var isAuthenticationInProgress: Bool {
        state == .authenticating
    }
    
    var isSkippingInProgress: Bool {
        state == .skipping
    }
    
    var areButtonsEnabled: Bool {
        state == .idle
    }
}
