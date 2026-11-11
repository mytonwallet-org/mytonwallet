import ContextMenuKit
import Perception
import SwiftUI
import UIKit
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

/// A navigation bar button that presents a trade screen's info menu.
@MainActor public struct TradeInfoBarButton {
    public let item: UIBarButtonItem
    public let button: UIButton
    /// The owner keeps the interaction alive while the button is visible.
    public let interaction: ContextMenuInteraction
}

extension TradeInfoMenu {
    public static func configuration(items: [ContextMenuItem]) -> ContextMenuConfiguration {
        ContextMenuConfiguration(rootPage: ContextMenuPage(items: items), backdrop: .none,
            style: ContextMenuStyle(minWidth: 242, maxWidth: 300, glassTint: .strong,
                                    listVerticalPadding: 10, separatorHeight: 20))
    }

    /// A glass bar button that shows the menu on tap or long press.
    public static func barButton(accessibilityIdentifier: String,
                                 configuration: @escaping @MainActor () -> ContextMenuConfiguration?) -> TradeInfoBarButton {
        let button = UIButton(type: .system)
        if #available(iOS 26, *), IOS_26_MODE_ENABLED {
            var configuration = UIButton.Configuration.glass()
            configuration.cornerStyle = .capsule
            configuration.contentInsets = .zero
            configuration.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .medium)
            button.configuration = configuration
        }
        button.tintColor = .label
        button.accessibilityIdentifier = accessibilityIdentifier
        // Keep navigation-bar sizing independent of the icon's intrinsic size.
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        button.frame = container.bounds
        button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(button)
        let item = UIBarButtonItem(customView: container)
        if #available(iOS 26, *) { item.hidesSharedBackground = true }
        if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
        let interaction = ContextMenuInteraction(triggers: [.tap, .longPress], presentationMode: .zoomPopover) { _ in
            configuration()
        }
        interaction.attach(to: button)
        button.addAction(UIAction { [weak interaction] _ in interaction?.present() }, for: .primaryActionTriggered)
        return TradeInfoBarButton(item: item, button: button, interaction: interaction)
    }
}
