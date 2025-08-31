//
//  Api+Dapp.swift
//  WalletCore
//
//  Created by Sina on 6/25/24.
//

import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func getDapps(accountId: String) async throws -> [ApiDapp] {
        return try await bridge.callApi("getDapps", accountId, decoding: [ApiDapp].self)
    }
    
    /// url -> id -> dapp
    public static func getDappsByUrl(accountId: String) async throws -> [String: [String: ApiDapp]] {
        try await bridge.callApi("getDappsByUrl", accountId, decoding: [String: [String: ApiDapp]].self)
    }
    
    /// - Important: Do not call this method directly, use **DappsStore** instead
    internal static func deleteDapp(accountId: String, url: String, uniqueId: String, dontNotifyDapp: Bool?) async throws -> Any? {
        try await bridge.callApiRaw("deleteDapp", accountId, url, uniqueId, dontNotifyDapp)
    }
    
    internal static func deleteAllDapps(accountId: String) async throws {
        try await bridge.callApiVoid("deleteAllDapps", accountId)
    }
    
    public static func loadExploreSites(isLandscape: Bool = false) async throws -> ExploreSitesResult {
        struct Opts: Encodable {
            var isLandscape: Bool
        }
        return try await bridge.callApi("loadExploreSites", Opts(isLandscape: isLandscape), decoding: ExploreSitesResult.self)
    }
}


// MARK: - Types

extension Api {
    public struct ExploreSitesResult: Codable, Sendable {
        public var categories: [ApiSiteCategory]
        public var sites: [ApiSite]
    }
}
