import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

public final class MarketVC: WViewController, WalletCoreData.EventsObserver, Sendable {
    private let showsLargeTitle: Bool
    private let usesTopTabsChrome: Bool
    private let model = MarketScreenModel()
    private let navigationHeader = NavigationHeader2()
    private let largeTitleLabel = UILabel()
    private var navigationBarBlurView: UIView?
    private var lastScrollOffset: CGFloat = 0
    private var isLargeTitleVisible: Bool?
    private var isNavigationTitleVisible: Bool?
    private var didCompleteInitialAppearance = false

    public init(showsLargeTitle: Bool = true, usesTopTabsChrome: Bool = false) {
        self.showsLargeTitle = showsLargeTitle
        self.usesTopTabsChrome = usesTopTabsChrome
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = lang("Market")
        WalletCoreData.add(eventObserver: self)
        model.start()
        view.backgroundColor = .air.groupedBackground

        let screen = MarketScreen(
            model: model,
            onScrollOffsetChange: { [weak self] offset in
                self?.scrollOffsetDidChange(offset)
            },
            onSeeAll: { [weak self] section in
                self?.showAllTokens(in: section)
            },
            onSelectToken: { token in
                AppActions.showTokenBySlug(token.token.slug)
            }
        )
        let hostingController = LayoutMarginsHostingController(rootView: screen)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addStretchedToBounds(subview: hostingController.view)
        hostingController.didMove(toParent: self)

        configureNavigationHeader()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncNavigationHeader(animated: false)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model.refreshIfNeeded()
        let isFirstAppearance = !didCompleteInitialAppearance
        didCompleteInitialAppearance = true
        if isFirstAppearance {
            lastScrollOffset = 0
        }
        syncNavigationHeader(animated: false)
    }

    public override func scrollToTop(animated: Bool) {
        model.scrollToTop()
    }

    public nonisolated func walletCore(event: WalletCoreData.Event) {
        MainActor.assumeIsolated {
            switch event {
            case .tokensChanged, .baseCurrencyChanged(to: _):
                model.reloadTokens()
            default:
                break
            }
        }
    }

    private func configureNavigationHeader() {
        navigationHeader.setTitle(lang("Market"), fixedColor: true)
        navigationItem.titleView = navigationHeader
        navigationBarBlurView = addCustomNavigationBarBackground(color: .air.groupedBackground)
        navigationBarBlurView?.alpha = 0

        largeTitleLabel.text = lang("Market")
        largeTitleLabel.applyTextStyle(.largeTitle, scaling: .dynamic)
        largeTitleLabel.textColor = .label
        largeTitleLabel.accessibilityTraits = .header
        largeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(largeTitleLabel)
        NSLayoutConstraint.activate([
            largeTitleLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            largeTitleLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -8),
        ])
        syncNavigationHeader(animated: false)
    }

    private func scrollOffsetDidChange(_ offset: CGFloat) {
        lastScrollOffset = offset
        guard didCompleteInitialAppearance else { return }
        syncNavigationHeader()
    }

    private func syncNavigationHeader(animated: Bool = true) {
        let showsLargeTitle: Bool
        let showsNavigationTitle: Bool

        if !self.showsLargeTitle {
            showsLargeTitle = false
            showsNavigationTitle = true
            navigationBarBlurView?.alpha = usesTopTabsChrome ? 1 : 0
        } else {
            let progress = calculateNavigationBarProgressiveBlurProgress(lastScrollOffset)
            navigationBarBlurView?.alpha = progress
            if isLargeTitleVisible == true {
                showsLargeTitle = progress <= 0.7
            } else {
                showsLargeTitle = progress <= 0.1
            }
            showsNavigationTitle = true
        }

        applyNavigationAccessibility(
            showsLargeTitle: showsLargeTitle,
            showsNavigationTitle: showsNavigationTitle
        )

        guard isLargeTitleVisible != showsLargeTitle
                || isNavigationTitleVisible != showsNavigationTitle else { return }
        isLargeTitleVisible = showsLargeTitle
        isNavigationTitleVisible = showsNavigationTitle

        let compactTitleAlpha: CGFloat = showsNavigationTitle ? (showsLargeTitle ? 0 : 1) : 0
        let changes = {
            self.largeTitleLabel.alpha = showsLargeTitle ? 1 : 0
            self.navigationHeader.visibilityAlpha = compactTitleAlpha
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    private func applyNavigationAccessibility(
        showsLargeTitle: Bool,
        showsNavigationTitle: Bool
    ) {
        largeTitleLabel.isAccessibilityElement = showsLargeTitle
        let showsCompactTitle = showsNavigationTitle && !showsLargeTitle
        navigationHeader.accessibilityElementsHidden = !showsCompactTitle
        if let titleLabel = navigationHeader.contentView as? UILabel {
            titleLabel.isAccessibilityElement = showsCompactTitle
            titleLabel.accessibilityTraits = .header
        }
    }

    private func showAllTokens(in section: MarketSection) {
        let viewController = MarketTokenListVC(title: section.title, tokens: section.tokens)
        navigationController?.pushViewController(viewController, animated: true)
    }
}
