
import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Kingfisher

struct HeaderDappIcon: View {
    
    var dapp: ApiDapp
    
    var body: some View {
        KFImage(URL(string: dapp.iconUrl))
            .resizable()
            .frame(width: 64, height: 64)
            .background(Color(WTheme.secondaryFill))
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(.foreground.opacity(0.1), lineWidth: 1)
            }
            .clipShape(.containerRelative)
            .containerShape(.rect(cornerRadius: 16))
    }
}
