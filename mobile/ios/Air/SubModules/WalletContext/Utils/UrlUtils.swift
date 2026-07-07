//
//  UrlUtils.swift
//  WalletContext
//
//  Created by Sina on 8/13/24.
//

import Foundation

extension URL {
    public static func sanitizedHttpUrl(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.nilIfEmpty != nil else {
            return nil
        }

        return url
    }

    public static func sanitizedMailtoUrl(email rawEmail: String?) -> URL? {
        sanitizedMailtoLink(email: rawEmail)?.url
    }

    public static func sanitizedMailtoLink(email rawEmail: String?) -> (email: String, url: URL)? {
        guard let rawEmail else {
            return nil
        }

        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty,
              email.contains("@"),
              !email.contains(where: { $0.isWhitespace }),
              let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        guard let url = URL(string: "mailto:\(encodedEmail)") else {
            return nil
        }

        return (email, url)
    }

    public var isTelegramURL: Bool {
        let normalizedScheme = scheme?.lowercased()
        if normalizedScheme == "tg" {
            return true
        }

        guard (normalizedScheme == "http" || normalizedScheme == "https"),
              let host = host?.lowercased() else {
            return false
        }

        return host == "t.me" || host == "telegram.me"
    }

    public var isSubproject: Bool {
        guard let host = self.host?.lowercased() else {
            return false
        }
        if APP_ROOT_URL_DOMAINS.contains(where: { domain in host.hasSuffix(".\(domain)") }) {
            return true
        }
        guard host == "localhost", let port = self.port else {
            return false
        }
        return String(port).hasPrefix("432")
    }

    public var origin: String? {
        guard let scheme = self.scheme, let host = self.host else {
            return nil
        }
        var origin = "\(scheme)://\(host)"
        if let port = self.port {
            origin += ":\(port)"
        }
        return origin
    }

    public var queryParameters: [String: String]? {
        guard
            let components = URLComponents(url: self, resolvingAgainstBaseURL: true),
            let queryItems = components.queryItems else { return nil }
        return queryItems.reduce(into: [String: String]()) { (result, item) in
            result[item.name] = item.value
        }
    }
}
