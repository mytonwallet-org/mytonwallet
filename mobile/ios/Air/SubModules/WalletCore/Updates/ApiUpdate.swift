
import WalletContext


public enum ApiUpdate: Equatable, Hashable {
    case newActivities(NewActivities)
    case newLocalActivity(NewLocalActivities)
    case updateBalances(UpdateBalances)
    case updateStaking(UpdateStaking)
    case updateTokens(UpdateTokens)
    case updateSwapTokens(UpdateSwapTokens)
    case updateNfts(UpdateNfts)
    case nftReceived(NftReceived)
    case nftSent(NftSent)
    case nftPutUpForSale(NftPutUpForSale)
    // more coming soon...
}
