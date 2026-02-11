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
