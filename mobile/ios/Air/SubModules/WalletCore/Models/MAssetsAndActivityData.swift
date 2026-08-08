//
//  MAssetsAndActivityData.swift
//  WalletCore
//
//  Created by Sina on 7/5/24.
//

import OrderedCollections
import WalletContext

public enum MChainDisplayMode: String, Equatable, Hashable, Codable, Sendable {
    case value
    case manual
}

public struct MChainDisplayConfiguration: Equatable, Hashable, Codable, Sendable {
    public private(set) var displayMode: MChainDisplayMode
    public private(set) var hiddenChains: [ApiChain]
    public private(set) var shownChains: [ApiChain]
    public private(set) var manualOrder: [ApiChain]

    public init(
        displayMode: MChainDisplayMode = .value,
        hiddenChains: [ApiChain] = [],
        shownChains: [ApiChain] = [],
        manualOrder: [ApiChain] = []
    ) {
        self.displayMode = displayMode
        self.hiddenChains = Self.unique(hiddenChains)
        let hiddenChains = Set(self.hiddenChains)
        self.shownChains = Self.unique(shownChains).filter { !hiddenChains.contains($0) }
        self.manualOrder = Self.unique(manualOrder)
    }

    public var isDefault: Bool {
        displayMode == .value && hiddenChains.isEmpty && shownChains.isEmpty && manualOrder.isEmpty
    }

    public mutating func setDisplayMode(_ displayMode: MChainDisplayMode, capturing order: [ApiChain]? = nil) {
        self.displayMode = displayMode
        if displayMode == .manual, let order {
            manualOrder = Self.unique(order)
        }
    }

    public func isVisible(_ chain: ApiChain, automaticallyVisibleChains: Set<ApiChain>) -> Bool {
        if hiddenChains.contains(chain) {
            return false
        } else if shownChains.contains(chain) {
            return true
        } else {
            return automaticallyVisibleChains.contains(chain)
        }
    }

    public mutating func setVisible(
        _ chain: ApiChain,
        isVisible: Bool,
        automaticallyVisible: Bool
    ) {
        hiddenChains.removeAll { $0 == chain }
        shownChains.removeAll { $0 == chain }
        if !isVisible {
            manualOrder.removeAll { $0 == chain }
        }

        guard isVisible != automaticallyVisible else { return }
        if isVisible {
            shownChains.append(chain)
        } else {
            hiddenChains.append(chain)
        }
    }

    public mutating func setManualOrder(
        _ manualOrder: [ApiChain],
        automaticallyVisibleChains: Set<ApiChain>
    ) {
        self.manualOrder = Self.unique(manualOrder).filter { chain in
            isVisible(chain, automaticallyVisibleChains: automaticallyVisibleChains)
        }
    }

    public func orderedChains(
        defaultOrder: [ApiChain],
        valueOrder: [ApiChain],
        automaticallyVisibleChains: Set<ApiChain>
    ) -> [ApiChain] {
        let defaultOrder = Self.unique(defaultOrder)
        let availableChains = Set(defaultOrder)

        if displayMode == .value {
            let availableValueOrder = Self.unique(valueOrder).filter { availableChains.contains($0) }
            let valueOrderedChains = Set(availableValueOrder)
            let orderedChains = availableValueOrder + defaultOrder.filter { !valueOrderedChains.contains($0) }
            return Self.groupingVisibleFirst(
                orderedChains,
                isVisible: automaticallyVisibleChains.contains
            )
        }

        let visibleChains = normalizedManualOrder(
            defaultOrder: defaultOrder,
            automaticallyVisibleChains: automaticallyVisibleChains
        )
        let visibleChainSet = Set(visibleChains)
        let availableValueOrder = Self.unique(valueOrder).filter { availableChains.contains($0) }
        let valueOrderedChains = Set(availableValueOrder)
        let completeValueOrder = availableValueOrder + defaultOrder.filter { !valueOrderedChains.contains($0) }
        return visibleChains + completeValueOrder.filter { !visibleChainSet.contains($0) }
    }

    public func normalizedManualOrder(
        defaultOrder: [ApiChain],
        automaticallyVisibleChains: Set<ApiChain>
    ) -> [ApiChain] {
        let defaultOrder = Self.unique(defaultOrder)
        let availableChains = Set(defaultOrder)
        let availableManualOrder = manualOrder.filter {
            availableChains.contains($0)
                && isVisible($0, automaticallyVisibleChains: automaticallyVisibleChains)
        }
        let manuallyOrderedChains = Set(availableManualOrder)
        return availableManualOrder + defaultOrder.filter { chain in
            !manuallyOrderedChains.contains(chain)
                && isVisible(chain, automaticallyVisibleChains: automaticallyVisibleChains)
        }
    }

    public func visibleChains(
        defaultOrder: [ApiChain],
        valueOrder: [ApiChain],
        automaticallyVisibleChains: Set<ApiChain>,
        including requiredChain: ApiChain? = nil
    ) -> [ApiChain] {
        let orderedChains = orderedChains(
            defaultOrder: defaultOrder,
            valueOrder: valueOrder,
            automaticallyVisibleChains: automaticallyVisibleChains
        )
        let visibleChains = orderedChains.filter { chain in
            chain == requiredChain
                || (displayMode == .value
                    ? automaticallyVisibleChains.contains(chain)
                    : isVisible(chain, automaticallyVisibleChains: automaticallyVisibleChains))
        }
        guard visibleChains.isEmpty else { return visibleChains }
        let fallbackChain = displayMode == .value
            ? orderedChains.first
            : defaultOrder.first { !hiddenChains.contains($0) } ?? defaultOrder.first
        return fallbackChain.map { [$0] } ?? []
    }

    public static func automaticallyVisibleChains(
        defaultOrder: [ApiChain],
        chainsWithBalance: Set<ApiChain>,
        hasTokenBalance: Bool,
        isGramWallet: Bool
    ) -> Set<ApiChain> {
        let defaultOrder = Self.unique(defaultOrder)
        if !hasTokenBalance {
            return isGramWallet ? Set(defaultOrder.filter { $0 == .ton }) : Set(defaultOrder)
        }

        let availableChainsWithBalance = chainsWithBalance.intersection(defaultOrder)
        return availableChainsWithBalance.isEmpty
            ? Set(defaultOrder.prefix(1))
            : availableChainsWithBalance
    }

    private static func unique(_ chains: [ApiChain]) -> [ApiChain] {
        Array(OrderedSet(chains))
    }

    private static func groupingVisibleFirst(
        _ chains: [ApiChain],
        isVisible: (ApiChain) -> Bool
    ) -> [ApiChain] {
        chains.filter(isVisible) + chains.filter { !isVisible($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case displayMode
        case hiddenChains
        case shownChains
        case manualOrder
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hiddenChains = try container.decodeIfPresent([ApiChain].self, forKey: .hiddenChains) ?? []
        let shownChains = try container.decodeIfPresent([ApiChain].self, forKey: .shownChains) ?? []
        let manualOrder = try container.decodeIfPresent([ApiChain].self, forKey: .manualOrder) ?? []
        let displayMode = try container.decodeIfPresent(MChainDisplayMode.self, forKey: .displayMode)
            ?? ((hiddenChains.isEmpty && shownChains.isEmpty && manualOrder.isEmpty) ? .value : .manual)
        self.init(
            displayMode: displayMode,
            hiddenChains: hiddenChains,
            shownChains: shownChains,
            manualOrder: manualOrder
        )
    }
}

public struct MAssetsAndActivityData: Equatable, Sendable {
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

    public private(set) var chainDisplayConfiguration: MChainDisplayConfiguration?

    init(dictionary: [String: Any]?) {
        if let dictionary {
            // alwaysShownSlugs = Set(dictionary["alwaysShownSlugs"] as? [String] ?? [])
            alwaysHiddenSlugs = Set(dictionary["alwaysHiddenSlugs"] as? [String] ?? [])
            importedSlugs = Set(dictionary["importedSlugs"] as? [String] ?? [])
            _pinnedSlugs = (dictionary["pinnedSlugs"] as? [String]).map { OrderedSet($0) }
            chainDisplayConfiguration = dictionary["chainDisplayConfiguration"] as? MChainDisplayConfiguration
        } else {
            // alwaysShownSlugs = []
            alwaysHiddenSlugs = []
            importedSlugs = []
            _pinnedSlugs = nil
            chainDisplayConfiguration = nil
        }
    }

    var toDictionary: [String: Any] {
        var dict: [String: Any] = [
            // "alwaysShownSlugs": Array(alwaysShownSlugs),
            "alwaysHiddenSlugs": Array(alwaysHiddenSlugs),
            "importedSlugs": Array(importedSlugs),
        ]

        if let _pinnedSlugs {
            dict["pinnedSlugs"] = Array(_pinnedSlugs)
        }
        if let chainDisplayConfiguration {
            dict["chainDisplayConfiguration"] = chainDisplayConfiguration
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

    // MARK: Chains

    public var chainDisplayMode: MChainDisplayMode {
        chainDisplayConfiguration?.displayMode ?? .value
    }

    public var hiddenChains: [ApiChain] {
        chainDisplayConfiguration?.hiddenChains ?? []
    }

    public var shownChains: [ApiChain] {
        chainDisplayConfiguration?.shownChains ?? []
    }

    public mutating func saveChainDisplayMode(
        _ displayMode: MChainDisplayMode,
        capturing order: [ApiChain]? = nil
    ) {
        var configuration = chainDisplayConfiguration ?? MChainDisplayConfiguration()
        configuration.setDisplayMode(displayMode, capturing: order)
        chainDisplayConfiguration = configuration.isDefault ? nil : configuration
    }

    public mutating func saveChainVisible(
        _ chain: ApiChain,
        isVisible: Bool,
        automaticallyVisible: Bool
    ) {
        var configuration = chainDisplayConfiguration ?? MChainDisplayConfiguration(displayMode: .manual)
        configuration.setDisplayMode(.manual)
        configuration.setVisible(
            chain,
            isVisible: isVisible,
            automaticallyVisible: automaticallyVisible
        )
        chainDisplayConfiguration = configuration.isDefault ? nil : configuration
    }

    public mutating func saveChainOrder(
        _ manualOrder: [ApiChain],
        automaticallyVisibleChains: Set<ApiChain>
    ) {
        var configuration = chainDisplayConfiguration ?? MChainDisplayConfiguration(displayMode: .manual)
        configuration.setDisplayMode(.manual)
        configuration.setManualOrder(
            manualOrder,
            automaticallyVisibleChains: automaticallyVisibleChains
        )
        chainDisplayConfiguration = configuration.isDefault ? nil : configuration
    }

    public func visibleChains(
        defaultOrder: [ApiChain],
        valueOrder: [ApiChain],
        automaticallyVisibleChains: Set<ApiChain>,
        including requiredChain: ApiChain? = nil
    ) -> [ApiChain] {
        (chainDisplayConfiguration ?? MChainDisplayConfiguration())
            .visibleChains(
                defaultOrder: defaultOrder,
                valueOrder: valueOrder,
                automaticallyVisibleChains: automaticallyVisibleChains,
                including: requiredChain
            )
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

    public var hasPinnedTokens: Bool {
        !pinnedSlugs.isEmpty
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
