
import WalletContext
import UIKit
import SwiftUI


public enum SignData: @unchecked Sendable {
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
