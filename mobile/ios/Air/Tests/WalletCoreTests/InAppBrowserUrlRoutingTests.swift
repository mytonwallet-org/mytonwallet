import Foundation
import Testing
import WalletContext
import WalletCore

@Suite("In-App Browser URL Routing")
struct InAppBrowserUrlRoutingTests {
    @Test(arguments: [
        ("https://example.com/page", "https://example.com/page", false, true),
        ("https://example.com/page#one", "https://example.com/page#two", false, true),
        ("https://example.com/page#one", "https://example.com/page", false, true),
        ("https://example.com/page?item=1", "https://example.com/page?item=2", false, false),
        ("https://example.com/one", "https://example.com/two", false, false),
        ("https://example.com/one", "https://other.com/one", false, false),
        ("https://app.ston.fi/pools?asset=ton#one", "https://app.ston.fi/swap?asset=usdt#two", true, true),
        ("https://app.ston.fi/pools", "https://other.ston.fi/swap", true, false),
        ("https://app.ston.fi/pools", "https://app.ston.fi.evil.com/swap", true, false),
        ("https://app.ston.fi/pools", "http://app.ston.fi/swap", true, false),
        ("https://app.ston.fi/pools", "https://app.ston.fi:8443/swap", true, false),
        ("about:blank", "https://app.ston.fi/swap", true, false),
        ("https://tonscan.org/tx/one?view=raw", "https://tonscan.org/tx/one?view=details", true, false),
    ])
    func `app links reuse only matching tabs`(current: String, requested: String, isKnownDapp: Bool, matches: Bool) throws {
        let currentUrl = try #require(URL(string: current))
        let requestedUrl = try #require(URL(string: requested))

        #expect(inAppBrowserTabMatchesUrl(currentUrl, requestedUrl: requestedUrl, isKnownDapp: isKnownDapp) == matches)
    }

    @Test(arguments: ApiChain.allCases)
    func `configured explorers keep different pages in separate tabs`(chain: ApiChain) throws {
        for explorer in getAvailableExplorers(chain: chain) {
            for base in explorer.baseUrl.values {
                let baseUrl = try #require(URL(string: base.url))
                let first = baseUrl.appendingPathComponent("first")
                let second = baseUrl.appendingPathComponent("second")
                let fragment = try #require(URL(string: first.absoluteString + "#details"))

                #expect(ExplorerHelper.isExplorerUrl(first))
                #expect(!inAppBrowserTabMatchesUrl(first, requestedUrl: second, isKnownDapp: true))
                #expect(inAppBrowserTabMatchesUrl(first, requestedUrl: fragment, isKnownDapp: true))
            }
        }
    }

    @Test(arguments: [
        ("https://TONSCAN.ORG/tx/one", true),
        ("https://tonscan.org.evil.com/tx/one", false),
        ("https://app.ston.fi/pools", false),
    ])
    func `explorer classification matches exact hosts ignoring case`(url: String, isExplorer: Bool) throws {
        #expect(ExplorerHelper.isExplorerUrl(try #require(URL(string: url))) == isExplorer)
    }

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
    func `subframes may load about: documents`() throws {
        let blankURL = try #require(URL(string: "about:blank"))
        let srcdocURL = try #require(URL(string: "about:srcdoc"))

        #expect(resolveInAppBrowserNavigationUrlRouting(blankURL, isMainFrame: false, shouldOpenInNewPage: false) == .allow)
        #expect(resolveInAppBrowserNavigationUrlRouting(srcdocURL, isMainFrame: false, shouldOpenInNewPage: false) == .allow)
        #expect(resolveInAppBrowserNavigationUrlRouting(blankURL, isMainFrame: false, shouldOpenInNewPage: true) == .consume)

        let otherAboutURL = try #require(URL(string: "about:preferences"))
        #expect(resolveInAppBrowserNavigationUrlRouting(otherAboutURL, isMainFrame: false, shouldOpenInNewPage: false) == .consume)
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
