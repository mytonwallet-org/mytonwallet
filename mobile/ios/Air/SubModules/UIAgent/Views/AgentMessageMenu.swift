import ContextMenuKit
import UIComponents
import UIKit
import WalletContext

/// The menu of a message, a news post in a chat and a News card, as Telegram's message menu: it hangs 7 pt under the
/// bubble on the bubble's side, headed by the message's date, while the pressed bubble slides into view under it, out
/// from behind the header and the bottom bar. A centred row, such as a date line, has its menu centred under it, as
/// Telegram's date menu is.
@MainActor
enum AgentMessageMenu {
    static func makeStyle(isOutgoing: Bool, isCentered: Bool = false) -> ContextMenuStyle {
        var style = ContextMenuStyle.default
        style.minWidth = 180
        style.maxWidth = 250
        style.sourceSpacing = 7
        style.horizontalAlignment = isCentered ? .center : isOutgoing ? .trailing : .leading
        // Rows without an icon, as a news post's sources, start under the separator's start
        style.alignsPlainTitlesWithSeparators = true
        return style
    }

    static func makeConfiguration(
        items: [ContextMenuItem],
        date: Date,
        isOutgoing: Bool,
        isCentered: Bool = false,
        accessory: ContextMenuAccessory? = nil,
        contentAreaInWindow: CGRect?
    ) -> ContextMenuConfiguration {
        let (dateText, timeText) = AgentModel.formatChatDate(for: date)
        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: [makeHeaderRow(text: "\(dateText), \(timeText)")] + items),
            style: makeStyle(isOutgoing: isOutgoing, isCentered: isCentered),
            accessory: accessory,
            sourceRelocation: ContextMenuSourceRelocation(contentAreaInWindow: contentAreaInWindow)
        )
    }

    /// `scrollView`'s area between its header and what covers its bottom, in the window's coordinates
    static func getVisibleArea(of scrollView: UIScrollView, bottom: CGFloat? = nil) -> CGRect? {
        guard scrollView.window != nil else { return nil }
        let top = scrollView.bounds.minY + scrollView.adjustedContentInset.top
        let bottom = bottom ?? scrollView.bounds.maxY - scrollView.adjustedContentInset.bottom
        guard bottom > top else { return nil }
        return scrollView.convert(
            CGRect(x: scrollView.bounds.minX, y: top, width: scrollView.bounds.width, height: bottom - top),
            to: nil
        )
    }

    private static func makeHeaderRow(text: String) -> ContextMenuItem {
        .custom(ContextMenuCustomRow(sizing: .fixed(height: 30), interaction: .contentHandlesTouches) { _ in
            let container = UIView()
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = text
            label.font = .systemFont(ofSize: 13)
            label.textColor = .air.secondaryLabel
            label.isAccessibilityElement = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            ])
            return container
        })
    }
}
