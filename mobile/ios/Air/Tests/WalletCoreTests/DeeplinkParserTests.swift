import Foundation
import Testing
import WalletCore

@Suite("Deeplink Parser")
struct DeeplinkParserTests {
    @Test(arguments: [
        "mtw://nft-card",
        "mtw://nft-card/",
        "mtw://nft-card?utm_source=promotion",
        "https://my.tt/nft-card",
        "https://my.tt/nft-card/",
        "https://go.mytonwallet.org/nft-card",
        "http://go.mytonwallet.org/nft-card?utm_source=promotion",
        "mtw://mint",
        "mtw://mint/",
        "mtw://mint?utm_source=promotion",
        "https://my.tt/mint",
        "https://my.tt/mint/",
        "https://go.mytonwallet.org/mint",
        "http://go.mytonwallet.org/mint?utm_source=promotion",
    ])
    func parsesMintCardDeeplink(value: String) throws {
        let url = try #require(URL(string: value))
        let deeplink = try #require(Deeplink(url: url))
        guard case .mintCard = deeplink else {
            Issue.record("Expected mint card deeplink")
            return
        }
    }

    struct WalletConnectCase: Sendable {
        let url: String
        let expectedRequestLink: String
    }

    static let walletConnectRequestLink = [
        "wc:94caa59c77dae0dd234b5818fb7292540d017b27d41f7f387ee75b22b9738c94@2",
        "?relay-protocol=irn",
        "&symKey=ce3a2c7724c03cf1769ba8b1bdedad5414cc7b920aa3fb72112b997d1916266f",
    ].joined()

    static let encodedWalletConnectRequestLink = walletConnectRequestLink
        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!

    static let walletConnectCases: [WalletConnectCase] = [
        .init(
            url: walletConnectRequestLink,
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "mw://wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "mtw://wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "mywallet-wc://wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "https://connect.mywallet.io/wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "https://connect.mywallet.io/wc/wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "https://connect.mytonwallet.org/wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "https://connect.mytonwallet.org/wc/wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "gramwallet://wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "gramwallet-wc://wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "https://connect.gramwallet.io/wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "https://connect.gramwallet.io/wc/wc?uri=\(walletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
        .init(
            url: "mw://wc?uri=\(encodedWalletConnectRequestLink)",
            expectedRequestLink: walletConnectRequestLink
        ),
    ]

    @Test(arguments: walletConnectCases)
    func parsesWalletConnectDeeplink(testCase: WalletConnectCase) throws {
        let url = try #require(URL(string: testCase.url))
        let deeplink = try #require(Deeplink(url: url))

        guard case .walletConnect(let requestLink) = deeplink else {
            Issue.record("Expected WalletConnect deeplink")
            return
        }

        #expect(requestLink == testCase.expectedRequestLink)
    }

    @Test
    func rejectsWalletConnectWrappersWithoutWalletConnectUri() throws {
        let missingUriUrl = try #require(URL(string: "mw://wc"))
        #expect(Deeplink(url: missingUriUrl) == nil)

        let nonWalletConnectUriUrl = try #require(URL(string: "mw://wc?uri=ton://transfer"))
        #expect(Deeplink(url: nonWalletConnectUriUrl) == nil)
    }

    @Test(arguments: [
        "mywallet-wc://request?requestId=123&sessionTopic=session-topic",
        "https://connect.mywallet.io/wc?topic=session-topic&wc_ev=envelope%2Fpayload%3D",
        "https://connect.mywallet.io/wc?topic=session-topic&message=envelope",
    ])
    func parsesWalletConnectLinkModeSessionRequest(value: String) throws {
        let url = try #require(URL(string: value))
        let deeplink = try #require(Deeplink(url: url))

        guard case .walletConnect(let requestLink) = deeplink else {
            Issue.record("Expected WalletConnect deeplink")
            return
        }

        #expect(requestLink == value)
    }

    @Test
    func parsesSellOnCardDeeplink() throws {
        let url = try #require(URL(string: "mtw://sell-on-card"))
        let deeplink = try #require(Deeplink(url: url))

        guard case .sellOnCard = deeplink else {
            Issue.record("Expected sellOnCard deeplink")
            return
        }
    }
}
