import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

public final class MarketVC: WViewController, WalletCoreData.EventsObserver, Sendable {
    private let usesTopTabsChrome: Bool
    private let model = MarketScreenModel()
    private let navigationHeader = NavigationHeader2()
    private let largeTitleLabel = UILabel()
    private var navigationBarBlurView: UIView?
    private var lastScrollOffset: CGFloat = 0
    private var isLargeTitleVisible: Bool?

    public init(usesTopTabsChrome: Bool = false) {
        self.usesTopTabsChrome = usesTopTabsChrome
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        WalletCoreData.add(eventObserver: self)
        view.backgroundColor = .air.groupedBackground

        let screen = MarketScreen(
            model: model,
            showsInlineTitle: usesTopTabsChrome,
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
        let hostingController = UIHostingController(rootView: screen)
        hostingController.view.backgroundColor = .clear
        hostingController.view.insetsLayoutMarginsFromSafeArea = false
        addChild(hostingController)
        view.addStretchedToBounds(subview: hostingController.view)
        hostingController.didMove(toParent: self)

        configureNavigationHeader()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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

        guard !usesTopTabsChrome else {
            syncNavigationHeader(animated: false)
            return
        }

        largeTitleLabel.text = lang("Market")
        largeTitleLabel.applyTextStyle(.largeTitle, scaling: .dynamic)
        largeTitleLabel.textColor = .label
        largeTitleLabel.accessibilityTraits = .header
        largeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(largeTitleLabel)
        NSLayoutConstraint.activate([
            largeTitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            largeTitleLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: -8),
        ])
        syncNavigationHeader(animated: false)
    }

    private func scrollOffsetDidChange(_ offset: CGFloat) {
        lastScrollOffset = offset
        syncNavigationHeader()
    }

    private func syncNavigationHeader(animated: Bool = true) {
        let progress = calculateNavigationBarProgressiveBlurProgress(lastScrollOffset)
        navigationBarBlurView?.alpha = progress

        let showsLargeTitle: Bool
        if isLargeTitleVisible == true {
            showsLargeTitle = progress <= 0.7
        } else {
            showsLargeTitle = progress <= 0.1
        }
        guard isLargeTitleVisible != showsLargeTitle else { return }
        isLargeTitleVisible = showsLargeTitle

        largeTitleLabel.isAccessibilityElement = !usesTopTabsChrome && showsLargeTitle
        navigationHeader.accessibilityElementsHidden = showsLargeTitle
        if let titleLabel = navigationHeader.contentView as? UILabel {
            titleLabel.isAccessibilityElement = !showsLargeTitle
            titleLabel.accessibilityTraits = .header
        }

        let changes = {
            self.largeTitleLabel.alpha = showsLargeTitle ? 1 : 0
            self.navigationHeader.visibilityAlpha = showsLargeTitle ? 0 : 1
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            UIView.performWithoutAnimation(changes)
        }
    }

    private func showAllTokens(in section: MarketSection) {
        let viewController = MarketTokenListVC(title: lang(section.title), tokens: section.tokens)
        navigationController?.pushViewController(viewController, animated: true)
    }
}
