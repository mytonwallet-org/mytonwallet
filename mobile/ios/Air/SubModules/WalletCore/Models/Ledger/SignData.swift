
import WalletContext
import UIKit
import SwiftUI
import WalletCoreTypes


public enum SignData: Sendable {
    case signTransfer(
        transferOptions: ApiSubmitTransferOptions
    )

     case signDappTransfers(
         update: ApiUpdate.DappSendTransactions
     )

     case signLedgerProof(
         promiseId: String,
         proof: ApiTonConnectProof?
     )

     case signNftTransfer(
         chain: ApiChain,
         accountId: String,
         nft: ApiNft,
         toAddress: String,
         comment: String?,
         realFee: BigInt?,
         isNftBurn: Bool?,
     )

     case signNftTransfers(
         chain: ApiChain,
         accountId: String,
         nfts: [ApiNft],
         toAddress: String,
         comment: String?,
         realFee: BigInt?,
         isNftBurn: Bool?,
     )

    case linkDomain(
        accountId: String,
        nft: ApiNft,
        address: String,
        realFee: BigInt?
    )

    case renewDomains(
        accountId: String,
        nfts: [ApiNft],
        realFee: BigInt?
    )
    
    case staking(
        isStaking: Bool,
        accountId: String,
        amount: BigInt,
        stakingState: ApiStakingState,
        realFee: BigInt?
    )
    
    case submitStakingClaimOrUnlock(
        accountId: String,
        state: ApiStakingState,
        realFee: BigInt?
    )
}
