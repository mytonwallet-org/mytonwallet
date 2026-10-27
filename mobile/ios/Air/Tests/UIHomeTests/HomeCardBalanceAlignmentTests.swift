import Dependencies
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletResources
@testable import UIHome

@MainActor
@Suite("Home card balance alignment", .serialized)
struct HomeCardBalanceAlignmentTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test(arguments: [HomeRootNavigationStyle.standard, .topTabsNavigationBar], [320.0, 402.0, 440.0, 1024.0])
    func balancesFollowTheSameAnimationPath(style: HomeRootNavigationStyle, width: Double) async throws {
        try await checkAlignment(style: style, width: width, amount: nil)
    }

    @Test(arguments: [HomeRootNavigationStyle.standard, .topTabsNavigationBar], [320.0, 402.0, 440.0, 1024.0])
    func fittedTextFollowsTheSameAnimationPath(style: HomeRootNavigationStyle, width: Double) async throws {
        for amount in [1234.56, 123456789012.34] {
            try await checkAlignment(style: style, width: width, amount: amount)
        }
    }

    @Test(arguments: [0.5, 1.0])
    func scrolledBalanceStaysAlignedThroughExpansionAndRecollapse(progress: Double) async throws {
        for amount in [nil, 1234.56, 123456789012.34] as [Double?] {
            try await checkAlignment(style: .standard, width: 402, amount: amount, scrollProgress: progress)
        }
    }

    @Test
    func scrollingDuringCollapseKeepsBothFacesAligned() async throws {
        for amount in [nil, 123456789012.34] as [Double?] {
            try await checkAlignment(style: .standard, width: 402, amount: amount,
                                     scrollProgress: 1, scrollDuringCollapse: true)
        }
    }

    private func checkAlignment(style: HomeRootNavigationStyle, width: Double, amount: Double?,
                                scrollProgress: Double = 0, scrollDuringCollapse: Bool = false) async throws {
        try await withDependencies { $0.context = .live } operation: {
            let wasHidden = AppStorageHelper.isSensitiveDataHidden
            AppStorageHelper.isSensitiveDataHidden = false
            defer { AppStorageHelper.isSensitiveDataHidden = wasHidden }
            let account = MAccount(id: "90105-mainnet", title: "Alignment fixture", type: .mnemonic,
                                   byChain: [.ton: AccountChain(address: "UQDQ7EXuEywyezyEWzfNkHZTSbe8qbPKETFYHr_KTZnnJ-xL")])
            let model = HomeHeaderViewModel(accountSource: .constant(account), rootNavigationStyle: style)
            let metrics = HomeCardLayoutMetrics.forContainerWidth(width)
            let card = HomeCard(frame: .zero)
            card.configure(headerViewModel: model, accountContext: AccountContext(source: .constant(account)),
                           layout: metrics, minimumHomeCardFontScale: width == 320 ? 0.8 : 1)

            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 874))
            let host = UIViewController()
            window.rootViewController = host
            host.view.addSubview(card)
            card.frame = CGRect(x: metrics.leadingInset, y: 160, width: metrics.itemWidth, height: metrics.itemHeight)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()
            defer { card.prepareForReuse(); window.isHidden = true }

            let expanded = try #require(card.cardContentMaskingContainer.subviews.first as? HomeCardContentView)
            let collapsed = try #require(card.contentView.subviews.first as? HomeCardContentView)
            let expandedBalance = try #require((expanded.subviews.first as? MtwCardContentView)?.balance)
            let collapsedBalance = try #require((collapsed.subviews.first as? MtwCardContentView)?.balance)
            if let amount {
                // Isolate live stores while exercising the actual card animation
                // and the numeric SwiftUI hosts with a deterministic balance.
                for face in [expanded, collapsed] {
                    face.prepareForReuse()
                    let content = try #require(face.subviews.first as? MtwCardContentView)
                    content.configure(MtwCardContentData(account: account,
                        addressLine: account.addressLine(orderedChains: account.orderedChains),
                        balance: .fromDouble(amount, .USD), previousBalance: nil, balanceChange: nil, nft: nil),
                        cardWidth: metrics.itemWidth, minimumFontScale: width == 320 ? 0.8 : 1,
                        usesTopTabs: style.usesNavigationBarTopTabs, animatesBalance: false)
                }
                // Refresh the inactive transform after replacing the fixture data.
                model.state = .collapsed
                try await Task.sleep(for: .milliseconds(600))
                model.state = .expanded
            }
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let expandedLabel = amount == nil ? expandedBalance : try #require(descendants(of: expandedBalance).first { $0 is HostingView })
            let collapsedLabel = amount == nil ? collapsedBalance : try #require(descendants(of: collapsedBalance).first { $0 is HostingView })
            if let amount, amount > 1_000_000 {
                #expect(expandedLabel.transform.a < 1)
                #expect(collapsedLabel.transform.a < 1)
                #expect(expandedLabel.frame.width <= expandedBalance.bounds.width + 0.5)
                #expect(collapsedLabel.frame.width <= collapsedBalance.bounds.width + 0.5)
            }

            for state in [HomeHeaderState.collapsed, .expanded, .collapsed, .expanded] {
                if state == .expanded, scrollProgress > 0 {
                    model.scrollOffsetChanged(to: model.collapsedHeight * scrollProgress)
                    try await Task.sleep(for: .milliseconds(100))
                    window.layoutIfNeeded()
                }
                model.state = state
                if state == .expanded { model.scrollOffsetChanged(to: 0) }
                var sampledAnimation = false
                for sample in 0..<15 {
                    if state == .collapsed, scrollDuringCollapse, sample < 5 {
                        model.scrollOffsetChanged(to: model.collapsedHeight * CGFloat(sample) / 4)
                    }
                    try await Task.sleep(for: .milliseconds(40))
                    window.layoutIfNeeded()
                    let expandedLayer = try #require(expanded.layer.presentation())
                    let collapsedLayer = try #require(collapsed.layer.presentation())
                    sampledAnimation = sampledAnimation || abs(expandedLayer.transform.m11 - expanded.layer.transform.m11) > 0.001
                        || abs(collapsedLayer.transform.m11 - collapsed.layer.transform.m11) > 0.001
                    let expandedFrame = try presentedFrame(expandedLabel, in: window, animatedAncestor: expanded)
                    let collapsedFrame = try presentedFrame(collapsedLabel, in: window, animatedAncestor: collapsed)
                    #expect(abs(expandedFrame.midX - collapsedFrame.midX) < 0.5,
                            "Horizontal alignment during \(state), \(style), width \(width)")
                    #expect(abs(expandedFrame.midY - collapsedFrame.midY) < 0.5,
                            "Vertical alignment during \(state), \(style), width \(width)")
                    #expect(abs(expandedFrame.height - collapsedFrame.height) < 0.5,
                            "Balance scale during \(state), \(style), width \(width)")
                }
                #expect(sampledAnimation, "Must sample an in-flight transform, not only its endpoint")
            }
        }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func presentedFrame(_ view: UIView, in window: UIWindow, animatedAncestor: UIView) throws -> CGRect {
        let layer = try #require(view.layer.presentation())
        let ancestor = try #require(animatedAncestor.layer.presentation())
        let windowLayer = try #require(window.layer.presentation())
        return ancestor.convert(layer.convert(layer.bounds, to: ancestor), to: windowLayer)
    }
}
