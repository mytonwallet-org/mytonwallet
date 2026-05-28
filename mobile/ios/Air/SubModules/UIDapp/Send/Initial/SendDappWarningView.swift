
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import Kingfisher

struct SendDappWarningView: View {
    
    var body: some View {
        WarningView(text: lang("$hardware_payload_warning"), kind: .warning)
            .fontWeight(.medium)
    }
}
