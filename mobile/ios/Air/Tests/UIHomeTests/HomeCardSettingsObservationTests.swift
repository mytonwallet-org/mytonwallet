import CoreText
import Foundation
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
        for name in ["SFCompactRoundedBold", "SFCompactDisplayMedium"] {
            if let url = WalletResourcesBundle.bundle.url(forResource: name, withExtension: "otf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
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
