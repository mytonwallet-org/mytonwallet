
import Foundation
import WalletContext


public enum StepId: Sendable {
    case connect
    case openApp
    case sign
    case discoveringWallets
    
    var displayTitlle: String {
        switch self {
        case .connect:
            "Connect your Ledger via Bluetooth"
        case .openApp:
            "Unlock it and open the TON app"
        case .sign:
            "Please confirm transfer on your Ledger"
        case .discoveringWallets:
            "Discovering wallets"
        }
    }
}

public enum StepStatus: Sendable, Equatable {
    case none
    case current
    case done
    case error(String?)
    case hidden
    
    var displaySubtitle: String? {
        switch self {
        case .none:
            return nil
        case .current:
            return nil
        case .done:
            return nil
        case .error(let errorString):
            return errorString
        case .hidden:
            return nil
        }
    }
}
