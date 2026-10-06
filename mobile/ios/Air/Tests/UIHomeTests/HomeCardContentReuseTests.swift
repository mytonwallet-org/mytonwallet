import Dependencies
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletResources
@testable import UIHome

@MainActor
@Suite("Home card content reuse", .serialized)
struct HomeCardContentReuseTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test(arguments: [HomeRootNavigationStyle.standard, .topTabsNavigationBar])
    func freshExpandedCardDoesNotExposeCollapsedIcons(style: HomeRootNavigationStyle) throws {
        try withDependencies { $0.context = .live } operation: {
            let account = makeAccount("90101-mainnet")
            let model = HomeHeaderViewModel(accountSource: .constant(account), rootNavigationStyle: style)
            let metrics = HomeCardLayoutMetrics.forContainerWidth(402)
            let card = HomeCard(frame: .zero)
            // Configure only the inactive face, isolating layout from live wallet stores.
            card.container.headerViewModel = model
            card.container.accountContext = AccountContext(source: .constant(account))
            let collapsed = try #require(card.contentView.subviews.first as? HomeCardContentView)
            collapsed.configure(headerViewModel: model, accountContext: try #require(card.container.accountContext))
            card.updateLayoutMetrics(metrics, minimumHomeCardFontScale: 0.999)
            let window = show(card, size: CGSize(width: metrics.itemWidth, height: metrics.itemHeight))
            defer { window.isHidden = true }

            let content = try #require(collapsed.subviews.first as? MtwCardContentView)
            let icons = descendants(of: content).compactMap { $0 as? UIImageView }.filter { $0.image != nil }
            #expect(!icons.isEmpty)
            #expect(content.balance.displayedBalance == nil)
            #expect(icons.allSatisfy { !isVisible($0) })
        }
    }

    @Test(arguments: [HomeRootNavigationStyle.standard, .topTabsNavigationBar])
    func reuseWhileExpandedHidesPreviousBalanceUntilConfigured(style: HomeRootNavigationStyle) throws {
        try withDependencies { $0.context = .live } operation: {
            let oldAccount = makeAccount("90102-mainnet")
            let incomingAccount = makeAccount("90103-mainnet")
            let collapsed = HomeCardContentView(mode: .collapsed)
            let content = try #require(collapsed.subviews.first as? MtwCardContentView)
            let usesTopTabs = style.usesNavigationBarTopTabs
            content.configure(data(oldAccount, balance: 12345.67), cardWidth: 378,
                              usesTopTabs: usesTopTabs, animatesBalance: false)
            let window = show(collapsed, size: CGSize(width: 378, height: 238))
            defer { window.isHidden = true }
            let label = try #require(descendants(of: content.balance).first { $0 is HostingView })
            let oldBalanceFrame = content.balance.frame
            #expect(isVisible(label))

            collapsed.prepareForReuse()
            let model = HomeHeaderViewModel(accountSource: .constant(incomingAccount), rootNavigationStyle: style)
            collapsed.configure(headerViewModel: model, accountContext: AccountContext(source: .constant(incomingAccount)))
            collapsed.bounds.size = CGSize(width: 300, height: 189)
            collapsed.setNeedsLayout()
            window.layoutIfNeeded()

            #expect(content.balance.displayedBalance == nil)
            #expect(!isVisible(label))
            #expect(!isVisible(content.change))

            // Once this face is needed, rendering new account data restores it at the new size.
            content.configure(data(incomingAccount, balance: 98.76), cardWidth: 300,
                              usesTopTabs: usesTopTabs, animatesBalance: false)
            window.layoutIfNeeded()
            #expect(isVisible(label))
            #expect(content.balance.displayedBalance == .fromDouble(98.76, .USD))
            #expect(content.balance.numericTransitionCount == 0)
            #expect(content.balance.frame != oldBalanceFrame)
            #expect(abs(content.balance.frame.midX - content.bounds.midX) < 0.5)
        }
    }

    private func makeAccount(_ id: String) -> MAccount {
        MAccount(id: id, title: "Layout fixture", type: .mnemonic,
                 byChain: [.ton: AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")])
    }

    private func data(_ account: MAccount, balance: Double) -> MtwCardContentData {
        MtwCardContentData(account: account,
                           addressLine: account.addressLine(orderedChains: account.orderedChains),
                           balance: .fromDouble(balance, .USD), previousBalance: .fromDouble(100, .USD),
                           balanceChange: 0.02, nft: nil)
    }

    private func show(_ view: UIView, size: CGSize) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = true
        view.frame = CGRect(origin: CGPoint(x: 12, y: 160), size: size)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        view.layoutIfNeeded()
        return window
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func isVisible(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let view = current {
            if view.isHidden || view.alpha == 0 { return false }
            current = view.superview
        }
        return true
    }
}
