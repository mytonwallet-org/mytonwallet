
import WalletContext
import UIKit
import SwiftUI


public enum SignData: @unchecked Sendable {
    case signTransfer(
        transferOptions: Api.SubmitTransferOptions
    )

     case signDappTransfers(
         update: MDappSendTransactions
     )

     case signLedgerProof(
         promiseId: String,
         proof: ApiTonConnectProof?
     )

     case signNftTransfer(
         accountId: String,
         nft: ApiNft,
         toAddress: String,
         comment: String?,
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
