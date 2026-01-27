import SwiftUI
import UIComponents
import WalletCore
import Perception

struct SwapView: View {
    
    var swapModel: SwapModel
    var isSensitiveDataHidden: Bool
    
    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 16) {
                    SwapSelectorsView(model: swapModel.input)
                        .padding(.top, 8)
                    
                    SwapWarning(displayImpactWarning: swapModel.detailsVM.displayImpactWarning)
                    
                    if swapModel.swapType == .onChain {
                        SwapDetailsView(
                            inputModel: swapModel.input,
                            model: swapModel.detailsVM
                        )
                        .transition(.opacity)
                    } else {
                        SwapChangellyView()
                            .transition(.opacity)
                        SwapCexDetailsView(
                            inputModel: swapModel.input,
                            crosschainModel: swapModel.crosschain,
                            swapType: swapModel.swapType
                        )
                    }
                    
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, 16)
                .animation(.snappy, value: swapModel.detailsVM.swapEstimate)
            }
        }
    }
}
