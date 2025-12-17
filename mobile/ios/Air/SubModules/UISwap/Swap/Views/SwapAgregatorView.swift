
import SwiftUI
import UIComponents
import WalletCore
import WalletContext


struct SwapAgregatorView: View {
    
    var fromToken: ApiToken
    var toToken: ApiToken
    var estimate: ApiSwapEstimateResponse
    var selectedState: ApiSwapDexLabel?
    var onSelect: (ApiSwapDexLabel?) -> ()
    
    var bestOption: ApiSwapDexLabel? { estimate.dexLabel }
    var worseOption: ApiSwapDexLabel? {
        if let bestOption {
            return bestOption == .ston ? .dedust : .ston
        }
        return nil
    }
    
    var fromAmount: TokenAmount { TokenAmount.fromDouble(estimate.fromAmount?.value ?? 99, fromToken) }
    var bestToAmount: TokenAmount { TokenAmount.fromDouble(estimate.toAmount?.value ?? 99, toToken) }
    var worseToAmount: TokenAmount { TokenAmount.fromDouble(estimate.other?.first?.toAmount.value ?? 99, toToken) }
    var difference: TokenAmount { TokenAmount(bestToAmount.amount - worseToAmount.amount, toToken) }
    
    private var alternativeOption: ApiSwapEstimateVariant? {
        let otherDexLabel: ApiSwapDexLabel = estimate.dexLabel == .dedust ? .ston : .dedust
        return estimate.other?.first { $0.dexLabel == otherDexLabel }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                exchangeOptionCard(
                    dexLabel: .dedust,
                    isSelected: estimate.dexLabel == .dedust,
                    amount: bestOption == .dedust ? estimate.toAmount?.value : alternativeOption?.toAmount.value
                )
                
                exchangeOptionCard(
                    dexLabel: .ston,
                    isSelected: estimate.dexLabel == .ston,
                    amount: bestOption == .ston ? estimate.toAmount?.value : alternativeOption?.toAmount.value
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            
            VStack(alignment: .leading, spacing: 12) {
                Text(langMd("Analyzed actual rates on **DeDust** and **STON.fi** to use the **best rate**."))
                    .font13()
                    .foregroundColor(Color.secondary)
                
                Text("You will receive \(Text(amount: difference, format: .init(maxDecimals: 5))) more.")
                    .font13()
                    .foregroundColor(Color.secondary)
                    .transition(.opacity)
                    .opacity(selectedState == bestOption || selectedState == nil ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
    
    @ViewBuilder
    private func exchangeOptionCard(dexLabel: ApiSwapDexLabel, isSelected: Bool, amount: Double?) -> some View {
        let toAmount = dexLabel == bestOption ? bestToAmount : worseToAmount
        
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image.airBundle(dexLabel.rawValue)
                    .resizable()
                    .frame(width: 32, height: 32)
                    .clipShape(.rect(cornerRadius: 10))
                
                Text(dexLabel.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 4)
            
            Text(amount: toAmount, format: .init(maxDecimals: 5))
                .font(.system(size: 17, weight: .semibold))
                .redacted(reason: amount == nil ? .placeholder : [])
                .foregroundStyle(labelStyle(dexLabel: dexLabel))
                .frame(maxHeight: .infinity, alignment: .top)
            
            let rate = fromAmount.doubleValue > 0 ? toAmount.doubleValue / fromAmount.doubleValue : 99
            let exchangeRate = TokenAmount.fromDouble(rate, toToken)
            Text("\(fromToken.symbol) ≈ \n\(Text(amount: exchangeRate, format: .init(maxDecimals: 5)))")
                .font(.system(size: 13))
                .redacted(reason: amount == nil || fromAmount.doubleValue <= 0 ? .placeholder : [])
                .foregroundStyle(Color(WTheme.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderStyle(dexLabel: dexLabel), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Group {
                if isSelected {
                    Text(lang("Best"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .padding(.trailing, -1)
                        .background(Color.airBundle("EarnGradientColorRight"), in: .capsule)
                        .offset(x: -14, y: 0)
                }
            }
            .alignmentGuide(VerticalAlignment.top, computeValue: { $0.height / 2 }) // -1 is affordance for border width
        }
        .contentShape(.rect)
        ._onButtonGesture { pressing in } perform: { _onSelect(dexLabel: dexLabel) }
    }
    
    func _onSelect(dexLabel: ApiSwapDexLabel) {
        if dexLabel == bestOption {
            onSelect(nil)
        } else {
            onSelect(dexLabel)
        }
    }
    
    func borderStyle(dexLabel: ApiSwapDexLabel) -> AnyShapeStyle {
        if dexLabel == bestOption && selectedState != worseOption {
            return AnyShapeStyle(gradient)
        } else if dexLabel == selectedState {
            return AnyShapeStyle(Color(WTheme.tint))
        } else {
            return AnyShapeStyle(Color(WTheme.separatorDarkBackground).opacity(0.5))
        }
    }
    
    func labelStyle(dexLabel: ApiSwapDexLabel) -> AnyShapeStyle {
        if dexLabel == bestOption && selectedState != worseOption {
            return AnyShapeStyle(gradient)
        } else if dexLabel == selectedState {
            return AnyShapeStyle(Color(WTheme.tint))
        } else {
            return AnyShapeStyle(Color(WTheme.primaryLabel))
        }
    }
    
    var gradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientColorLeft", bundle: AirBundle),
            Color("EarnGradientColorRight", bundle: AirBundle),
        ], startPoint: .leading, endPoint: .trailing)
    }
    
    var secondaryGradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientDisabledColorLeft", bundle: AirBundle),
            Color("EarnGradientDisabledColorRight", bundle: AirBundle),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

struct SwapAgregatorContainerView: View {
    
    @ObservedObject var model: SwapDetailsVM
    
    @State private var show = false
    @State private var dismissing = false
    @State private var dy: CGFloat = 0
    
    @State private var buttonState: ApiSwapDexLabel?
    
    init(model: SwapDetailsVM) {
        self.model = model
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            Color.clear.ignoresSafeArea()
            if show {
                Color.black.opacity(dismissing ? 0 : 0.4).ignoresSafeArea()
                    .transition(.opacity)
                    .contentShape(.rect)
                    .onTapGesture {
                        if dy == 0 {
                            dismiss()
                        }
                    }
                    .gesture(dragGesture)
                contents
                    .transition(.asymmetric(
                        insertion: .scale(scale: 1.15).combined(with: .opacity),
                        removal: .identity
                    ))
                    .opacity(dismissing ? 0 : 1)
                    .gesture(dragGesture)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.3)) {
                show = true
            }
        }
        .onAppear {
            buttonState = model.selectedDex
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged({ drag in
                self.dy = drag.translation.height
            })
            .onEnded({ drag in
                if drag.predictedEndTranslation.height > 90 {
                    dismiss()
                } else {
                    withAnimation(.spring) {
                        dy = 0
                    }
                }
        })
    }
    
    var contents: some View {
        VStack(spacing: 0) {
            
            VStack(spacing: 8) {
                Text(lang("Built-in DEX Aggregator"))
                    .fontWeight(.semibold)
                    .font17h22()

                if let estimate = model.swapEstimate {
                    SwapAgregatorView(fromToken: model.fromToken, toToken: model.toToken, estimate: estimate, selectedState: buttonState, onSelect: { buttonState = $0 })
                        .font13()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)
            .background(Color(WTheme.modularBackground))
            
            Rectangle()
                .fill(Color(WTheme.separatorDarkBackground))
                .frame(height: 0.333)
            
            selectButton
        }
        .clipShape(.rect(cornerRadius: 14))
        .padding(.horizontal, 24)
        .offset(y: dy / 6)
        .buttonStyle(.plain)
    }
    
    var buttonTitle: String {
        switch buttonState {
        case .none:
            "Use Best Rate"
        case .dedust:
            "Use DeDust"
        case .ston:
            "Use STON.fi"
        }
    }
    
    @ViewBuilder
    var selectButton: some View {
        Button(action: onButtonTapped) {
            Text(buttonTitle)
                .fontWeight(.semibold)
                .font17h22()
                .foregroundStyle(buttonStyle)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(.rect)
                .background(Color(WTheme.modularBackground))
        }
    }
    
    var buttonStyle: some ShapeStyle {
        buttonState == nil ? AnyShapeStyle(gradient) : AnyShapeStyle(Color((WTheme.tint)))
    }
    
    var gradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientColorLeft", bundle: AirBundle),
            Color("EarnGradientColorRight", bundle: AirBundle),
        ], startPoint: .leading, endPoint: .trailing)
    }
    
    var secondaryGradient: LinearGradient {
        LinearGradient(colors: [
            Color("EarnGradientDisabledColorLeft", bundle: AirBundle),
            Color("EarnGradientDisabledColorRight", bundle: AirBundle),
        ], startPoint: .leading, endPoint: .trailing)
    }
    
    // MARK: Actions
    
    func onButtonTapped() {
        model.onPreferredDexChanged(buttonState)
        dismiss()
    }
    
    func dismiss() {
        let duration = 0.25
        withAnimation(.easeIn(duration: duration)) {
            dismissing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            topViewController()?.presentingViewController?.dismiss(animated: false)
        }
    }
}

