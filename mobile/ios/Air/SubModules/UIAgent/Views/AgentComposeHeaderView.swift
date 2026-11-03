import UIKit
import UIComponents
import WalletContext

/// The new chat's header that the Agent list shows while its question field is focused: the back button and the
/// "New Chat" title on its glass pill, placed where a chat's header has them. A chat that doesn't exist yet has nothing
/// in its menu, so there is no more button. Sending the question pushes a chat whose header takes over in place.
@MainActor
public final class AgentComposeHeaderView: UIView {
    /// Ends composing, returning to the list
    public var onThreads: (() -> Void)?

    public let threadsButton: AgentGlassCircleButton
    /// The title's glass pill, and the title inside it
    public let titlePill: UIView
    public var titleContent: UIView { pill.contentView }
    private let chatTitleView = AgentChatTitleView()
    private let pill: AgentChatTitlePill

    public override init(frame: CGRect) {
        threadsButton = AgentChatNavigation.makeButton(image: AgentChatNavigation.backImage, primaryAction: nil)
        pill = AgentChatTitlePill(titleView: chatTitleView)
        titlePill = pill
        super.init(frame: frame)
        threadsButton.button.accessibilityLabel = lang("Back")
        threadsButton.button.accessibilityIdentifier = AgentChatNavigation.threadsButtonIdentifier
        threadsButton.button.addAction(UIAction { [weak self] _ in self?.onThreads?() }, for: .primaryActionTriggered)
        chatTitleView.setTitle(lang("New Chat"), icon: nil, animated: false)
        for view in [pill, threadsButton] as [UIView] {
            view.autoresizingMask = []
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let size = AgentChatNavigation.buttonSize
        let y = bounds.midY - size / 2
        let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let leading = CGRect(x: isRTL ? bounds.maxX - size : bounds.minX, y: y, width: size, height: size)
        // Frames are set through bounds and center so a running morph's transforms stay intact
        place(threadsButton, in: leading)
        // The pill is centred on the bar, as a chat's title is, within the room the threads button leaves
        let available = max(0, bounds.width - 2 * (size + 8))
        let width = min(available, pill.intrinsicContentSize.width)
        var centerX = bounds.midX
        if let navigationBar = enclosingNavigationBar {
            let barCenter = CGPoint(x: navigationBar.bounds.inset(by: navigationBar.safeAreaInsets).midX, y: 0)
            centerX = navigationBar.convert(barCenter, to: self).x
        }
        centerX = min(max(centerX, size + 8 + width / 2), bounds.width - size - 8 - width / 2)
        place(pill, in: CGRect(x: centerX - width / 2, y: bounds.midY - AgentChatTitlePill.height / 2, width: width, height: AgentChatTitlePill.height))
    }

    private var enclosingNavigationBar: UINavigationBar? {
        var ancestor = superview
        while let view = ancestor {
            if let navigationBar = view as? UINavigationBar { return navigationBar }
            ancestor = view.superview
        }
        return nil
    }

    private func place(_ view: UIView, in frame: CGRect) {
        view.bounds = CGRect(origin: .zero, size: frame.size)
        view.center = CGPoint(x: frame.midX, y: frame.midY)
    }
}
