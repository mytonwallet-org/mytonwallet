import Foundation
import WalletCore
import WalletCoreTypes

public enum UniversalSearchWebIntent: Equatable, Sendable {
    case openWebsite(url: URL, displayText: String)
    case searchGoogle(query: String)

    public init?(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if Self.containsChainDomain(text) {
            self = .searchGoogle(query: text)
        } else if let website = Self.website(from: text) {
            self = .openWebsite(url: website, displayText: Self.displayText(for: website))
        } else {
            self = .searchGoogle(query: text)
        }
    }

    public static func googleSearchQuery(from url: URL) -> String? {
        guard let host = url.host(percentEncoded: false)?.lowercased(),
              (host == "google.com" || host.hasSuffix(".google.com")),
              url.path.lowercased().hasPrefix("/search"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        return components.queryItems?
            .first { $0.name.lowercased() == "q" }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    public static func googleSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    static func isSameDestination(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhs = normalizedDestination(lhs),
              let rhs = normalizedDestination(rhs) else { return false }
        return lhs == rhs
    }

    private static func normalizedDestination(_ url: URL) -> URLComponents? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.percentEncodedPath == "/" {
            components.percentEncodedPath = ""
        }
        // Paths, queries and fragments may select different pages on the same host.
        return components
    }

    private static func website(from text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }

        let hasScheme = text.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#,
            options: .regularExpression
        ) != nil
        let candidate = hasScheme ? text : "https://\(text)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil, components.password == nil,
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              isWebHost(host),
              let url = components.url else {
            return nil
        }
        return url
    }

    private static func containsChainDomain(_ text: String) -> Bool {
        if ApiChain.allCases.contains(where: { $0.isValidDomain(text) }) {
            return true
        }
        let candidate = text.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#,
            options: .regularExpression
        ) == nil ? "https://\(text)" : text
        guard let host = URLComponents(string: candidate)?.host else { return false }
        return ApiChain.allCases.contains { $0.isValidDomain(host) }
    }

    private static func isWebHost(_ host: String) -> Bool {
        let host = host.lowercased()
        guard !host.isEmpty else { return false }
        if host == "localhost" { return true }
        if host.contains(":") { return true }
        if host.split(separator: ".").count == 4,
           host.split(separator: ".").allSatisfy({ UInt8($0) != nil }) {
            return true
        }
        guard host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix(".") else {
            return false
        }
        return true
    }

    private static func displayText(for url: URL) -> String {
        var result = url.absoluteString
        if let scheme = url.scheme {
            result.removeFirst(min(result.count, scheme.count + 3))
        }
        if result.hasSuffix("/") {
            result.removeLast()
        }
        return result.removingPercentEncoding ?? result
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
