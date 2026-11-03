import UIKit
import UIAgent

/// While the Agent list's question field is focused, the root header becomes a new chat's header: the tabs' capsule
/// flows into the title's pill, the threads button grows out of it and the wallet avatar dissolves, as the header's
/// capsules move in a push into a chat. Losing focus plays it backwards.
@MainActor
final class AgentComposeHeaderSwap {
    private let header = AgentComposeHeaderView()
    private weak var tabs: UIView?
    private weak var avatar: UIView?
    private var listBar: (@MainActor () -> AgentHeaderPlatterTransition.Bar)?
    private var transition: AgentHeaderPlatterTransition?
    private(set) var isActive = false

    init(onThreads: @escaping () -> Void) {
        header.onThreads = onThreads
        applyState(isActive: false)
    }

    /// Places the new chat's header over `container`, the view that holds the tabs and the avatar. `listBar` gives
    /// the list header's capsules for the transition.
    func install(
        in container: UIView,
        tabs: UIView,
        avatar: UIView,
        listBar: @escaping @MainActor () -> AgentHeaderPlatterTransition.Bar
    ) {
        self.tabs = tabs
        self.avatar = avatar
        self.listBar = listBar
        guard header.superview !== container else { return }
        header.removeFromSuperview()
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    func setActive(_ isActive: Bool, animated: Bool) {
        transition?.cancel()
        transition = nil
        guard isActive != self.isActive else {
            applyState(isActive: isActive)
            return
        }
        self.isActive = isActive
        guard animated, let window = header.window, let listBar else {
            applyState(isActive: isActive)
            return
        }
        let composeBar: @MainActor () -> AgentHeaderPlatterTransition.Bar = { [weak self] in
            self?.makeBar() ?? AgentHeaderPlatterTransition.Bar()
        }
        // The new chat's title pill swells a third as wide as it turns back into the tabs, as tall as ever
        let transition = AgentHeaderPlatterTransition(
            outgoing: isActive ? listBar : composeBar,
            incoming: isActive ? composeBar : listBar,
            pillSwellStrength: isActive ? CGSize(width: 1, height: 1) : CGSize(width: 1 / 3, height: 1)
        )
        self.transition = transition
        transition.run(in: window) {
            applyState(isActive: isActive)
            header.superview?.layoutIfNeeded()
        }
    }

    /// The new chat's header capsules, for a transition to another header
    func makeBar() -> AgentHeaderPlatterTransition.Bar {
        AgentHeaderPlatterTransition.Bar(
            leading: .button(header.threadsButton),
            pill: .snapshot(header.titlePill, content: header.titleContent)
        )
    }

    /// The header as it rests: the new chat's header over the hidden tabs and avatar, or neither
    private func applyState(isActive: Bool) {
        header.superview?.bringSubviewToFront(header)
        header.isHidden = !isActive
        header.isUserInteractionEnabled = isActive
        header.accessibilityElementsHidden = !isActive
        for view in [header.threadsButton, header.titlePill] {
            view.alpha = 1
            view.transform = .identity
        }
        for view in [tabs, avatar].compactMap({ $0 }) {
            view.alpha = isActive ? 0 : 1
            view.transform = .identity
            view.isUserInteractionEnabled = !isActive
            view.accessibilityElementsHidden = isActive
        }
    }
}
