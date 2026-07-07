import Foundation
import Testing
import UserNotifications
import WalletContext
import WalletCore

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

        guard case .sell = navigator.handledDeeplinks.first else {
            Issue.record("Expected Offramp deeplink")
            return
        }
    }

    private func makeOfframpURL() -> URL? {
        URL(string: "\(SELF_PROTOCOL_SCHEME)://offramp?transactionId=test")
    }
}

@MainActor
private final class RecordingDeeplinkNavigator: DeeplinkNavigator {
    var handledDeeplinks: [Deeplink] = []

    func handle(deeplink: Deeplink) {
        handledDeeplinks.append(deeplink)
    }

    func handleNotification(_ notification: UNNotification) {
    }
}
