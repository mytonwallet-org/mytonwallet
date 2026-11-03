import ContextMenuKit
import Perception
import SwiftUI
import WalletContext

@MainActor public enum TradeInfoMenu {
    public static func row(title: String, value: @escaping () -> String, help: String? = nil,
                            action: (() -> Void)? = nil, showsChevron: Bool = true,
                            showsInfo: Bool = false) -> ContextMenuItem {
        .custom(.swiftUI(preferredWidth: 242, sizing: .automatic(minHeight: 60),
                        interaction: action.map { .selectable(allowsContentInteraction: true, handler: $0) } ?? .contentHandlesTouches) { _ in
            WithPerceptionTracking {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .lastTextBaseline, spacing: 5) {
                            Text(title)
                                .font(.system(size: 17))
                                .foregroundStyle(Color.air.primaryLabel)
                            if let help {
                                Button {
                                    topViewController()?.showTip(title: title, message: help)
                                } label: {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color.air.secondaryLabel.opacity(0.6))
                                        .padding(6)
                                        .contentShape(.rect)
                                }
                                .padding(-6)
                                .buttonStyle(.plain)
                                .accessibilityLabel(title + ", " + lang("Info"))
                            } else if showsInfo {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.air.secondaryLabel.opacity(0.6))
                            }
                        }
                        Text(value().nilIfEmpty ?? "—")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.air.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if action != nil, showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.air.primaryLabel)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
        })
    }
}
