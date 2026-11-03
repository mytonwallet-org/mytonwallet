import SwiftUI
import WalletContext

public struct TradeNoticeView: View {
    let title: String
    let message: String
    var isWarning = false
    let isCompact: Bool
    var actionTitle: String?
    var onAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(title: String, message: String, isWarning: Bool = false, isCompact: Bool = false, actionTitle: String? = nil, onAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.isWarning = isWarning
        self.isCompact = isCompact
        self.actionTitle = actionTitle
        self.onAction = onAction
    }

    private var color: Color {
        isWarning ? .air.error : Color(UIColor(light: "#DE8C00", dark: "#FFAB2F"))
    }

    public var body: some View {
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
        .padding(.vertical, isCompact ? 7 : 12)
        .padding(.horizontal, isCompact ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background { WarningBackground(color: color, isCompact: isCompact) }
    }

    private var textContent: some View {
        (Text(title).fontWeight(.semibold) + Text((title.isEmpty ? "" : "\n") + message))
            .textStyle(.footnote, scaling: .dynamic)
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
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("tokenTrade.hintAction")
        }
    }

}
