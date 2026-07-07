//
//  SwapHistoryItem.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

import Foundation
import WalletCoreTypes

public struct ApiSwapHistoryItem: Codable, Sendable {
    public let id: String
    public let timestamp: Int64
    public let lt: Int64?
    public let from: String
    public let fromAddress: String?
    public let fromAmount: MDouble
    public let to: String
    public let toAmount: MDouble
    /** The real fee in the chain's native token */
    public let networkFee: MDouble?
    public let swapFee: MDouble
    public let ourFee: MDouble?
    public let ourFeeMode: String?
    public let cexLabel: ApiSwapCexLabel?
    
    /**
     * Swap confirmation status
     * Both 'pendingTrusted' and 'pending' mean the swap is awaiting confirmation by the blockchain.
     * - 'pendingTrusted' — awaiting confirmation and trusted (initiated by our app).
     * - 'pending' — awaiting confirmation from an external/unauthenticated source.
     *
     * There are two backends: ToncenterApi and our backend.
     * Swaps returned by ToncenterApi have the status 'pending'.
     * Swaps returned by our backend also have the status 'pending', but they are meant to be 'pendingTrusted'.
     * When an activity reaches the `GlobalState`, it already has the correct status set.
     */
    public let status: ApiSwapStatus
    public var hashes: [String]
    public var transactionIds: ApiSwapTransactionIds
    public let isCanceled: Bool?
    public let cex: ApiSwapCexTransactionExtras?
    
    public static func makeFrom(swapBuildRequest: ApiSwapBuildRequest, swapId: String) -> ApiSwapHistoryItem {
        ApiSwapHistoryItem(
            id: swapId,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            lt: nil,
            from: swapBuildRequest.from,
            fromAddress: swapBuildRequest.fromAddress,
            fromAmount: swapBuildRequest.fromAmount,
            to: swapBuildRequest.to,
            toAmount: swapBuildRequest.toAmount ?? .zero,
            networkFee:  swapBuildRequest.networkFee,
            swapFee: swapBuildRequest.swapFee ?? .zero,
            ourFee: swapBuildRequest.ourFee,
            ourFeeMode: nil,
            cexLabel: nil,
            status: .pendingTrusted,
            hashes: [],
            transactionIds: .init(),
            isCanceled: nil,
            cex: nil
        )
    }
}
