import SwiftUI
import UIComponents
import WalletContext

struct SwapDetailsContainer<Content: View>: View {
    @Binding var isExpanded: Bool
    var content: Content

    init(isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        InsetSection(horizontalPadding: 0) {
            header

            if isExpanded {
                content
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: isExpanded ? nil : 44, alignment: .top)
        .clipShape(.rect(cornerRadius: S.insetSectionCornerRadius))
        .tint(.accentColor)
        .animation(.spring(duration: isExpanded ? 0.45 : 0.3), value: isExpanded)
    }

    private var header: some View {
        Button(action: { isExpanded.toggle() }) {
            InsetCell {
                HStack {
                    Text(lang("Swap Details"))
                        .textCase(IOS_26_MODE_ENABLED ? nil : .uppercase)
                    Spacer()
                    Image.airBundle("RightArrowIcon")
                        .renderingMode(.template)
                        .rotationEffect(isExpanded ? .radians(-0.5 * .pi) : .radians(0.5 * .pi))
                }
                .font(IOS_26_MODE_ENABLED ? .system(size: 17, weight: .semibold) : .system(size: 13))
                .tint(.air.secondaryLabel)
                .foregroundStyle(Color.air.secondaryLabel)
            }
            .frame(minHeight: 44)
            .frame(height: 44)
            .contentShape(.rect)
        }
        .buttonStyle(InsetButtonStyle())
    }
}
