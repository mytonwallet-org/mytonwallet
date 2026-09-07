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
                    case .dex:
                        SwapDetailsView(
                            model: swapModel.detailsVM,
                            slippage: swapModel.slippage,
                            onSlippageCommit: { swapModel.commitSlippage($0) }
                        )
                        .transition(.opacity)
                    case .cex(let swapType):
                        if let cexEstimate = swapModel.estimateState.cexEstimate,
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
                            swapEstimate: swapModel.estimateState.cexEstimate,
                            swapType: swapType
                        )
                    }
                    if let hint = swapModel.hint {
                        SwapHintView(hint: hint) {
                            swapModel.performHintAction(hint)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .animation(.snappy, value: swapModel.estimateState.dexEstimate)
            }
            .backportScrollEdgeEffectHidden(for: .top)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: bottomButtonScrollPadding)
                    .accessibilityHidden(true)
            }
        }
    }
}
