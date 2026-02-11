//
//  UrlUtils.swift
//  WalletContext
//
//  Created by Sina on 8/13/24.
//

import Foundation

extension URL {
    public var isSubproject: Bool {
        guard let host = self.host?.lowercased() else {
            return false
        }
        if host.hasSuffix(".mytonwallet.io") {
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
