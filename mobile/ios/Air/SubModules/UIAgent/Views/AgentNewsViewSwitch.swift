import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The News thread's "All News | Digests" switch in the header, in the title's place: the root header's tabs on their
/// glass capsule, sized by their titles
@MainActor
enum AgentNewsViewSwitch {
    private static let views: [ApiAgentV2NewsFeedView] = [.all, .digests]

    static func makeControl(
        selection: ApiAgentV2NewsFeedView,
        onSelect: @escaping (ApiAgentV2NewsFeedView) -> Void
    ) -> WSegmentedControl {
        let model = SegmentedControlModel(
            items: views.map { view in
                SegmentedControlItem(
                    id: view.rawValue,
                    title: getTitle(of: view),
                    isDeletable: false,
                    accessibilityIdentifier: getAccessibilityIdentifier(of: view),
                    viewController: AgentNewsViewSwitchContent()
                )
            },
            selection: .init(item1: selection.rawValue),
            primaryColor: .tintColor,
            capsuleColor: .air.thumbBackground,
            style: .compactRootHeader
        )
        model.onSelect = { item in
            guard let view = ApiAgentV2NewsFeedView(rawValue: item.id) else { return }
            onSelect(view)
        }
        let control = WSegmentedControl(model: model, isGlassInteractive: true)
        if #available(iOS 26, *) {
            control.tintAdjustmentMode = .normal
        }
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }

    static func select(_ view: ApiAgentV2NewsFeedView, in control: WSegmentedControl) {
        guard control.model.selectedItem?.id != view.rawValue else { return }
        control.model.selection = .init(item1: view.rawValue)
    }

    private static func getTitle(of view: ApiAgentV2NewsFeedView) -> String {
        switch view {
        case .all: lang("$agent_news_view_all")
        case .digests: lang("$agent_news_view_digests")
        }
    }

    private static func getAccessibilityIdentifier(of view: ApiAgentV2NewsFeedView) -> String {
        switch view {
        case .all: "AgentNewsViewAll"
        case .digests: "AgentNewsViewDigests"
        }
    }
}

/// The switch selects a view of the one feed, so its segments have no pages of their own
private final class AgentNewsViewSwitchContent: UIViewController, WSegmentedControllerContent {
    var onScroll: ((CGFloat) -> Void)?
    var scrollingView: UIScrollView? { nil }
    func scrollToTop(animated: Bool) {}
    func calculateHeight(isHosted: Bool) -> CGFloat { 0 }
}
