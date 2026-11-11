import GRDB
import Testing
import UIKit
import UIComponents
import WalletContext
@testable import WalletCore
import WalletResources
@testable import UIToken

/// The futures pages host the token Info card: a market shows its metrics under the description,
/// a position collapses them under the header (`collapsesMetrics`).
@Suite(.serialized, .settingsStoreIsolation) @MainActor
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
        let (window, layout, info, model) = try makeLayout(collapsesMetrics: collapsesMetrics)
        defer { window.isHidden = true; SettingsStore.liveValue.clean() }
        try await settle(window)
        let collapsedHeight = info.bounds.height
        // A market shows the title, three description lines with their toggle, and four metric rows.
        #expect(abs(collapsedHeight - (collapsesMetrics ? TokenInfoModel.collapsedHeight : 42 + 3 * 22 + 22 + 4 * 48)) < 2)
        let host = try #require(info.subviews.first)
        if collapsesMetrics {
            #expect(host.bounds.height > collapsedHeight + 50)
        }
        layout.scrollView.contentOffset.y = 180
        var heights: [CGFloat] = []
        var offsets: [CGFloat] = []
        info.configure(model: model, onHeightChange: { [weak layout, weak info] in
            layout?.layoutKeepingScrollPosition()
            if let info { heights.append(info.bounds.height) }
            if let layout { offsets.append(layout.scrollView.contentOffset.y) }
        })

        model.requestToggle()
        try await settle(window, milliseconds: 650)
        let expandedHeight = info.bounds.height
        #expect(expandedHeight > collapsedHeight + 50)
        #expect(abs(expandedHeight - model.measuredExpandedHeight) < 1)
        #expect(abs(host.bounds.height - expandedHeight) < 1)
        #expect(!heights.isEmpty)
        #expect(heights.allSatisfy { $0 >= collapsedHeight - 1 && $0 <= expandedHeight + 1 })
        #expect(offsets.allSatisfy { abs($0 - 180) < 1 })

        var refreshed = fixture()
        refreshed.fundingRate = "0.0015% · 8h"
        refreshed.price = 66_000
        model.configure(state: .summary(refreshed.infoSummary))
        info.modelStateDidChange()
        try await settle(window)
        #expect(abs(info.bounds.height - expandedHeight) < 1)
        model.requestToggle()
        try await settle(window, milliseconds: 650)
        #expect(abs(info.bounds.height - collapsedHeight) < 1)
        // A position keeps its content measured at full size and clips it; a market remeasures the shorter description.
        #expect(abs(host.bounds.height - (collapsesMetrics ? expandedHeight : collapsedHeight)) < 1)
        #expect(abs(layout.scrollView.contentOffset.y - 180) < 1)
    }

    @Test
    func descriptionMeasurementAdaptsToContentAndWidth() async throws {
        let (window, layout, info, model) = try makeLayout(collapsesMetrics: false)
        defer { window.isHidden = true; SettingsStore.liveValue.clean() }
        try await settle(window)
        model.requestToggle()
        try await settle(window, milliseconds: 650)
        let expandedHeight = info.bounds.height
        var data = fixture()
        data.description = "Short description."
        model.configure(state: .summary(data.infoSummary))
        info.modelStateDidChange()
        try await settle(window, milliseconds: 650)
        #expect(info.bounds.height < expandedHeight - 100)
        let shortHeight = info.bounds.height
        model.requestToggle()
        try await settle(window, milliseconds: 650)
        #expect(abs(info.bounds.height - shortHeight) < 1)
        data.description = fixture().description
        model.configure(state: .summary(data.infoSummary))
        info.modelStateDidChange()
        try await settle(window, milliseconds: 650)
        model.requestToggle()
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
        let (window, layout, info, model) = try makeLayout(collapsesMetrics: true, preparesSettings: false)
        defer { window.isHidden = true }
        try await settle(window)
        model.requestToggle()
        #expect(info.bounds.height > 400)
        layout.scrollView.contentOffset.y = layout.scrollView.contentSize.height + layout.scrollView.adjustedContentInset.bottom - layout.scrollView.bounds.height
        model.requestToggle()
        #expect(info.bounds.height == TokenInfoModel.collapsedHeight)
        #expect(abs(layout.scrollView.contentOffset.y - (layout.scrollView.contentSize.height + layout.scrollView.adjustedContentInset.bottom - layout.scrollView.bounds.height)) < 1)
    }

    @Test
    func expansionPreferenceIsRestoredAndSharedWithTokenInfo() async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        SettingsStore.liveValue.use(db: db)
        defer { SettingsStore.liveValue.clean() }
        AppStorageHelper.isTokenInfoExpanded = true
        let (window, _, info, model) = try makeLayout(collapsesMetrics: true, isExpanded: nil, preparesSettings: false)
        defer { window.isHidden = true }
        try await settle(window)
        #expect(info.bounds.height > 400)
        model.requestToggle()
        try await settle(window, milliseconds: 650)
        #expect(!AppStorageHelper.isTokenInfoExpanded)
        let (secondWindow, _, secondInfo, _) = try makeLayout(collapsesMetrics: true, isExpanded: nil, preparesSettings: false)
        defer { secondWindow.isHidden = true }
        try await settle(secondWindow)
        #expect(secondInfo.bounds.height == TokenInfoModel.collapsedHeight)
    }

    private func makeLayout(collapsesMetrics: Bool, isExpanded: Bool? = false, preparesSettings: Bool = true) throws
        -> (UIWindow, AssetDetailsView, TokenInfoCardView, TokenInfoModel) {
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
        let model = TokenInfoModel(state: .summary(fixture().infoSummary), isExpanded: isExpanded, hasBalance: collapsesMetrics)
        let info = TokenInfoCardView(sizesItself: true)
        let layout = AssetDetailsView(sections: [spacer, info, footer], buttons: [])
        layout.install(in: controller.view)
        info.configure(model: model, onHeightChange: { [weak layout] in layout?.layoutKeepingScrollPosition() })
        window.isHidden = false
        window.layoutIfNeeded()
        return (window, layout, info, model)
    }

    private func settle(_ window: UIWindow, milliseconds: Int = 200) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(milliseconds))
        window.layoutIfNeeded()
    }

    private func fixture() -> PerpsMarketDisplayData {
        .init(title: "Bitcoin Futures", token: .ETH, price: 64_845, percentChange24h: 3.23, history: [],
              description: "Bitcoin is the first cryptocurrency, created\u{2028}in 2009 by the pseudonymous Satoshi Nakamoto. It runs on its own network, without banks or intermediaries. Its supply is capped at 21 million coins — no one can issue more. Bitcoin is the largest crypto asset by market value and is more often held as a store of value than used for payments.",
              fundingRate: "0.0012% · 8h", maxLeverage: "40x", volume24h: "$1.9B", openInterest: "$2.21B")
    }
}
