import Foundation
import Testing
import WalletContext
import WalletCore

@Suite("In-App Browser URL Routing")
struct InAppBrowserUrlRoutingTests {
    @Test
    func `navigation consumes Offramp before delegate routing`() throws {
        let url = try #require(makeOfframpURL())

        #expect(resolveInAppBrowserNavigationUrlRouting(url, isMainFrame: true, shouldOpenInNewPage: false) == .consume)
    }

    @Test
    func `window open consumes Offramp before delegate routing`() throws {
        let url = try #require(makeOfframpURL())

        #expect(resolveInAppBrowserWindowOpenUrlRouting(url) == .consume)
    }

    @Test
    func `WebKit popup consumes Offramp before page creation`() throws {
        let url = try #require(makeOfframpURL())

        #expect(resolveInAppBrowserWebKitPopupUrlRouting(url) == .consume)
    }

    @Test
    func `self deeplinks use in-app browser provenance`() throws {
        let url = try #require(URL(string: "\(SELF_PROTOCOL_SCHEME)://transfer"))

        #expect(resolveInAppBrowserNavigationUrlRouting(url, isMainFrame: true, shouldOpenInNewPage: false) == .handleDeeplink(source: .inAppBrowser))
        #expect(resolveInAppBrowserWindowOpenUrlRouting(url) == .handleDeeplink(source: .inAppBrowser))
        #expect(resolveInAppBrowserWebKitPopupUrlRouting(url) == .handleDeeplink(source: .inAppBrowser))
    }

    @Test
    func `popup web URLs open in a new page`() throws {
        let url = try #require(URL(string: "https://example.com/path"))

        #expect(resolveInAppBrowserNavigationUrlRouting(url, isMainFrame: true, shouldOpenInNewPage: true) == .openNewPage)
        #expect(resolveInAppBrowserWindowOpenUrlRouting(url) == .openNewPage)
        #expect(resolveInAppBrowserWebKitPopupUrlRouting(url) == .openNewPage)
        #expect(resolveInAppBrowserWebKitPopupUrlRouting(nil) == .openNewPage)
    }

    @Test
    func `subframes can navigate themselves but cannot trigger native routing`() throws {
        let webURL = try #require(URL(string: "https://example.com/embedded"))
        let deeplinkURL = try #require(URL(string: "ton://transfer/UQAddress"))
        let systemURL = try #require(URL(string: "mailto:test@example.com"))

        #expect(resolveInAppBrowserNavigationUrlRouting(webURL, isMainFrame: false, shouldOpenInNewPage: false) == .allow)
        #expect(resolveInAppBrowserNavigationUrlRouting(webURL, isMainFrame: false, shouldOpenInNewPage: true) == .consume)
        #expect(resolveInAppBrowserNavigationUrlRouting(deeplinkURL, isMainFrame: false, shouldOpenInNewPage: false) == .consume)
        #expect(resolveInAppBrowserNavigationUrlRouting(systemURL, isMainFrame: false, shouldOpenInNewPage: false) == .consume)
    }

    @Test
    func `message origin accepts only HTTP and HTTPS`() {
        #expect(resolveInAppBrowserMessageOrigin(scheme: "HTTPS", host: "Example.COM", port: 0) == "https://example.com")
        #expect(resolveInAppBrowserMessageOrigin(scheme: "https", host: "example.com", port: 443) == "https://example.com")
        #expect(resolveInAppBrowserMessageOrigin(scheme: "http", host: "example.com", port: 80) == "http://example.com")
        #expect(resolveInAppBrowserMessageOrigin(scheme: "http", host: "localhost", port: 8080) == "http://localhost:8080")
        #expect(resolveInAppBrowserMessageOrigin(scheme: "file", host: "", port: 0) == nil)
        #expect(resolveInAppBrowserMessageOrigin(scheme: "capacitor", host: "mytonwallet.local", port: 0) == nil)
    }

    private func makeOfframpURL() -> URL? {
        URL(string: "\(SELF_PROTOCOL_SCHEME)://offramp?transactionId=test")
    }
}
