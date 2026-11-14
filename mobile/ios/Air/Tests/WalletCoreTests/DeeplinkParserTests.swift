import Foundation
import Testing
import WalletCore

@Suite("Deeplink Parser")
struct DeeplinkParserTests {
    @Test(arguments: ["mtw://agent", "https://my.tt/agent"])
    func parsesAgentPushLinks(base: String) throws {
        let newsUrl = try #require(URL(string: base + "?news=307"))
        let news = try #require(Deeplink(url: newsUrl))
        guard case .agentNews(let eventId) = news else { Issue.record("Expected news chat"); return }
        #expect(eventId == 307)
        let digestId = "ru:2026-11-08T18:00:00.000Z"
        var components = try #require(URLComponents(string: base))
        components.percentEncodedQuery = "digest=ru%3A2026-11-08T18%3A00%3A00.000Z"
        let digestUrl = try #require(components.url)
        let digest = try #require(Deeplink(url: digestUrl))
        guard case .agentDigest(let id) = digest else { Issue.record("Expected digest feed"); return }
        #expect(id == digestId)
        for query in ["", "?news=", "?news=abc", "?news=-1", "?news=0", "?digest=", "?digest=%20", "?digest=%0A"] {
            let fallbackUrl = try #require(URL(string: base + query))
            let fallback = try #require(Deeplink(url: fallbackUrl))
            guard case .agent = fallback else { Issue.record("Expected plain Agent for invalid value"); continue }
        }
    }

    /// The share link of a news item carries its ID and language in a fixed order and opens its discussion. The tests
    /// run as the main flavor: `IS_GRAM_WALLET` follows the bundle identifier.
    @Test(arguments: ["ru", "en"])
    func agentNewsShareLinkOpensTheNewsDiscussion(lang: String) throws {
        let url = ExplorerHelper.makeAgentNewsShareUrl(eventId: 307, lang: lang)
        #expect(url.absoluteString == "https://my.tt/agent?news=307&lang=\(lang)&utm_source=pulse_share")
        let deeplink = try #require(Deeplink(url: url))
        guard case .agentNews(let eventId) = deeplink else { Issue.record("Expected news chat"); return }
        #expect(eventId == 307)
    }

    @Test
    func parsesMultisend() throws {
        let url = try #require(URL(string: "mtw://multisend"))
        let deeplink = try #require(Deeplink(url: url))
        guard case .multisend = deeplink else {
            Issue.record("Expected multisend deeplink")
            return
        }
    }

    @Test(arguments: ["", "receiver.ton"])
    func parsesSendFormWithOptionalRecipient(address: String) throws {
        let url = try #require(URL(string: "mtw://send/ton:\(address)?token=gram&amount=3000000000&text=Hello"))
        let deeplink = try #require(Deeplink(url: url))

        guard case .send(let chain, let recipient, let amount, let comment, let binaryPayload, let tokenSlug, let stateInit) = deeplink else {
            Issue.record("Expected send deeplink")
            return
        }

        #expect(chain == .ton)
        #expect(recipient == address)
        #expect(amount == 3_000_000_000)
        #expect(comment == "Hello")
        #expect(tokenSlug == "gram")
        #expect(binaryPayload == nil)
        #expect(stateInit == nil)
    }

    @Test(arguments: [
        "mtw://send/ton:invalid-recipient?token=gram&amount=3000000000",
        "mtw://send/unsupported:?token=gram&amount=3000000000",
        "mtw://send/ton?token=gram&amount=3000000000",
    ])
    func rejectsInvalidSendForm(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(Deeplink(url: url) == nil)
    }

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

    #if DEBUG
    @Test
    func parsesE2EUnlockDeeplink() throws {
        let url = try #require(URL(string: "mtw://e2e-unlock?passcode=1111"))
        let deeplink = try #require(Deeplink(url: url))

        guard case .e2eUnlock(let passcode, let next) = deeplink else {
            Issue.record("Expected e2eUnlock deeplink")
            return
        }

        #expect(passcode == "1111")
        #expect(next == nil)
    }

    @Test
    func parsesE2EUnlockDeeplinkWithNext() throws {
        let url = try #require(URL(string: "mtw://e2e-unlock?passcode=1111&next=mtw%3A%2F%2Fswap%3Fin%3Dtoncoin%26amountIn%3D1"))
        let deeplink = try #require(Deeplink(url: url))

        guard case .e2eUnlock(let passcode, let next) = deeplink else {
            Issue.record("Expected e2eUnlock deeplink")
            return
        }

        #expect(passcode == "1111")
        #expect(next?.absoluteString == "mtw://swap?in=toncoin&amountIn=1")
    }
    #endif

    @Test(arguments: [
        "mtw://e2e-unlock",
        "mtw://e2e-unlock?passcode=",
        "https://my.tt/e2e-unlock?passcode=1111",
    ])
    func rejectsInvalidE2EUnlockDeeplink(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(Deeplink(url: url) == nil)
    }
}
