import UIKit
import UIComponents
import UIHome
import WalletCore
import WalletContext

@MainActor
enum RootContainerLayout: String {
    case tab
    case split

    private static let fallbackSplitMinimumWidth: CGFloat = 700

    static func preferred(for traitCollection: UITraitCollection, fallbackWidth: CGFloat) -> RootContainerLayout {
        switch traitCollection.horizontalSizeClass {
        case .regular:
            return .split
        case .compact:
            return .tab
        case .unspecified:
            return preferred(forFallbackWidth: fallbackWidth)
        @unknown default:
            return preferred(forFallbackWidth: fallbackWidth)
        }
    }

    static var fallbackWindowWidth: CGFloat {
        UIApplication.shared.sceneKeyWindow?.bounds.width
            ?? UIApplication.shared.anySceneKeyWindow?.bounds.width
            ?? UIApplication.shared.connectedWindowScene?.coordinateSpace.bounds.width
            ?? 0
    }

    private static func preferred(forFallbackWidth width: CGFloat) -> RootContainerLayout {
        width >= fallbackSplitMinimumWidth ? .split : .tab
    }
}

@MainActor
final class AdaptiveRootViewController: UIViewController, VisibleContentProviding {
    private var activeContentViewController: UIViewController?
    private var activeLayout: RootContainerLayout?

    var visibleContentProviderViewController: UIViewController {
        activeContentViewController ?? self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        updateLayoutIfNeeded()

        AppTabManager.shared.addObserver(self) { [weak self] ids in
            self?.applyTabConfigurationToActiveContainer(ids)
        }
    }

    nonisolated deinit {
        MainActor.assumeIsolated {
            AppTabManager.shared.removeObserver(self)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateLayoutIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateLayoutIfNeeded()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateLayoutIfNeeded()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayoutIfNeeded()
    }

    private func updateLayoutIfNeeded() {
        let width = currentWidth
        guard width > 0 || traitCollection.horizontalSizeClass != .unspecified else { return }

        let layout = RootContainerLayout.preferred(for: traitCollection, fallbackWidth: width)
        guard layout != activeLayout else { return }

        let navigationState = activeContentViewController.flatMap(AdaptiveRootNavigationState.init)
        let contentViewController = makeContentViewController(for: layout)
        contentViewController.loadViewIfNeeded()
        applyTabConfiguration(to: contentViewController, ids: AppTabManager.shared.orderedTabIds)
        navigationState?.apply(to: contentViewController, layout: layout)
        install(contentViewController, layout: layout, width: width)
    }

    private var currentWidth: CGFloat {
        if view.bounds.width > 0 {
            return view.bounds.width
        }
        return view.window?.bounds.width ?? RootContainerLayout.fallbackWindowWidth
    }

    private func makeContentViewController(for layout: RootContainerLayout) -> UIViewController {
        switch layout {
        case .tab:
            HomeTabBarController(
                navControllerFactory: { [layout] id in
                    AppTabManager.shared.makeNavigationController(for: id, layout: layout)
                },
                tabLabelProvider: { id in
                    AppTabManager.shared.title(for: id)
                }
            )
        case .split:
            SplitRootViewController()
        }
    }

    private func install(_ contentViewController: UIViewController, layout: RootContainerLayout, width: CGFloat) {
        if let activeContentViewController {
            activeContentViewController.willMove(toParent: nil)
            activeContentViewController.view.removeFromSuperview()
            activeContentViewController.removeFromParent()
        }

        activeLayout = layout
        activeContentViewController = contentViewController

        addChild(contentViewController)
        contentViewController.view.frame = view.bounds
        contentViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(contentViewController.view)
        contentViewController.didMove(toParent: self)

        StartupTrace.mark(
            "rootContainer.activeRoot.layout",
            details: "layout=\(layout.rawValue) horizontalSizeClass=\(horizontalSizeClassDescription) width=\(Int(width.rounded()))"
        )
    }

    private var horizontalSizeClassDescription: String {
        switch traitCollection.horizontalSizeClass {
        case .compact:    "compact"
        case .regular:    "regular"
        case .unspecified: "unspecified"
        @unknown default: "unknown"
        }
    }

    private func applyTabConfiguration(to viewController: UIViewController, ids: [AppTabId]) {
        switch viewController {
        case let tbc as HomeTabBarController:
            tbc.applyTabConfiguration(ids)
        case let split as SplitRootViewController:
            split.applyTabConfiguration(ids)
        default:
            break
        }
    }

    private func applyTabConfigurationToActiveContainer(_ ids: [AppTabId]) {
        guard let vc = activeContentViewController else { return }
        applyTabConfiguration(to: vc, ids: ids)
    }
}

/// Captures the navigation stacks of all live tabs when the root layout is about to change
/// (e.g. iPad rotation from split → compact), then restores them into the new container.
@MainActor
private struct AdaptiveRootNavigationState {
    let selectedTabId: AppTabId
    let homePath: [AdaptiveRootHomeStackItem]?
    let focusedHomeAccountId: String?
    let navigationStacks: [AppTabId: [UIViewController]]

    init?(viewController: UIViewController) {
        switch viewController {
        case let tabBarController as HomeTabBarController:
            self = Self(tabBarController: tabBarController)
        case let splitRootViewController as SplitRootViewController:
            self = Self(splitRootViewController: splitRootViewController)
        default:
            return nil
        }
    }

    private init(tabBarController: HomeTabBarController) {
        selectedTabId = tabBarController.currentTabId
        var homePath: [AdaptiveRootHomeStackItem]?
        var navigationStacks: [AppTabId: [UIViewController]] = [:]
        for id in AppTabManager.shared.orderedTabIds {
            if id == .wallet {
                if let stack = tabBarController.takeNavigationStack(for: id, keepingRoot: true) {
                    homePath = Self.homePath(from: stack)
                }
            } else if let stack = tabBarController.takeNavigationStack(for: id, keepingRoot: false) {
                navigationStacks[id] = stack
            }
        }
        self.homePath = homePath
        self.focusedHomeAccountId = Self.focusedAccountId(from: homePath)
        self.navigationStacks = navigationStacks
    }

    private init(splitRootViewController: SplitRootViewController) {
        selectedTabId = splitRootViewController.currentTabId
        var homePath: [AdaptiveRootHomeStackItem]?
        var navigationStacks: [AppTabId: [UIViewController]] = [:]
        for id in AppTabManager.shared.orderedTabIds {
            if id == .wallet {
                if let stack = splitRootViewController.takeNavigationStack(for: id, keepingRoot: true) {
                    homePath = Self.homePath(from: stack)
                }
            } else if let stack = splitRootViewController.takeNavigationStack(for: id, keepingRoot: false) {
                navigationStacks[id] = stack
            }
        }
        self.homePath = homePath
        self.focusedHomeAccountId = Self.focusedAccountId(from: homePath)
        self.navigationStacks = navigationStacks
    }

    func apply(to viewController: UIViewController, layout: RootContainerLayout) {
        switch viewController {
        case let tabBarController as HomeTabBarController:
            if let homeStack = homeStack(for: layout) {
                tabBarController.setNavigationStack(homeStack, for: .wallet)
            }
            for (id, stack) in navigationStacks {
                tabBarController.setNavigationStack(stack, for: id)
            }
            let orderedIds = AppTabManager.shared.orderedTabIds
            if let idx = orderedIds.firstIndex(of: selectedTabId) {
                tabBarController.selectedIndex = idx
            }
        case let splitRootViewController as SplitRootViewController:
            if let homeStack = homeStack(for: layout) {
                splitRootViewController.setNavigationStack(homeStack, for: .wallet)
            }
            for (id, stack) in navigationStacks {
                splitRootViewController.setNavigationStack(stack, for: id)
            }
            if let focusedHomeAccountId {
                splitRootViewController.focusSidebarAccount(accountId: focusedHomeAccountId, animated: false)
            }
            splitRootViewController.select(tab: selectedTabId)
        default:
            break
        }
    }

    private static func homePath(from stack: [UIViewController]) -> [AdaptiveRootHomeStackItem] {
        stack.enumerated().compactMap { index, viewController in
            if let homeRoot = viewController as? (UIViewController & HomeRootLayoutMigrating) {
                homeRoot.prepareForRootLayoutMigration()
                if index == 0, homeRoot.homeRootAccountSource == .current {
                    return nil
                }
                return .home(accountSource: homeRoot.homeRootAccountSource)
            }
            return .viewController(viewController)
        }
    }

    private static func focusedAccountId(from homePath: [AdaptiveRootHomeStackItem]?) -> String? {
        guard let homePath else { return nil }
        for item in homePath.reversed() {
            if case .home(let accountSource) = item,
               case .accountId(let accountId) = accountSource {
                return accountId
            }
        }
        return nil
    }

    private func homeStack(for layout: RootContainerLayout) -> [UIViewController]? {
        guard let homePath else { return nil }
        return [makeHomeRoot(for: layout, accountSource: .current)] + homePath.map { item in
            switch item {
            case .home(let accountSource):
                makeHomeRoot(for: layout, accountSource: accountSource)
            case .viewController(let viewController):
                viewController
            }
        }
    }

    private func makeHomeRoot(for layout: RootContainerLayout, accountSource: AccountSource) -> UIViewController {
        switch layout {
        case .tab:   HomeVC(accountSource: accountSource)
        case .split: SplitHomeVC(accountSource: accountSource)
        }
    }
}

private enum AdaptiveRootHomeStackItem {
    case home(accountSource: AccountSource)
    case viewController(UIViewController)
}
