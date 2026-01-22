//
//  SwapHistoryItem.swift
//  MyTonWalletAir
//
//  Created by nikstar on 31.08.2025.
//

import Foundation

public struct ApiSwapHistoryItem: Codable {
    public let id: String
    public let timestamp: Int64
    public let lt: Int64?
    public let from: String
    public let fromAmount: MDouble
    public let to: String
    public let toAmount: MDouble
    /** The real fee in the chain's native token */
    public let networkFee: MDouble?
    public let swapFee: MDouble
    public let ourFee: MDouble?
    
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
    public let isCanceled: Bool?
    public let cex: ApiSwapCexTransactionExtras?
    
    public static func makeFrom(swapBuildRequest: ApiSwapBuildRequest, swapTransferData: ApiSwapBuildResponse) -> ApiSwapHistoryItem {
        ApiSwapHistoryItem(
            id: swapTransferData.id,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            lt: nil,
            from: swapBuildRequest.from,
            fromAmount: swapBuildRequest.fromAmount,
            to: swapBuildRequest.to,
            toAmount: swapBuildRequest.toAmount,
            networkFee:  swapBuildRequest.networkFee,
            swapFee: swapBuildRequest.swapFee,
            ourFee: swapBuildRequest.ourFee,
            status: .pending,
            hashes: [],
            isCanceled: nil,
            cex: nil
        )
    }
}
