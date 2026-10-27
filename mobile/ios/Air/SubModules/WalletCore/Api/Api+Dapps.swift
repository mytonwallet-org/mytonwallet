//
//  Api+Dapp.swift
//  WalletCore
//
//  Created by Sina on 6/25/24.
//

import Foundation
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
    internal static func deleteDapp(accountId: String, url: String, uniqueId: String, dontNotifyDapp: Bool?) async throws -> Bool {
        try await bridge.callApi("deleteDapp", accountId, url, uniqueId, dontNotifyDapp, decoding: Bool.self)
    }
    
    internal static func deleteAllDapps(accountId: String) async throws {
        try await bridge.callApiVoid("deleteAllDapps", accountId)
    }
    
    public static func loadExploreSites(isLandscape: Bool = false, langCode: String, forceRefresh: Bool = false) async throws -> ApiExploreSitesResult {
        try await ExploreSitesCache.shared.load(isLandscape: isLandscape, langCode: langCode, forceRefresh: forceRefresh)
    }
}

@MainActor final class ExploreSitesCache {
    static let shared = ExploreSitesCache()

    private struct Key: Hashable, Encodable {
        let isLandscape: Bool
        let langCode: String
    }

    private struct Entry {
        let result: ApiExploreSitesResult
        let fetchedAt: Date
    }

    private static let validity: TimeInterval = 15 * 60
    private static let minimumRefreshInterval: TimeInterval = 60
    private let fetch: (Bool, String) async throws -> ApiExploreSitesResult
    private let now: () -> Date
    private let currentLanguage: () -> String
    private var language: String?
    private var generation = 0
    private var entries: [Key: Entry] = [:]
    private var inFlight: [Key: Task<ApiExploreSitesResult, any Error>] = [:]

    init(
        fetch: @escaping (Bool, String) async throws -> ApiExploreSitesResult = { isLandscape, langCode in
            try await Api.bridge.callApi(
                "loadExploreSites",
                Key(isLandscape: isLandscape, langCode: langCode),
                decoding: ApiExploreSitesResult.self
            )
        },
        now: @escaping () -> Date = Date.init,
        currentLanguage: @escaping () -> String = { LocalizationSupport.shared.langCode }
    ) {
        self.fetch = fetch
        self.now = now
        self.currentLanguage = currentLanguage
    }

    func load(isLandscape: Bool = false, langCode: String, forceRefresh: Bool = false) async throws -> ApiExploreSitesResult {
        let currentLanguage = currentLanguage()
        if language != currentLanguage {
            language = currentLanguage
            generation += 1
            entries.removeAll()
            inFlight.removeAll()
        }

        let key = Key(isLandscape: isLandscape, langCode: langCode)
        if let task = inFlight[key] {
            return try await task.value
        }
        let validity = forceRefresh ? Self.minimumRefreshInterval : Self.validity
        if let entry = entries[key], now().timeIntervalSince(entry.fetchedAt) < validity {
            return entry.result
        }

        let generation = generation
        let task = Task {
            defer {
                if self.generation == generation {
                    inFlight[key] = nil
                }
            }
            let result = try await fetch(isLandscape, langCode)
            if self.generation == generation {
                entries[key] = Entry(result: result, fetchedAt: now())
            }
            return result
        }
        inFlight[key] = task
        return try await task.value
    }
}


// MARK: - Types

public struct ApiExploreSitesResult: Codable, Sendable {
    public var featuredTitle: String?
    public var categories: [ApiSiteCategory]
    public var sites: [ApiSite]
}
