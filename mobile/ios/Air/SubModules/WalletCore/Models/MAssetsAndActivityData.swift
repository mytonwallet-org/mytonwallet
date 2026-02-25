//
//  MAssetsAndActivityData.swift
//  WalletCore
//
//  Created by Sina on 7/5/24.
//

import OrderedCollections
import WalletContext

public struct MAssetsAndActivityData: Equatable {
    public static var empty: Self { MAssetsAndActivityData(dictionary: nil) }

    /// These tokens will be visible even if they are no cost tokens! Because user checked them manually!
    // public private(set) var alwaysShownSlugs: Set<String>

    /// Hidden tokens won't be shown in Home-Page wallet tokens
    private var alwaysHiddenSlugs: Set<String>

    /// AddedTokens show tokens will be shown even if user don't have them!
    public private(set) var importedSlugs: Set<String>

    /// Pinned tokens are shown at the top of  screen. Most recently pinned token is in the end of this Set.
    private var pinnedSlugs: OrderedSet<String> { _pinnedSlugs ?? [] }
    private var _pinnedSlugs: OrderedSet<String>?

    public var pinningFeatureHasNotYetBeenEverUsed: Bool {
        _pinnedSlugs == nil
    }

    init(dictionary: [String: Any]?) {
        if let dictionary {
            // alwaysShownSlugs = Set(dictionary["alwaysShownSlugs"] as? [String] ?? [])
            alwaysHiddenSlugs = Set(dictionary["alwaysHiddenSlugs"] as? [String] ?? [])
            importedSlugs = Set(dictionary["importedSlugs"] as? [String] ?? [])
            _pinnedSlugs = (dictionary["pinnedSlugs"] as? [String]).map { OrderedSet($0) }
        } else {
            // alwaysShownSlugs = []
            alwaysHiddenSlugs = []
            importedSlugs = []
            _pinnedSlugs = nil
        }
    }

    var toDictionary: [String: Any] {
        var dict = [
            // "alwaysShownSlugs": Array(alwaysShownSlugs),
            "alwaysHiddenSlugs": Array(alwaysHiddenSlugs),
            "importedSlugs": Array(importedSlugs),
        ]

        if let _pinnedSlugs {
            dict["pinnedSlugs"] = Array(_pinnedSlugs)
        }

        return dict
    }

    // MARK: Hide

    public mutating func saveTokenHidden(slug: String, isStaking: Bool, isHidden: Bool) {
        let tokenIdentity = makeTokenIdentity(slug: slug, isStaked: isStaking)

        if isHidden {
            alwaysHiddenSlugs.insert(tokenIdentity)
            // alwaysShownSlugs.remove(tokenIdentity)
        } else {
            alwaysHiddenSlugs.remove(tokenIdentity)
            // alwaysShownSlugs.insert(tokenIdentity)
        }
    }

    public func isTokenHidden(slug: String, isStaking: Bool) -> Bool {
        let tokenIdentity = makeTokenIdentity(slug: slug, isStaked: isStaking)
        return alwaysHiddenSlugs.contains(tokenIdentity)
    }

    // MARK: Pinning

    public mutating func saveTokenPinning(slug: String, isStaking: Bool, isPinned: Bool) {
        if _pinnedSlugs == nil { _pinnedSlugs = [] }

        let tokenIdentity = makeTokenIdentity(slug: slug, isStaked: isStaking)
        if isPinned {
            _pinnedSlugs?.append(tokenIdentity)
        } else {
            _pinnedSlugs?.remove(tokenIdentity)
        }
    }

    public enum PinningInfo {
        case pinned(index: Int)
        case notPinned
    }

    public func isTokenPinned(slug: String, isStaked: Bool) -> PinningInfo {
        let tokenIdentity = makeTokenIdentity(slug: slug, isStaked: isStaked)

        return if let index = pinnedSlugs.firstIndex(of: tokenIdentity) {
            .pinned(index: index)
        } else {
            .notPinned
        }
    }

    private func makeTokenIdentity(slug: String, isStaked: Bool) -> String {
        isStaked ? "staking-" + slug : slug
    }

    // MARK: Imported tokens

    public mutating func saveImportedToken(slug: String) {
        importedSlugs.insert(slug)
    }

    public mutating func removeImportedToken(slug: String) {
        importedSlugs.remove(slug)
    }
}
