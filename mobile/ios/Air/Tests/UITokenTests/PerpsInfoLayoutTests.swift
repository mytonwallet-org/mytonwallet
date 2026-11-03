import GRDB
import Testing
import UIKit
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import UIToken

@Suite(.serialized) @MainActor
struct PerpsInfoLayoutTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func actionNoticeReservesScrollSpaceAndClearsWithoutMovingButtons() async throws {
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 700))
        window.rootViewController = controller
        let button = WButton(style: .primary)
        let layout = AssetDetailsView(sections: [], buttons: [button])
        controller.view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: controller.view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
        ])
        window.isHidden = false
        defer { window.isHidden = true }
        try await settle(window)
        let initialInset = layout.scrollView.contentInset.bottom
        let initialButtonFrame = button.convert(button.bounds, to: layout)
        layout.setActionNotice(lang("PerpsUnsupportedAccount"))
        try await settle(window)
        #expect(layout.scrollView.contentInset.bottom > initialInset + 44)
        #expect(button.convert(button.bounds, to: layout) == initialButtonFrame)
        layout.setActionNotice(nil)
        try await settle(window)
        #expect(abs(layout.scrollView.contentInset.bottom - initialInset) < 1)
        #expect(button.convert(button.bounds, to: layout) == initialButtonFrame)
    }

    @Test(arguments: [false, true])
    func expansionKeepsContentMeasuredAndScrollPositionStable(collapsesMetrics: Bool) async throws {
        let (window, layout, info) = try makeLayout(collapsesMetrics: collapsesMetrics)
        defer { window.isHidden = true; SettingsStore.liveValue.clean() }
        try await settle(window)
        let collapsedHeight = info.bounds.height
        #expect(abs(collapsedHeight - (collapsesMetrics ? 64 : 365)) < 2)
        if collapsesMetrics {
            let header = try #require(info.subviews.compactMap { $0 as? UIButton }.first)
            #expect(header.bounds.height == collapsedHeight)
            #expect(header.accessibilityValue == lang("Collapsed"))
            #expect(info.hitTest(CGPoint(x: 180, y: 32), with: nil) === header)
        }
        let host = try #require(info.subviews.first)
        let measuredHeight = host.bounds.height
        #expect(measuredHeight > collapsedHeight + 50)
        layout.scrollView.contentOffset.y = 180
        var heights: [CGFloat] = []
        var offsets: [CGFloat] = []
        info.onHeightChange = { [weak layout, weak info] in
            layout?.layoutKeepingScrollPosition()
            if let info { heights.append(info.bounds.height) }
            if let layout { offsets.append(layout.scrollView.contentOffset.y) }
        }

        info.toggleExpanded()
        try await settle(window, milliseconds: 650)
        #expect(abs(info.bounds.height - measuredHeight) < 1)
        #expect(abs(host.bounds.height - measuredHeight) < 1)
        #expect(heights.allSatisfy { $0 >= collapsedHeight - 1 && $0 <= measuredHeight + 1 })
        #expect(offsets.allSatisfy { abs($0 - 180) < 1 })

        var refreshed = fixture()
        refreshed.fundingRate = "0.0015% · 8h"
        refreshed.price = 66_000
        info.configure(data: refreshed)
        try await settle(window)
        #expect(abs(info.bounds.height - measuredHeight) < 1)
        info.toggleExpanded()
        try await settle(window, milliseconds: 650)
        #expect(abs(info.bounds.height - collapsedHeight) < 1)
        #expect(abs(host.bounds.height - measuredHeight) < 1)
        #expect(abs(layout.scrollView.contentOffset.y - 180) < 1)
    }

    @Test
    func descriptionMeasurementAdaptsToContentAndWidth() async throws {
        let (window, layout, info) = try makeLayout(collapsesMetrics: false)
        defer { window.isHidden = true; SettingsStore.liveValue.clean() }
        try await settle(window)
        info.toggleExpanded()
        try await settle(window, milliseconds: 650)
        let expandedHeight = info.bounds.height
        var data = fixture()
        data.description = "Short description."
        info.configure(data: data)
        try await settle(window)
        #expect(info.bounds.height < expandedHeight - 100)
        let shortHeight = info.bounds.height
        info.toggleExpanded()
        try await settle(window, milliseconds: 650)
        #expect(abs(info.bounds.height - shortHeight) < 1)
        data.description = fixture().description
        info.configure(data: data)
        try await settle(window)
        info.toggleExpanded()
        try await settle(window, milliseconds: 650)
        window.frame.size.width = 320
        layout.setNeedsLayout()
        try await settle(window)
        #expect(info.bounds.height > expandedHeight)
    }

    @Test
    func disablingAnimationsImmediatelyResizesAndClampsScrollOnCollapse() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        let previous = AppStorageHelper.animations
        AppStorageHelper.animations = false
        defer {
            AppStorageHelper.animations = previous
            SettingsStore.liveValue.clean()
        }
        let (window, layout, info) = try makeLayout(collapsesMetrics: true, preparesSettings: false)
        defer { window.isHidden = true }
        try await settle(window)
        info.toggleExpanded()
        #expect(info.bounds.height > 400)
        layout.scrollView.contentOffset.y = layout.scrollView.contentSize.height + layout.scrollView.adjustedContentInset.bottom - layout.scrollView.bounds.height
        info.toggleExpanded()
        #expect(info.bounds.height == 64)
        #expect(abs(layout.scrollView.contentOffset.y - (layout.scrollView.contentSize.height + layout.scrollView.adjustedContentInset.bottom - layout.scrollView.bounds.height)) < 1)
    }

    @Test
    func expansionPreferenceIsRestoredAndSharedWithTokenInfo() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        AppStorageHelper.isTokenInfoExpanded = true
        let (window, _, info) = try makeLayout(collapsesMetrics: true, isExpanded: nil, preparesSettings: false)
        defer { window.isHidden = true }
        try await settle(window)
        #expect(info.bounds.height > 400)
        info.toggleExpanded()
        try await settle(window, milliseconds: 650)
        #expect(!AppStorageHelper.isTokenInfoExpanded)
        let (secondWindow, _, secondInfo) = try makeLayout(collapsesMetrics: true, isExpanded: nil, preparesSettings: false)
        defer { secondWindow.isHidden = true }
        try await settle(secondWindow)
        #expect(secondInfo.bounds.height == 64)
    }

    private func makeLayout(collapsesMetrics: Bool, isExpanded: Bool? = false, preparesSettings: Bool = true) throws -> (UIWindow, AssetDetailsView, PerpsMarketInfoView) {
        if preparesSettings {
            let db = try DatabaseQueue()
            try makeMigrator().migrate(db)
            SettingsStore.liveValue.use(db: db)
        }
        let controller = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 600).isActive = true
        let footer = UIView()
        footer.heightAnchor.constraint(equalToConstant: 400).isActive = true
        let info = PerpsMarketInfoView(data: fixture(), collapsesMetrics: collapsesMetrics, isExpanded: isExpanded)
        let layout = AssetDetailsView(sections: [spacer, info, footer], buttons: [])
        controller.view.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: controller.view.topAnchor),
            layout.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
            layout.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
        ])
        info.onHeightChange = { [weak layout] in layout?.layoutKeepingScrollPosition() }
        window.isHidden = false
        window.layoutIfNeeded()
        return (window, layout, info)
    }

    private func settle(_ window: UIWindow, milliseconds: Int = 200) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        window.layoutIfNeeded()
    }

    private func fixture() -> PerpsMarketDisplayData {
        .init(title: "Bitcoin Futures", token: .ETH, price: 64_845, percentChange24h: 3.23, history: [],
              description: "Bitcoin is the first cryptocurrency, created\u{2028}in 2009 by the pseudonymous Satoshi Nakamoto. It runs on its own network, without banks or intermediaries. Its supply is capped at 21 million coins — no one can issue more. Bitcoin is the largest crypto asset by market value and is more often held as a store of value than used for payments.",
              fundingRate: "0.0012% · 8h", maxLeverage: "40x", volume24h: "$1.9B", openInterest: "$2.21B",
              distribution: .init(longValue: 1_370, shortValue: 840, longLabel: "$1.37B Long", shortLabel: "$840M Short"))
    }
}
