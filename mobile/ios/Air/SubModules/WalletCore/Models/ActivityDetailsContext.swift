import WalletContext

public enum ActivityDetailsContext {
    case normal
    case external
    case sendConfirmation
    case sendNftConfirmation
    case swapConfirmation
    case stakeConfirmation
    case unstakeConfirmation
    case unstakeRequestConfirmation
    
    public var isTransactionConfirmation: Bool {
        switch self {
        case .normal, .external: false
        case .sendConfirmation, .sendNftConfirmation, .swapConfirmation, .stakeConfirmation, .unstakeConfirmation, .unstakeRequestConfirmation: true
        }
    }
    
    public var displayTitle: String? {
        switch self {
        case .normal, .external: nil
        case .sendConfirmation: lang("Coins have been sent!")
        case .sendNftConfirmation: lang("NFT has been sent!")
        case .swapConfirmation: lang("Swap Placed")
        case .stakeConfirmation: lang("Coins have been staked!")
        case .unstakeConfirmation: lang("Coins have been unstaked!")
        case .unstakeRequestConfirmation: lang("Request for unstaking is sent!")
        }
    }
}
