
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies

struct HomeCardBackground: View {
    
    var headerViewModel: HomeHeaderViewModel
    var accountViewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            _StaticBackground(viewModel: accountViewModel)
                .opacity(headerViewModel.isCardHidden ? 0 : 1)
        }
    }
}

private struct _StaticBackground: View {
    
    let viewModel: AccountViewModel
    
    var body: some View {
        WithPerceptionTracking {
            MtwCardBackground(nft: viewModel.nft, hideBorder: false)
                .aspectRatio(1/CARD_RATIO, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 26))
                .containerShape(.rect(cornerRadius: 26))
        }
    }
}
