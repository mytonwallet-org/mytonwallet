
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception

struct HomeCardBackground: View {
    
    var headerViewModel: HomeHeaderViewModel
    var accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            _StaticBackground(accountContext: accountContext)
                .opacity(headerViewModel.isCardHidden ? 0 : 1)
        }
    }
}

private struct _StaticBackground: View {
    
    let accountContext: AccountContext
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: accountContext.nft, hideBorder: false)
                .aspectRatio(1/CARD_RATIO, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 26))
                .containerShape(.rect(cornerRadius: 26))
        }
    }
}
