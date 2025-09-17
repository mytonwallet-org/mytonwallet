import SwiftUI
import UIComponents
import WalletCore

struct SwapView: View {
    
    @ObservedObject var swapVM: SwapVM
    @ObservedObject var selectorsVM: SwapSelectorsVM
    @ObservedObject var detailsVM: SwapDetailsVM
    var swapType: SwapType { swapVM.swapType }
    var swapEstimate: ApiSwapEstimateResponse? { detailsVM.swapEstimate }
    var isSensitiveDataHidden: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SwapSelectorsView(model: selectorsVM)
                    .padding(.top, 8)
                
                SwapWarning(displayImpactWarning: detailsVM.displayImpactWarning)
                
                if swapType == .inChain {
                    SwapDetailsView(
                        swapVM: swapVM,
                        selectorsVM: selectorsVM,
                        model: detailsVM
                    )
                    .transition(.opacity)
                } else {
                    SwapChangellyView()
                        .transition(.opacity)
                    SwapCexDetailsView(
                        swapVM: swapVM,
                        selectorsVM: selectorsVM
                    )
                }
                
                Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, 16)
            .animation(.snappy, value: swapEstimate)
        }
        .environment(\.isSensitiveDataHidden, isSensitiveDataHidden)
    }
}
