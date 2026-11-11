import ContextMenuKit
import UIKit
import UIComponents
import UIHome
import WalletContext
import WalletCore

/// Lives in the selected root's view, so native pushes also transition the tabs away.
@available(iOS 27.1, *)
@MainActor
final class SplitRootToolbarView: UIView {
    /// The tabs in the order the bar shows them, which a drag on the bar changes
    var tabIds: [AppTabId] { tabBar.itemIds.map { AppTabId($0) } }
    let accountButton = WalletAccountButton()
    let tabBar: WVerticalTabBar
    weak var navigationContainer: UIView?
    var onLayout: (() -> Void)?
    private var accountMenuInteraction: ContextMenuInteraction?
    private var showsAccount = true
    private var accountAnimationID: UUID?

    init(tabIds: [AppTabId]) {
        tabBar = WVerticalTabBar(items: tabIds.compactMap { id in
            guard let registration = AppTabManager.shared.registration(for: id) else { return nil }
            return .init(id: id.rawValue, title: registration.titleProvider(), image: registration.compactIcon)
        })
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        accountButton.translatesAutoresizingMaskIntoConstraints = true
        addSubview(accountButton)
        addSubview(tabBar)
        let interaction = ContextMenuInteraction(triggers: [.longPress]) { sourceView in
            SwitchAccountMenu.makeConfiguration(sourceView: sourceView)
        }
        interaction.attach(to: accountButton)
        accountMenuInteraction = interaction
        NotificationCenter.default.addObserver(self, selector: #selector(toolbarSettingsChanged),
            name: ToolbarSettings.didChangeNotification, object: nil)
        updateAccountPlacement(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func toolbarSettingsChanged() {
        updateAccountPlacement(animated: true)
    }

    private func updateAccountPlacement(animated: Bool) {
        let showsAccount = !ToolbarSettings.configuration().showsAccounts
        guard self.showsAccount != showsAccount else { return }
        layoutIfNeeded()
        self.showsAccount = showsAccount
        let animationID = UUID()
        accountAnimationID = animationID
        accountButton.isHidden = false
        accountButton.isUserInteractionEnabled = showsAccount
        accountButton.accessibilityElementsHidden = !showsAccount
        let updates = {
            self.accountButton.setToolbarAppearance(showsBackground: showsAccount, showsContent: showsAccount)
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self, self.accountAnimationID == animationID else { return }
            self.accountButton.isHidden = !showsAccount
        }
        if animated, window != nil, UIView.areAnimationsEnabled, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.4, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: updates, completion: completion)
        } else {
            UIView.performWithoutAnimation(updates)
            completion(true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let container = navigationContainer, isDescendant(of: container) else { return }
        let isLTR = effectiveUserInterfaceLayoutDirection == .leftToRight
        let isLeft = traitCollection.verticalBarEdge == .leading ? isLTR : !isLTR
        let region = container.layoutGuide(for: .bar(onEdge: isLeft ? .left : .right, extent: 48)).layoutFrame
        guard !region.isEmpty else { return }
        let origin = convert(CGPoint(x: region.midX - 24, y: max(region.minY, container.bounds.minY + 24)), from: container)
        accountButton.frame = CGRect(origin: origin, size: CGSize(width: 48, height: 48))
        tabBar.frame = CGRect(x: origin.x, y: origin.y + (showsAccount ? 60 : 0), width: 48, height: tabBar.intrinsicContentSize.height)
        tabBar.isOnLeftEdge = isLeft
        onLayout?()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}
