import Foundation
import Testing
import WalletContext

@Suite("URL display host")
struct URLDisplayHostTests {
    @Test(arguments: [
        "https://", // Known Foundation reproducer: https://developer.apple.com/forums/thread/722451
        "https:///path-only",
        "about:blank",
        "data:text/html,<title>Hostless</title>",
        "javascript:void(0)",
        "mailto:support@example.com",
        "/relative/path",
    ])
    func hostlessURLsHaveNoDisplayHost(_ value: String) throws {
        let url = try #require(URL(string: value))
        #expect(url.displayHost == nil)
    }

    @Test(arguments: [
        ("https://example.com/path?query=value#fragment", "example.com"),
        ("http://localhost:4321/path", "localhost"),
        ("https://user:password@example.com:8443/path", "example.com"),
        ("https://%65xample.com/path", "example.com"),
        ("https://b%C3%BCcher.example/path", "bücher.example"),
        ("https://xn--bcher-kva.example/path", "bücher.example"),
        ("http://127.0.0.1:8080/", "127.0.0.1"),
        ("http://[::1]:8080/", "[::1]"),
    ])
    func extractsDecodedHostWithoutOtherURLComponents(_ value: String, _ expected: String) throws {
        let url = try #require(URL(string: value))
        #expect(url.displayHost == expected)
    }

    @Test
    func resolvesRelativeURLAgainstItsBase() throws {
        let base = try #require(URL(string: "https://example.com/base/"))
        let url = try #require(URL(string: "../page", relativeTo: base))
        #expect(url.displayHost == "example.com")
    }
}
