import SwiftUI
import UIComponents
import WalletCore
import Perception

private let bottomButtonScrollPadding: CGFloat = 114

struct SwapView: View {
    
    var swapModel: SwapModel
    var isSensitiveDataHidden: Bool
    
    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 16) {
                    SwapSelectorsView(model: swapModel.input)
                        .padding(.top, 8)
                    
                    SwapWarning(displayImpactWarning: swapModel.displayImpactWarning)
                    
                    switch swapModel.detailsSection {
                    case .onchain:
                        SwapDetailsView(
                            model: swapModel.detailsVM,
                            slippage: swapModel.slippage,
                            onSlippageCommit: { swapModel.commitSlippage($0) }
                        )
                        .transition(.opacity)
                    case .crosschain(let swapType):
                        if let cexEstimate = swapModel.crosschain.cexEstimate,
                           let providerName = cexEstimate.providerName {
                            SwapCexProviderInfoView(
                                providerName: providerName,
                                termsOfUseUrl: cexEstimate.termsOfUseUrl,
                                privacyPolicyUrl: cexEstimate.privacyPolicyUrl,
                                amlKycPolicyUrl: cexEstimate.amlKycPolicyUrl
                            )
                                .transition(.opacity)
                        }
                        SwapCexDetailsView(
                            inputModel: swapModel.input,
                            swapEstimate: swapModel.crosschain.cexEstimate,
                            swapType: swapType
                        )
                    }
                }
                .padding(.horizontal, 16)
                .animation(.snappy, value: swapModel.onchain.swapEstimate)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: bottomButtonScrollPadding)
                    .accessibilityHidden(true)
            }
        }
    }
}
