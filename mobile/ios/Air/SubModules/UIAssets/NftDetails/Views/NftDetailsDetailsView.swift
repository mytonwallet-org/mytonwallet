import SwiftUI
import UIComponents
import WalletContext
import WalletCore

private let tableBorderWidth: CGFloat = 1
private let tableBorderColor: Color = Color(UIColor(light: "DEDDE0", dark: "2E2D20"))

let animatedTransition: AnyTransition = .asymmetric(
    insertion: .opacity.animation(.linear(duration: 0.09)),
    removal: .opacity.animation(.linear(duration: 0.08).delay(0.01))
)

struct NftDetailsDetailsView: View {
    
    @ObservedObject var viewModel: NftDetailsViewModel
    @State private var isDebugMenuPresented = false
    
    var nft: ApiNft { viewModel.nft }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            descriptionSection
//            debugSettingsButton
            attributesSection
                .transition(animatedTransition)
                .id(nft.id)
                
        }
        .padding(.top, viewModel.isExpanded ? 16 : 8)
//        .sheet(isPresented: $isDebugMenuPresented) {
//            if #available(iOS 18, *) {
//                DebugSettingsView()
//                    .presentationDetents([.fraction(0.67)])
//                    .presentationBackgroundInteraction(.enabled)
//            }
//        }
    }
    
    @ViewBuilder
    var descriptionSection: some View {
        if let description = nft.description?.nilIfEmpty {
            InsetSection {
                InsetCell {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang("description"))
                            .font(.system(size: 14))
                        
                        Text(description)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .font17h22()
                            .foregroundStyle(Color(WTheme.primaryLabel))
                            .frame(maxWidth: .infinity, alignment: .leading)
//                            .transition(animatedTransition)
                            .contentTransition(.opacity)
//                            .id(nft.id)
                    }
                    .padding(.bottom, -1)
                }
            }
        }
    }
    
    @ViewBuilder
    var attributesSection: some View {
        if let attributes = nft.metadata?.attributes?.nilIfEmpty {
            VStack(spacing: 4) {
                Text(lang("Attributes"))
                    .font13()
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(Color(WTheme.secondaryLabel))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 3)
                
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(attributes, id: \.self) { attr in
                        GridRow {
                            Text(attr.trait_type)
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: 120, alignment: .leading)
                                .frame(height: 40)
                                .background {
                                    Color(UIColor(light: "F2F2F6", dark: "121216"))
                                }
                                .overlay(alignment: .trailing) {
                                    tableBorderColor
                                        .frame(width: tableBorderWidth)
                                }
                                .frame(height: 40)
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(attr.value)
                                    .lineLimit(1)
                                
//                                if let rarity = attr.rarity {
//                                    Text(formatAmountText(amount: rarity * 100, decimalsCount: 1) + "%")
//                                        .padding(.horizontal, 6)
//                                        .padding(.vertical, 3)
//                                        .foregroundStyle(Color(WTheme.tint))
//                                        .background(Color(WTheme.tint).opacity(0.1), in: .capsule)
//                                        .font(.system(size: 11))
//                                        .offset(y: -1)
//                                        .padding(.vertical, -5) // don't mess with vertical cell sizing
//                                }
                                    
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 15))
                        .overlay(alignment: .bottom) {
                            if attr != attributes.last {
                                tableBorderColor
                                    .frame(height: tableBorderWidth)
                            }
                        }
                    }
                }
                .background {
                    Color(WTheme.groupedItem)
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tableBorderColor, lineWidth: tableBorderWidth)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var debugSettingsButton: some View {
        Button {
            isDebugMenuPresented = true
        } label: {
            Text(lang("Debug Settings"))
                .font13()
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color(WTheme.tint))
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - DebugSettingsView

private struct DebugSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: Tunable parameters backed by AppStorage
    @AppStorage("cf_animateTitleChange") private var animateTitleChange: Bool = false
    private typealias D = CoverFlowDefaults
    @AppStorage("cf_itemSpacing") private var itemSpacing: Double = D.itemSpacing
    @AppStorage("cf_rotationSensitivity") private var rotationSensitivity: Double = D.rotationSensitivity
    @AppStorage("cf_rotationAngle") private var rotationAngle: Double = D.rotationAngle
    @AppStorage("cf_offsetSensitivity") private var offsetSensitivity: Double = D.offsetSensitivity
    @AppStorage("cf_offsetMultiplier") private var offsetMultiplier: Double = D.offsetMultiplier
    @AppStorage("cf_offsetMultiplier2") private var offsetMultiplier2: Double = D.offsetMultiplier2

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Toggle("Animate Title Change", isOn: $animateTitleChange)
                }

                Section("Presets") {
                    Button("Apply Fast Preset") { applyPreset(.fast) }
                    Button("Apply Standard Preset") { applyPreset(.standard) }
                    Button("Apply Slow Preset") { applyPreset(.slow) }
                }

                Section {
                    Button("Reset All", role: .destructive) { resetAll() }
                }

                Section("Parameters") {
                    parameterSlider(title: "Item Spacing", value: $itemSpacing, range: -200...200, step: 1)
                    parameterSlider(title: "Rotation Sensitivity", value: $rotationSensitivity, range: 0...10, step: 0.1)
                    parameterSlider(title: "Rotation Angle", value: $rotationAngle, range: -180...180, step: 1)
                    parameterSlider(title: "Offset Sensitivity", value: $offsetSensitivity, range: 0...10, step: 0.1)
                    parameterSlider(title: "Offset Multiplier", value: $offsetMultiplier, range: -200...200, step: 1)
                    parameterSlider(title: "Offset Multiplier 2", value: $offsetMultiplier2, range: -200...200, step: 1)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationBarTitle(Text(lang("Debug Settings")), displayMode: .inline)
        }
    }

    // MARK: - Helper views
    private func parameterSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    // MARK: - Presets & Reset
    private enum Preset { case slow, standard, fast }

    private func applyPreset(_ preset: Preset) {
        switch preset {
        case .slow:
            itemSpacing = 0
            rotationSensitivity = 1.7
            rotationAngle = -15
            offsetSensitivity = 1
            offsetMultiplier = -60
            offsetMultiplier2 = -110
        case .standard:
            itemSpacing = D.itemSpacing
            rotationSensitivity = D.rotationSensitivity
            rotationAngle = D.rotationAngle
            offsetSensitivity = D.offsetSensitivity
            offsetMultiplier = D.offsetMultiplier
            offsetMultiplier2 = D.offsetMultiplier2
        case .fast:
            itemSpacing = -110
            rotationSensitivity = 4
            rotationAngle = -15
            offsetSensitivity = 6
            offsetMultiplier = 52
            offsetMultiplier2 = 0
        }
    }

    private func resetAll() {
        let defaults = UserDefaults.standard
        [
            "cf_animateTitleChange",
            "cf_itemSpacing",
            "cf_rotationSensitivity",
            "cf_rotationAngle",
            "cf_offsetSensitivity",
            "cf_offsetMultiplier",
            "cf_offsetMultiplier2",
        ].forEach { defaults.removeObject(forKey: $0) }
    }
}
