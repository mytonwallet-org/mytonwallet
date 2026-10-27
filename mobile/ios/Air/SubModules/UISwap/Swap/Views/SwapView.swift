import SwiftUI
import UIComponents
import WalletCore
import Perception

private let bottomButtonScrollPadding: CGFloat = 114

struct SwapView: View {
    
    var swapModel: SwapModel
    var isSensitiveDataHidden: Bool
    var showsSelectors = true
    var onSelectorsAppear: (() -> Void)?
    
    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(spacing: 16) {
                    if showsSelectors {
                        SwapSelectorsView(
                            model: swapModel.input,
                            hasAmountError: swapModel.hasAmountError,
                            hasInsufficientFunds: swapModel.hasInsufficientFunds,
                            onAppear: onSelectorsAppear ?? swapModel.input.focusInitialInput
                        )
                            .padding(.top, 8)
                    }
                    
                    SwapWarning(displayImpactWarning: swapModel.displayImpactWarning)
                    
                    switch swapModel.detailsSection {
                    case .dex:
                        SwapDetailsView(
                            model: swapModel.detailsVM,
                            slippage: swapModel.slippage,
                            isFeeError: swapModel.hasInsufficientFee,
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
                            swapType: swapType,
                            isFeeError: swapModel.hasInsufficientFee
                        )
                    }
                    if let hint = swapModel.hint {
                        SwapHintView(hint: hint) {
                            swapModel.performHintAction(hint)
                        }
                    }
                    if let estimateDebugSummary = swapModel.estimateDebugSummary {
                        Text(estimateDebugSummary)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.air.secondaryLabel)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                Color.air.secondaryFill,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                }
                .padding(.horizontal, 16)
                .animation(.snappy, value: swapModel.estimateState.dexEstimate)
                .animation(.snappy, value: swapModel.estimateState.cexEstimate)
                .animation(.snappy, value: swapModel.detailsSection)
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
