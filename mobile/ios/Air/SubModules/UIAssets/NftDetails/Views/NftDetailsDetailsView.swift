import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Perception

private let tableBorderWidth: CGFloat = 1
private let tableBorderColor: Color = Color(UIColor(light: "DEDDE0", dark: "2E2D20"))

private struct AttributeValueColumnModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                    length * 0.5
                }
        } else {
            content
        }
    }
}

let animatedTransition: AnyTransition = .asymmetric(
    insertion: .opacity.animation(.linear(duration: 0.09)),
    removal: .opacity.animation(.linear(duration: 0.08).delay(0.01))
)

struct NftDetailsDetailsView: View {
    
    var viewModel: NftDetailsViewModel
    @State private var isDebugMenuPresented = false
    
    var nft: ApiNft { viewModel.nft }
    
    var body: some View {
        WithPerceptionTracking {
            @Perception.Bindable var viewModel = viewModel
            VStack(alignment: .leading, spacing: 24) {
                descriptionSection
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
    }
    
    @ViewBuilder
    var descriptionSection: some View {
        if let description = nft.description?.nilIfEmpty {
            InsetSection {
                InsetCell {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang("Description").lowercased())
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
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: 180, alignment: .leading)
                                .frame(height: 40, alignment: .leading)
                                .background {
                                    Color(UIColor(light: "F2F2F6", dark: "121216"))
                                }
                                .overlay(alignment: .trailing) {
                                    tableBorderColor
                                        .frame(width: tableBorderWidth)
                                }
                            
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(attr.value)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 40)
                            .modifier(AttributeValueColumnModifier())
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
            Text(lang("Developer Options"))
                .font13()
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color(WTheme.tint))
        }
        .padding(.horizontal, 32)
    }
}
