import SwiftUI
import UIComponents
import WalletCore
import Perception

struct SwapView: View {
    
    var swapVM: SwapVM
    var selectorsVM: SwapSelectorsVM
    var detailsVM: SwapDetailsVM
    var swapType: SwapType { swapVM.swapType }
    var swapEstimate: ApiSwapEstimateResponse? { detailsVM.swapEstimate }
    var isSensitiveDataHidden: Bool
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var swapVM = swapVM
            @Perception.Bindable var selectorsVM = selectorsVM
            @Perception.Bindable var detailsVM = detailsVM
            
            ScrollView {
                VStack(spacing: 16) {
                    SwapSelectorsView(model: selectorsVM)
                        .padding(.top, 8)
                    
                    SwapWarning(displayImpactWarning: detailsVM.displayImpactWarning)
                    
                    if swapType == .onChain {
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
        }
    }
}
