
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Kingfisher

struct SendDappWarningView: View {
    
    var body: some View {
        WarningView(text: lang("$hardware_payload_warning"), color: .orange)
            .fontWeight(.medium)
    }
}
