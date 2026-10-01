import GRDB
import Testing
import UIKit
import UIComponents
@testable import UIToken
import WalletContext
@testable import WalletCore
import WalletResources

@MainActor
@Suite("Token Chart Loading", .serialized)
struct TokenChartLoadingTests {
    @Test
    func `switching from empty history hides the label while the next period loads`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure([])
        #expect(fixture.emptyLabel.isHidden == false)

        try fixture.selectPeriod(0)
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.spinner.isAnimating)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.spinner.isAnimating)
    }

    @Test
    func `switching periods with an already visible spinner stays pending`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure([])
        try fixture.selectPeriod(0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.spinner.alpha == 1)

        try fixture.selectPeriod(1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.emptyLabel.isHidden)

        fixture.record("loading-after-period-switch.png")
        fixture.configure([])
        fixture.record("empty-response.png")
        #expect(fixture.spinner.isHidden)
        #expect(fixture.spinner.isAnimating == false)
        #expect(fixture.emptyLabel.isHidden == false)
    }

    @Test
    func `reconfiguration distinguishes pending empty and populated history`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure([])
        fixture.configure(nil)
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.emptyLabel.isHidden)

        fixture.configure([[1, 1], [2, 2]])
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)

        fixture.configure(nil)
        try await Task.sleep(for: .milliseconds(400))
        fixture.configure([])
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden == false)
    }

    @MainActor
    private final class Fixture {
        let view: TokenExpandableChartView
        let window: UIWindow
        let spinner: WActivityIndicator
        let emptyLabel: UILabel
        let periods: WChartSegmentedControl

        init() async throws {
            _ = WalletResourcesBundle.bundle.load()
            let db = try DatabaseQueue()
            try makeMigrator().migrate(db)
            SettingsStore.liveValue.use(db: db)
            AppStorageHelper.isTokenChartExpanded = true
            view = TokenExpandableChartView(onHeightChange: {})
            spinner = try #require(view.subviews.compactMap { $0 as? WActivityIndicator }.first)
            emptyLabel = try #require(view.subviews.compactMap { $0 as? UILabel }.first)
            periods = try #require(view.subviews.compactMap { $0 as? WChartSegmentedControl }.first)
            spinner.stopAnimating(animated: false)
            spinner.presentationDelay = 0

            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let controller = UIViewController()
            window.rootViewController = controller
            window.isHidden = false
            controller.view.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 100),
                view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
                view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            ])
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }

        func configure(_ history: [[Double]]?) {
            var token = ApiToken.TONCOIN
            token.priceUsd = 1.5
            view.configure(token: token, historyData: history, onPeriodChange: { _ in }, onAnalyze: nil)
        }

        func selectPeriod(_ index: Int) throws {
            periods.selectedSegmentIndex = index
            // These package tests have no UIApplication to dispatch UIControl actions.
            let action = try #require(periods.actions(forTarget: view, forControlEvent: .valueChanged)?.first)
            view.perform(NSSelectorFromString(action), with: periods)
        }

        func record(_ name: String) {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
                view.layer.render(in: context.cgContext)
            }
            if let data = image.pngData() {
                Attachment.record(data, named: name)
            }
        }

        func close() {
            spinner.stopAnimating(animated: false)
            window.isHidden = true
            SettingsStore.liveValue.clean()
        }
    }
}
