import Dependencies
import Foundation
import IssueReportingTestSupport
import Testing
import UIComponents
import UIKit
import WalletContext
import WalletCore
import WalletResources
@testable import UIHome

@MainActor
@Suite("Home card settings observation", .serialized)
struct HomeCardSettingsObservationTests {
    init() {
        _ = WalletResourcesBundle.bundle.load()
    }

    @Test
    func contentClipPreservesCoordinatesAcrossCollapseAndExpansion() async throws {
        try await withDependencies { $0.context = .live } operation: {
            let model = HomeHeaderViewModel(accountSource: .accountId("preview"))
            let context = AccountContext(source: .accountId("preview"))
            let layout = HomeCardLayoutMetrics.forContainerWidth(393)
            let card = HomeCard(frame: CGRect(x: 0, y: 0, width: layout.itemWidth, height: layout.itemHeight))
            card.configure(headerViewModel: model, accountContext: context, layout: layout)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            let root = UIViewController()
            window.rootViewController = root
            root.view.addSubview(card)
            card.frame = CGRect(x: 0, y: 0, width: layout.itemWidth, height: layout.itemHeight)
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            card.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            let clip = try #require(card.cardContentMaskingContainer)
            let content = try #require(clip.subviews.first)
            for state in [HomeHeaderState.collapsed, .expanded] {
                model.state = state
                try await Task.sleep(for: .milliseconds(50))
                card.layoutIfNeeded()
                #expect(clip.mask == nil)
                #expect(clip.clipsToBounds)
                #expect(abs(content.bounds.width - layout.itemWidth) < 0.01)
                let center = clip.convert(content.center, to: clip.superview)
                #expect(abs(center.x - layout.itemWidth / 2) < 0.01)
                #expect(abs(center.y - layout.itemHeight / 2) < 0.01)
                if state == .expanded {
                    #expect(abs(clip.bounds.width - layout.itemWidth) < 0.01)
                    #expect(abs(clip.layer.cornerRadius - 26) < 0.01)
                } else {
                    #expect(clip.bounds.width < 50)
                    #expect(clip.layer.animation(forKey: "cornerRadius") != nil)
                }
            }
        }
    }

    @Test
    func backgroundDefaultsNotificationsDoNotWaitForRendering() {
        let model = HomeHeaderViewModel(accountSource: .current)
        let expanded = HomeCardContentView(mode: .expanded)
        let collapsed = HomeCardContentView(mode: .collapsed)
        let posted = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            posted.signal()
        }

        // Keep the main actor occupied: a synchronous main-queue observer would
        // block the posting queue, which may be holding ConfigStore's barrier.
        let result = posted.wait(timeout: .now() + 1)
        withExtendedLifetime((model, expanded, collapsed)) {
            #expect(result == .success)
        }
    }

    @Test
    func topLineChangesReachTheHeaderAfterNotificationDelivery() async throws {
        let key = WalletCardSettings.topLineUserDefaultsKey
        let original = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(original, forKey: key) }
        let model = HomeHeaderViewModel(accountSource: .current)
        let next: WalletCardTopLine = model.walletCardTopLine == .walletName ? .topAddress : .walletName

        await Task.detached {
            UserDefaults.standard.set(next.rawValue, forKey: key)
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        }.value

        for _ in 0..<50 where model.walletCardTopLine != next {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.walletCardTopLine == next)
    }
}
