import Foundation
import Testing
import UserNotifications
import WalletContext
@testable import WalletCore

@MainActor
@Suite("Deeplink Provenance Handler")
struct DeeplinkProvenanceHandlerTests {
    @Test
    func `blocks Offramp from in-app browser`() throws {
        let navigator = RecordingDeeplinkNavigator()
        let handler = DeeplinkHandler(deeplinkNavigator: navigator)
        let url = try #require(makeOfframpURL())

        #expect(handler.handle(url, source: .inAppBrowser) == false)
        #expect(navigator.handledDeeplinks.isEmpty)
    }

    @Test
    func `blocks Offramp from QR scan`() throws {
        let navigator = RecordingDeeplinkNavigator()
        let handler = DeeplinkHandler(deeplinkNavigator: navigator)
        let url = try #require(makeOfframpURL())

        #expect(handler.handle(url, source: .qrScan) == false)
        #expect(navigator.handledDeeplinks.isEmpty)
    }

    @Test
    func `keeps Offramp available from trusted sources`() throws {
        let navigator = RecordingDeeplinkNavigator()
        let handler = DeeplinkHandler(deeplinkNavigator: navigator)
        let url = try #require(makeOfframpURL())

        #expect(handler.handle(url, source: .generic))
        #expect(navigator.handledDeeplinks.count == 1)
        #expect(navigator.handledSources == [.generic])

        guard case .sell = navigator.handledDeeplinks.first else {
            Issue.record("Expected Offramp deeplink")
            return
        }
    }

    @Test
    func `captures only opened permitted self links`() throws {
        let navigator = RecordingDeeplinkNavigator()
        var captured: [InstallAttributionSnapshot] = []
        let handler = DeeplinkHandler(deeplinkNavigator: navigator, capture: { captured.append($0) })
        let url = try #require(URL(string: "https://my.tt/market?utm_source=Partner&utm_campaign=launch"))
        _ = Deeplink(url: url)
        #expect(captured.isEmpty)
        #expect(handler.handle(url))
        #expect(captured.first?.channel == "partner")
        #expect(captured.first?.utmCampaign == "launch")
        #expect(navigator.handledDeeplinks.count == 1)
        #expect(handler.handle(try #require(URL(string: "https://my.tt/get/android?utm_source=second"))))
        #expect(navigator.handledDeeplinks.count == 1)
        #expect(captured.count == 2)
        let denied = try #require(URL(string: "\(SELF_PROTOCOL_SCHEME)://offramp?transactionId=test&utm_source=bad"))
        #expect(handler.handle(denied, source: .inAppBrowser) == false)
        #expect(captured.count == 2)
        _ = handler.handle(url, source: .exploreSearchBar)
        #expect(captured.count == 2)
    }

    @Test
    func `split preserves raw nested business query and validates whole snapshot`() throws {
        let business = "uri=wc%3Atopic%402%3Frelay-protocol%3Dirn%26symKey%3Dabc&r=keep%2bbytes"
        let url = try #require(URL(string: "https://my.tt/wc?\(business)&utm_source=partner&utm_content=button"))
        let split = splitAttributionDeeplink(url)
        #expect(split.url.absoluteString == "https://my.tt/wc?\(business)")
        #expect(split.snapshot?.utmContent == "button")
        let external = try #require(URL(string: "https://other.example/get?utm_source=partner"))
        #expect(splitAttributionDeeplink(external).snapshot == nil)
        #expect(splitAttributionDeeplink(external).url == external)
        let invalid = try #require(URL(string: "https://my.tt/get?utm_source=\(String(repeating: "a", count: 31))"))
        #expect(splitAttributionDeeplink(invalid).snapshot == nil)
        let controls = try #require(URL(string: "https://my.tt/get?utm_source=partner&utm_campaign=%0Alaunch"))
        #expect(splitAttributionDeeplink(controls).snapshot?.utmCampaign == nil)
    }

    @Test
    func `pending survives cold launch upgrades once and clears only on SDK acceptance`() async throws {
        let name = "attribution-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let inferred = InstallAttributionSnapshot(channel: "", attributionKind: "referrer", referrerDomain: "news.example")
        let explicit = InstallAttributionSnapshot(channel: "partner", attributionKind: "utm", utmCampaign: "first")
        var sent: [InstallAttributionSnapshot] = []
        let first = InstallAttributionDelivery(defaults: defaults) { value in sent.append(value); return true }
        first.capture(inferred)
        #expect(sent.isEmpty)
        let restored = InstallAttributionDelivery(defaults: defaults) { value in sent.append(value); return false }
        #expect(restored.pending == inferred)
        restored.capture(explicit)
        restored.capture(InstallAttributionSnapshot(channel: "partner", attributionKind: "utm", utmCampaign: "second"))
        restored.bridgePrepared()
        for _ in 0..<10 { await Task.yield() }
        #expect(sent == [explicit])
        #expect(restored.pending == explicit)
        let accepted = InstallAttributionDelivery(defaults: defaults) { value in sent.append(value); return true }
        accepted.bridgePrepared()
        for _ in 0..<10 { await Task.yield() }
        #expect(accepted.pending == nil)
        #expect(sent == [explicit, explicit])
    }

    @Test
    func `old in flight acceptance does not erase a newer explicit snapshot`() async throws {
        let name = "attribution-race-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var sent: [InstallAttributionSnapshot] = []
        var finish: CheckedContinuation<Bool, Never>?
        let delivery = InstallAttributionDelivery(defaults: defaults) { value in
            sent.append(value)
            if sent.count == 1 {
                return await withCheckedContinuation { finish = $0 }
            }
            return true
        }
        let inferred = InstallAttributionSnapshot(channel: "", attributionKind: "referrer", referrerDomain: "news.example")
        let explicit = InstallAttributionSnapshot(channel: "partner", attributionKind: "utm", utmCampaign: "launch")
        delivery.capture(inferred)
        delivery.bridgePrepared()
        for _ in 0..<10 { await Task.yield() }
        let completion = try #require(finish)
        delivery.capture(explicit)
        completion.resume(returning: true)
        for _ in 0..<10 { await Task.yield() }
        #expect(sent == [inferred, explicit])
        #expect(delivery.pending == nil)
    }

    @Test
    func `bridge replacement retries without waiting for an old send to finish`() async throws {
        let name = "attribution-bridge-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var sends = 0
        var finish: CheckedContinuation<Bool, Never>?
        let delivery = InstallAttributionDelivery(defaults: defaults) { _ in
            sends += 1
            if sends == 1 { return await withCheckedContinuation { finish = $0 } }
            return true
        }
        delivery.capture(InstallAttributionSnapshot(channel: "partner", attributionKind: "utm"))
        delivery.bridgePrepared()
        for _ in 0..<10 { await Task.yield() }
        let completion = try #require(finish)
        delivery.bridgeStopped()
        delivery.bridgePrepared()
        for _ in 0..<10 { await Task.yield() }
        #expect(sends == 2)
        #expect(delivery.pending == nil)
        completion.resume(returning: false)
        for _ in 0..<10 { await Task.yield() }
        #expect(sends == 2)
        #expect(delivery.pending == nil)
    }

    @Test
    func `empty queries are safe and referrer controls are rejected`() throws {
        for query in ["", "?", "?&&", "?&&#"] {
            let split = splitAttributionDeeplink(try #require(URL(string: "https://my.tt/get" + query)))
            #expect(split.isGet)
            #expect(split.snapshot == nil)
        }
        for suffix in ["%0A", "%0D", "%E2%80%A8", "%E2%80%A9"] {
            let url = try #require(URL(string: "https://my.tt/get?attribution_referrer=news.example" + suffix))
            #expect(splitAttributionDeeplink(url).snapshot == nil)
        }
    }

    private func makeOfframpURL() -> URL? {
        URL(string: "\(SELF_PROTOCOL_SCHEME)://offramp?transactionId=test")
    }
}

@MainActor
private final class RecordingDeeplinkNavigator: DeeplinkNavigator {
    var handledDeeplinks: [Deeplink] = []
    var handledSources: [DeeplinkOpenSource] = []

    func handle(deeplink: Deeplink, source: DeeplinkOpenSource) {
        handledDeeplinks.append(deeplink)
        handledSources.append(source)
    }

    func handleNotification(_ notification: UNNotification) {
    }
}
