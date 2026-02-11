//
//  BaseActivity.swift
//  WalletCore
//
//  Created by nikstar on 10.08.2025.
//

import Foundation

public protocol BaseActivity: Identifiable {
    var id: String { get }
    var shouldHide: Bool? { get }
    /** Trace external message hash normalized. Not unique but doesn't change in pending activities. Only for TON. */
    var externalMsgHashNorm: String? { get }
    /** Whether the activity data should be re-loaded to get the necessary data before showing in the activity list */
    var shouldReload: Bool? { get }
    /// Whether more details should be loaded by calling the `fetchTonActivityDetails` action. Undefined means "no".
    var shouldLoadDetails: Bool? { get }
    var extra: BaseActivityExtra? { get }
}

public struct BaseActivityExtra: Equatable, Hashable, Codable, Sendable {
    /// Only for TON
    public var withW5Gasless: Bool?
    /// Only for TON liquidity deposit and withdrawal
    public var dex: ApiSwapDexLabel? // Only for TON liquidity deposit and withdrawal
    public var marketplace: ApiNftMarketplace?
    public var queryId: String?
    public var isOurSwapFee: Bool?
    public var mtwAggregator: ApiMtwAggregator?
    // TODO Move other extra fields here (externalMsgHash, ...)
}

public struct ApiMtwAggregator: Equatable, Hashable, Codable, Sendable {
    public let traceId: String
    public let swapIds: [String]
    public let from: String
    public let to: String
}
