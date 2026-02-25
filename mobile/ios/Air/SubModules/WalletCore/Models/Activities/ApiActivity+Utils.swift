
import UIKit
import WalletContext

public struct ApiTransactionTypeTitles: ExpressibleByArrayLiteral {
    public let complete: String
    public let inProgress: String
    public let future: String
    
    public init(arrayLiteral elements: String...) {
        self.complete = elements[0]
        self.inProgress = elements[1]
        self.future = elements[2]
    }
}

public enum ActivityAccessoryStatus: Sendable {
    case pending
    case pendingTrusted
    case failed
    case hold
    case expired
}

public extension ApiActivity {
    var displayTitle: ApiTransactionTypeTitles {
        let base: ApiTransactionTypeTitles = switch type {
        case .stake: ["Staked", "Staking", "$stake_action"]
        case .unstake: ["Unstaked", "Unstaking", "$unstake_action"]
        case .unstakeRequest: ["Requested Unstake", "Requesting Unstake", "$request_unstake_action"]
        case .callContract: ["Called Contract", "Calling Contract", "$call_contract_action"]
        case .excess: ["Excess", "Excess", "Excess"]
        case .contractDeploy: ["Deployed Contract", "Deploying Contract", "$deploy_contract_action"]
        case .bounced: ["Bounced", "Bouncing", "$bounce_action"]
        case .mint: ["Minted", "Minting", "$mint_action"]
        case .burn: ["Burned", "Burning", "$burn_action"]
        case .auctionBid: ["NFT Auction Bid", "Bidding at NFT Auction", "NFT Auction Bid"]
        case .dnsChangeAddress: ["Updated Address", "Updating Address", "$update_address_action"]
        case .dnsChangeSite: ["Updated Site", "Updating Site", "$update_site_action"]
        case .dnsChangeSubdomains: ["Updated Subdomains", "Updating Subdomains", "$update_subdomains_action"]
        case .dnsChangeStorage: ["Updated Storage", "Updating Storage", "$update_storage_action"]
        case .dnsDelete: ["Deleted Domain Record", "Deleting Domain Record", "$delete_domain_record_action"]
        case .dnsRenew: ["Renewed Domain", "Renewing Domain", "$renew_domain_action"]
        case .liquidityDeposit: ["Provided Liquidity", "Providing Liquidity", "$provide_liquidity_action"]
        case .liquidityWithdraw: ["Withdrawn Liquidity", "Withdrawing Liquidity", "$withdraw_liquidity_action"]
        
        case .nftTrade: ["NFT Bought", "Buying NFT", "Buy NFT"]
        case .nftPurchase: ["NFT Bought", "Buying NFT", "Buy NFT"]
        case .nftReceived: ["Received NFT", "Receiving", "$receive_action"]
        case .nftTransferred: ["Sent NFT", "Sending", "$send_action"]
        case .swap:  ["Swapped", "Swap", "Swap"]
            
        case nil:
            if transaction?.nft != nil {
                if transaction?.isIncoming == true {
                    ["Received NFT", "Receiving", "$receive_action"]
                } else {
                    ["Sent NFT", "Sending", "$send_action"]
                }
            } else {
                if transaction?.isIncoming == true {
                    ["Received", "Receiving", "$receive_action"]
                } else {
                    ["Sent", "Sending", "$send_action"]
                }
            }
        }
        return [lang(base.complete), lang(base.inProgress), lang(base.future)]
    }
    
    var displayTitleResolved: String {
        let displayTitle = self.displayTitle
        let resolved = if swap?.status == .expired || swap?.status == .failed || transaction?.status == .failed {
            displayTitle.future
        } else if isLocal || getIsActivityPending(self) || swap?.status == .pending || swap?.status == .pendingTrusted {
            displayTitle.inProgress
        } else {
            displayTitle.complete
        }
        return resolved
    }

    var displayTitleResolvedOptimistic: String {
        let displayTitle = self.displayTitle
        let resolved = if swap?.status == .expired || swap?.status == .failed || transaction?.status == .failed {
            displayTitle.future
        } else {
            displayTitle.complete
        }
//        return "\(abs(id.hashValue) % 1000) " + resolved + " " + (transaction?.status.rawValue ?? "")
        return resolved
    }
}

public func activityAccessoryStatus(for activity: ApiActivity) -> ActivityAccessoryStatus? {
    if activity.isLocal {
        return .pendingTrusted
    }
    switch activity {
    case .transaction(let tx):
        switch tx.status {
        case .pending:
            return tx.isIncoming ? .pending : .pendingTrusted
        case .pendingTrusted:
            return .pendingTrusted
        case .failed:
            return .failed
        case .completed, .confirmed:
            return nil
        }
    case .swap(let swap):
        if let cexStatus = swap.cex?.status {
            switch cexStatus {
            case .hold:
                return .hold
            case .expired, .overdue:
                return .expired
            case .failed:
                return .failed
            default:
                break
            }
        }
        switch swap.status {
        case .pending, .pendingTrusted:
            return .pendingTrusted
        case .failed:
            return .failed
        case .expired:
            return .expired
        case .completed, .confirmed:
            return nil
        }
    }
}

public extension ApiActivity {
    
    var isStakingTransaction: Bool {
        switch type {
        case .stake, .unstake, .unstakeRequest:
            return true
        default:
            return false
        }
    }
    
    var isDnsOperation: Bool {
        switch type {
        case .dnsChangeAddress, .dnsChangeSite, .dnsChangeStorage, .dnsChangeSubdomains, .dnsDelete, .dnsRenew:
            return true
        default:
            return false
        }
    }
}
 

public extension ApiActivity {
    var avatarContent: AvatarContent {
        let icon: String = switch self.type {
        case .stake, .unstake, .unstakeRequest:
            "ActionStake"
        case .nftReceived:
            "ActionReceive"
        case .nftTransferred:
            "ActionSend"
        case .callContract:
            "ActionContract"
        case .excess:
            "ActionReceive"
        case .contractDeploy:
            "ActionContract"
        case .bounced:
            "ActionReceive"
        case .mint:
            "ActionMint"
        case .burn:
            "ActionBurn"
        case .auctionBid:
            "ActionAuctionBid"
        case .nftTrade:
            "ActionNftBought"
        case .nftPurchase:
            "ActionNftBought"
        case .dnsChangeAddress, .dnsChangeSite, .dnsChangeSubdomains, .dnsChangeStorage, .dnsDelete, .dnsRenew:
            "ActionSiteTon"
        case .liquidityDeposit:
            "ActionProvidedLiquidity"
        case .liquidityWithdraw:
            "ActionWithdrawnLiquidity"
        case .swap:
            "ActionSwap"
        case nil:
            transaction?.isIncoming == true ? "ActionReceive" : "ActionSend"
        }
        return .image(icon)
    }
    
    private var green: [UIColor] { WColors.greenGradient }
    private var red: [UIColor] { WColors.redGradient }
    private var gray: [UIColor] { WColors.grayGradient }
    private var blue: [UIColor] { WColors.blueGradient }
    private var indigo: [UIColor] { WColors.indigoGradient }
    
    var iconColors: [UIColor] {
        let colors: [UIColor] = switch self.type {
        case .stake:
            indigo
        case .unstake:
            green
        case .unstakeRequest:
            blue
        case .nftReceived:
            green
        case .nftTransferred:
            blue
        case .callContract:
            gray
        case .excess:
            green
        case .contractDeploy:
            gray
        case .bounced:
            red
        case .mint:
            green
        case .burn:
            red
        case .auctionBid:
            blue
        case .nftTrade:
            blue
        case .nftPurchase:
            blue
        case .dnsChangeAddress, .dnsChangeSite, .dnsChangeSubdomains, .dnsChangeStorage, .dnsDelete, .dnsRenew:
            gray
        case .liquidityDeposit:
            blue
        case .liquidityWithdraw:
            green
        case .swap:
            if case .swap(let swap) = self {
                if swap.cex?.status == .hold {
                    gray
                } else if swap.status == .expired || swap.status == .failed {
                    red
                } else {
                    blue
                }
            } else {
                blue
            }
        case nil:
            if transaction?.status == .failed {
                red
            } else {
                transaction?.isIncoming == true ? green : blue
            }
        }
        return colors
    }
    
    var addressToShow: String {
        return transaction?.addressToShow ?? " "
    }
    
    var peerAddress: String? {
        return transaction?.isIncoming == true ? transaction?.fromAddress : transaction?.toAddress
    }
}


public extension ApiActivity {
    func shouldIncludeForSlug(_ tokenSlug: String?) -> Bool {
        if let tokenSlug {
            return switch self {
            case .transaction(let tx):
                tx.slug == tokenSlug
            case .swap(let swap):
                swap.to == tokenSlug || swap.from == tokenSlug
            }
        } else {
            return true
        }
    }
}


public extension ApiActivity {
    
    var isTinyOrScamTransaction: Bool {
        if isScamTransaction {
            return true
        }
        switch self {
        case .transaction(let transaction):
            if transaction.nft != nil {
                return false
            }
            
            let isOutgoingBouncedSpam = type == .bounced && !transaction.isIncoming
            if type != nil && !isOutgoingBouncedSpam {
                return false
            }
            
            guard let token = TokenStore.tokens[slug] else {
                return false
            }
            return abs(bigIntToDouble(amount: transaction.amount, decimals: token.decimals)) * (token.priceUsd ?? 0) < TINY_TRANSFER_MAX_COST
        case .swap:
            return false
        }
    }
    
    var isScamTransaction: Bool {
        return transaction?.metadata?.isScam == true // TODO: ||  getIsTransactionWithPoisoning(transaction))
    }

    var shouldShowTransactionComment: Bool {
        return !isStakingTransaction && !isScamTransaction
    }

    enum AmountDisplayMode {
        case hide
        case noSign
        case normal
        case swap
    }
    var amountDisplayMode: AmountDisplayMode {
        switch self {
        case .transaction(let tx):
            let isPlainTransfer = type == nil && tx.nft == nil
            if !isPlainTransfer && tx.amount == 0 {
                return .hide
            } else if type == .stake || type == .unstake {
                return .noSign
            } else {
                return .normal
            }
        case .swap:
            return .swap
        }
    }

    var shouldShowTransactionAddress: Bool {
        if case .transaction(let transaction) = self {
            let shouldHide = isOurStakingTransaction
                || type == .burn
                || type == .nftPurchase
                || type == .nftTrade
                || (!transaction.isIncoming && transaction.nft != nil && transaction.toAddress == transaction.nft?.address)
                || (transaction.isIncoming && type == .excess && transaction.fromAddress == BURN_ADDRESS)

          return !shouldHide;
        }
        return false
    }
    
    /** "Our" is staking that can be controlled with MyTonWallet app */
    var isOurStakingTransaction: Bool {
        if case .transaction(let tx) = self {
            return isStakingTransaction && ALL_STAKING_POOLS.contains(tx.isIncoming ? tx.fromAddress ?? "" : tx.toAddress ?? "")
        }
        return false
    }

    var shouldShowTransactionAnnualYield: Bool {
        return type == .stake && isOurStakingTransaction
    }
    
    var timestampDate: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }
}
