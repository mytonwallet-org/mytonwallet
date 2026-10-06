import SwiftUI
import UIComponents
import WalletContext

struct TokenTradeNoticeView: View {
    let title: String
    let message: String
    var isWarning = false
    var actionTitle: String?
    var onAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var color: Color {
        isWarning ? .air.error : Color(UIColor(light: "#DE8C00", dark: "#FFAB2F"))
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    textContent
                    actionButton
                }
            } else {
                HStack(spacing: 12) {
                    textContent
                    actionButton
                }
            }
        }
        .foregroundStyle(color)
        .padding(.vertical, 12)
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(color.opacity(0.12))
        .overlay(alignment: .leading) { sideAccent }
        .overlay(alignment: .trailing) { sideAccent.scaleEffect(x: -1, y: 1) }
        .clipShape(.rect(cornerRadius: 26))
    }

    private var textContent: some View {
        (Text(title).fontWeight(.semibold) + Text("\n" + message))
            .font(.footnote)
            .lineSpacing(2)
            .padding(.vertical, 2)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actionButton: some View {
        if let actionTitle, let onAction {
            Button(action: onAction) {
                Text(actionTitle)
                    .textStyle(.supportingBold, scaling: .dynamic)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(color.opacity(0.12), in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            .accessibilityIdentifier("tokenTrade.hintAction")
        }
    }

    private var sideAccent: some View {
        Image("TokenTradeNoticeEdge", bundle: AirBundle)
            .renderingMode(.template)
            .resizable(capInsets: EdgeInsets(top: 29, leading: 0, bottom: 29, trailing: 0))
            .foregroundStyle(color)
            .frame(width: 53)
            .padding(.vertical, -4)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
