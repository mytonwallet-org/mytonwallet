
import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext

struct HeaderDappIcon: View {
    
    static let cornerRadius: CGFloat = 16
    
    var dapp: ApiDapp
    
    var body: some View {
        DappIcon(iconUrl: dapp.iconUrl)
            .frame(width: 64, height: 64)
            .background(Color.air.secondaryFill)
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(.foreground.opacity(0.1), lineWidth: 1)
            }
            .clipShape(.containerRelative)
            .containerShape(.rect(cornerRadius: Self.cornerRadius))
    }
}
