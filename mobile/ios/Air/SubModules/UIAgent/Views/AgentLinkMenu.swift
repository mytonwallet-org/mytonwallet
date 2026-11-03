import ContextMenuKit
import SafariServices
import UIKit
import WalletContext
import WalletCore

/// A held link lifts its complete URL above the blurred chat, with the actions directly below it.
@MainActor
final class AgentLinkMenu {
    private let linkAt: (CGPoint) -> URL?
    private let open: (URL) -> Void
    private weak var source: UIView?
    private var selectedURL: URL?
    private var location = CGPoint.zero
    private var preview: UIView?
    private var previewContent: UIView?
    private var interaction: ContextMenuInteraction?

    init(source: UIView, linkAt: @escaping (CGPoint) -> URL?, open: @escaping (URL) -> Void) {
        self.source = source
        self.linkAt = linkAt
        self.open = open
        let interaction = ContextMenuInteraction(
            triggers: [.longPress],
            sourcePortal: ContextMenuSourcePortal(
                sourceViewProvider: { [weak self] in self?.preview },
                mask: .roundedAttachmentRect(cornerRadius: 10)
            ),
            activationViewProvider: { [weak self] _ in self?.preview },
            activationHitTestProvider: { [weak self] _, point in
                guard let self, let url = self.linkAt(point),
                      AgentTextLinks.newsSourceURL(url.absoluteString) != nil else { return false }
                self.selectedURL = url
                self.location = point
                return true
            },
            onWillPresent: { [weak self] in
                guard let content = self?.previewContent else { return }
                UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                    content.alpha = 1
                }
            },
            onWillDismiss: { [weak self] in
                guard let content = self?.previewContent else { return }
                UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                    content.alpha = 0
                }
            },
            onDidDismiss: { [weak self] in
                self?.preview?.removeFromSuperview()
                self?.preview = nil
                self?.previewContent = nil
                self?.selectedURL = nil
            },
            configurationProvider: { [weak self] _ in self?.makeConfiguration() }
        )
        self.interaction = interaction
        interaction.attach(to: source)
    }

    private func makeConfiguration() -> ContextMenuConfiguration? {
        guard let source, let window = source.window, let url = selectedURL else { return nil }
        preview?.removeFromSuperview()
        let label = UILabel()
        label.text = url.absoluteString
        label.font = AgentMessageTextRenderer.baseFont
        label.textColor = source.tintColor
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        let maxWidth = window.bounds.width - window.safeAreaInsets.left - window.safeAreaInsets.right - 32
        let size = label.sizeThatFits(CGSize(width: maxWidth - 16, height: .greatestFiniteMagnitude))
        let width = min(maxWidth, ceil(size.width) + 16)
        let height = ceil(size.height) + 10
        let point = source.convert(location, to: window)
        let pill = UIView(frame: CGRect(
            x: min(max(point.x - 8, window.safeAreaInsets.left + 16),
                   window.bounds.maxX - window.safeAreaInsets.right - 16 - width),
            y: point.y - label.font.lineHeight / 2 - 5, width: width, height: height
        ))
        pill.isUserInteractionEnabled = false
        pill.accessibilityIdentifier = "AgentLinkURLPreview"
        let content = UIView(frame: pill.bounds)
        content.backgroundColor = .air.agentBubbleFill
        content.layer.cornerRadius = 10
        content.alpha = 0
        label.frame = content.bounds.insetBy(dx: 8, dy: 5)
        content.addSubview(label)
        pill.addSubview(content)
        window.addSubview(pill)
        preview = pill
        previewContent = content

        var actions: [ContextMenuItem] = [
            .action(ContextMenuAction(title: lang("Open"), icon: .system("globe")) { [weak self] in
                self?.open(url)
            }),
            .action(ContextMenuAction(title: lang("Open in Browser"), icon: .system("safari")) {
                UIApplication.shared.open(url)
            }),
            .action(ContextMenuAction(title: lang("Copy Link"), icon: .system("doc.on.doc")) {
                UIPasteboard.general.url = url
                AppActions.showToast(message: lang("Link Copied"))
            }),
        ]
        if SSReadingList.supportsURL(url) {
            actions.append(.action(ContextMenuAction(title: lang("Add to Reading List"), icon: .system("eyeglasses")) {
                do {
                    try SSReadingList.default()?.addItem(with: url, title: nil, previewText: nil)
                } catch {
                    AppActions.showError(error: DisplayError(text: lang("Something went wrong")))
                }
            }))
        }
        return ContextMenuConfiguration(
            rootPage: ContextMenuPage(items: actions),
            style: AgentMessageMenu.makeStyle(isOutgoing: false, isCentered: true),
            sourceRelocation: ContextMenuSourceRelocation()
        )
    }
}
