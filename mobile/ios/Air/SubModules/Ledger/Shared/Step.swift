
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
            lang("Connect your Ledger via Bluetooth")
        case .openApp:
            lang("Unlock it and open the TON App")
        case .sign:
            lang("Please confirm transfer on your Ledger")
        case .discoveringWallets:
            lang("Discovering wallets")
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
