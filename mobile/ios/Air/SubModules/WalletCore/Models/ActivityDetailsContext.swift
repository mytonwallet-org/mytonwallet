import WalletContext

public enum ActivityDetailsContext {
    case normal
    case external
    case sendConfirmation
    case swapConfirmation
    case onchainSwapConfirmation
    case stakeConfirmation
    case unstakeConfirmation
    case unstakeRequestConfirmation
    
    public var isTransactionConfirmation: Bool {
        switch self {
        case .normal, .external: false
        case .sendConfirmation, .swapConfirmation, .onchainSwapConfirmation, .stakeConfirmation, .unstakeConfirmation, .unstakeRequestConfirmation: true
        }
    }
    
    public var displayTitle: String? {
        switch self {
        case .normal, .external: nil
        case .sendConfirmation: lang("Sent")
        case .swapConfirmation: lang("Swap Placed")
        case .onchainSwapConfirmation: lang("Swapped")
        case .stakeConfirmation: lang("Staked")
        case .unstakeConfirmation: lang("Unstaked")
        case .unstakeRequestConfirmation: lang("Unstake Requested")
        }
    }
}
