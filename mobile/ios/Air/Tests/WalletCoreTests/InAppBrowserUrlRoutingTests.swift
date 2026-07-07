import Foundation
import Testing
import WalletContext
import WalletCore

@Suite("In-App Browser URL Routing")
struct InAppBrowserUrlRoutingTests {
    @Test
    func `navigation consumes Offramp before delegate routing`() throws {
        let url = try #require(makeOfframpURL())

        #expect(resolveInAppBrowserNavigationUrlRouting(url, shouldOpenInNewPage: false) == .consume)
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

        #expect(resolveInAppBrowserNavigationUrlRouting(url, shouldOpenInNewPage: false) == .handleDeeplink(source: .inAppBrowser))
        #expect(resolveInAppBrowserWindowOpenUrlRouting(url) == .handleDeeplink(source: .inAppBrowser))
        #expect(resolveInAppBrowserWebKitPopupUrlRouting(url) == .handleDeeplink(source: .inAppBrowser))
    }

    @Test
    func `popup web URLs open in a new page`() throws {
        let url = try #require(URL(string: "https://example.com/path"))

        #expect(resolveInAppBrowserNavigationUrlRouting(url, shouldOpenInNewPage: true) == .openNewPage)
        #expect(resolveInAppBrowserWindowOpenUrlRouting(url) == .openNewPage)
        #expect(resolveInAppBrowserWebKitPopupUrlRouting(url) == .openNewPage)
        #expect(resolveInAppBrowserWebKitPopupUrlRouting(nil) == .openNewPage)
    }

    @Test
    func `dapp request origin uses live web view URL`() throws {
        let configURL = try #require(URL(string: "https://first.example/path"))
        let webViewURL = try #require(URL(string: "https://second.example/other?q=1"))

        #expect(resolveDappRequestOrigin(configURL: configURL, webViewURL: webViewURL) == "https://second.example")
        #expect(resolveDappRequestOrigin(configURL: configURL, webViewURL: nil) == "https://first.example")
    }

    private func makeOfframpURL() -> URL? {
        URL(string: "\(SELF_PROTOCOL_SCHEME)://offramp?transactionId=test")
    }
}
