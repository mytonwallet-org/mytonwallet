import Foundation
import Testing
import WalletContext

@Suite("URL Sanitization")
struct URLSanitizationTests {
    @Test
    func `sanitizedHttpUrl accepts http and https URLs`() {
        let httpsUrl = URL.sanitizedHttpUrl(from: " https://example.com/path?value=1 ")
        let httpUrl = URL.sanitizedHttpUrl(from: "http://localhost:4321")
        let uppercaseSchemeUrl = URL.sanitizedHttpUrl(from: "HTTPS://example.com")

        #expect(httpsUrl?.absoluteString == "https://example.com/path?value=1")
        #expect(httpUrl?.absoluteString == "http://localhost:4321")
        #expect(uppercaseSchemeUrl?.scheme?.lowercased() == "https")
    }

    @Test
    func `sanitizedHttpUrl rejects unsafe or malformed URLs`() {
        let invalidValues: [String?] = [
            nil,
            "",
            "   ",
            "javascript:alert(1)",
            "ftp://example.com",
            "mailto:support@example.com",
            "https:example.com",
            "https:///path-only",
        ]

        for value in invalidValues {
            #expect(URL.sanitizedHttpUrl(from: value) == nil)
        }
    }

    @Test
    func `sanitizedMailtoUrl builds mailto URLs from email addresses`() {
        let supportUrl = URL.sanitizedMailtoUrl(email: " support@example.com ")
        let plusAddressUrl = URL.sanitizedMailtoUrl(email: "support+ios@example.com")
        let queryLikeUrl = URL.sanitizedMailtoUrl(email: "support@example.com?subject=test")
        let emailLink = URL.sanitizedMailtoLink(email: " support@example.com ")

        #expect(supportUrl?.absoluteString == "mailto:support@example.com")
        #expect(plusAddressUrl?.absoluteString == "mailto:support+ios@example.com")
        #expect(queryLikeUrl?.scheme == "mailto")
        #expect(queryLikeUrl?.query == nil)
        #expect(queryLikeUrl?.absoluteString.contains("?") == false)
        #expect(emailLink?.email == "support@example.com")
        #expect(emailLink?.url == supportUrl)
    }

    @Test
    func `sanitizedMailtoUrl rejects empty whitespace or addressless values`() {
        let invalidValues: [String?] = [
            nil,
            "",
            "   ",
            "support example.com",
            "support.example.com",
        ]

        for value in invalidValues {
            #expect(URL.sanitizedMailtoUrl(email: value) == nil)
        }
    }
}
