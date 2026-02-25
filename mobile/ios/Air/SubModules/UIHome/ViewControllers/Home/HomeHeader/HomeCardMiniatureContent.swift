
import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect
import Perception
import Dependencies

struct HomeCardMiniatureContent: View {
    
    var headerViewModel: HomeHeaderViewModel
    var accountContext: AccountContext
    var layout: HomeCardLayoutMetrics
    
    var body: some View {
        WithPerceptionTracking {
            Color.clear
                .overlay(alignment: .bottom) {
                    MtwCardMiniPlaceholders()
                        .sourceAtop {
                            MtwCardInverseCenteredGradient(nft: accountContext.nft)
                        }
                        .padding(.bottom, 18)
                        .scaleEffect(layout.itemWidth/34)
                }
                .opacity(headerViewModel.isCardHidden ? 0 : 1)
        }
    }
    
    var isCollapsed: Bool {
        headerViewModel.isCollapsed
    }
}
