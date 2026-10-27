import Foundation
import WalletContext

// MARK: This code has been generated based on TypeScript definitions. Do not edit manually.

public enum ApiParsedPayload: Equatable, Hashable, Codable, Sendable {
    case comment(ApiCommentPayload)
    case encryptedComment(ApiEncryptedCommentPayload)
    case nftTransfer(ApiNftTransferPayload)
    case nftOwnershipAssigned(ApiNftOwnershipAssignedPayload)
    case tokensTransfer(ApiTokensTransferPayload)
    case tokensTransferNonStandard(ApiTokensTransferNonStandardPayload)
    case unknown(ApiUnknownPayload)
    case dedustNativeSwap(ApiDedustNativeSwapPayload)
    case tokensBurn(ApiTokensBurnPayload)
    case liquidStakingDeposit(ApiLiquidStakingDepositPayload)
    case liquidStakingWithdrawal(ApiLiquidStakingWithdrawalPayload)
    case liquidStakingWithdrawalNft(ApiLiquidStakingWithdrawalNftPayload)
    case tokenBridgePaySwap(ApiTokenBridgePaySwap)
    case dnsChangeRecord(ApiDnsChangeRecord)
    case vestingAddWhitelist(ApiVestingAddWhitelistPayload)
    case singleNominatorWithdraw(ApiSingleNominatorWithdrawPayload)
    case singleNominatorChangeValidator(ApiSingleNominatorChangeValidatorPayload)
    case liquidStakingVote(ApiLiquidStakingVotePayload)
    case jettonStakingUnstake(ApiJettonStakePayload)
    case teleitemStartAuction(ApiTeleitemStartAuctionPayload)
    case teleitemCancelAuction(ApiTeleitemCancelAuctionPayload)
    case teleitemDeploy(ApiTeleitemDeployPayload)
    case teleitemBidInfo(ApiTeleitemBidInfoPayload)
    case teleitemReturnBid(ApiTeleitemReturnBidPayload)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "comment":
            self = .comment(try ApiCommentPayload(from: decoder))
        case "encrypted-comment":
            self = .encryptedComment(try ApiEncryptedCommentPayload(from: decoder))
        case "nft:transfer":
            self = .nftTransfer(try ApiNftTransferPayload(from: decoder))
        case "nft:ownership-assigned":
            self = .nftOwnershipAssigned(try ApiNftOwnershipAssignedPayload(from: decoder))
        case "tokens:transfer":
            self = .tokensTransfer(try ApiTokensTransferPayload(from: decoder))
        case "tokens:transfer-non-standard":
            self = .tokensTransferNonStandard(try ApiTokensTransferNonStandardPayload(from: decoder))
        case "unknown":
            self = .unknown(try ApiUnknownPayload(from: decoder))
        case "dedust:native-swap":
            self = .dedustNativeSwap(try ApiDedustNativeSwapPayload(from: decoder))
        case "tokens:burn":
            self = .tokensBurn(try ApiTokensBurnPayload(from: decoder))
        case "liquid-staking:deposit":
            self = .liquidStakingDeposit(try ApiLiquidStakingDepositPayload(from: decoder))
        case "liquid-staking:withdrawal":
            self = .liquidStakingWithdrawal(try ApiLiquidStakingWithdrawalPayload(from: decoder))
        case "liquid-staking:withdrawal-nft":
            self = .liquidStakingWithdrawalNft(try ApiLiquidStakingWithdrawalNftPayload(from: decoder))
        case "token-bridge:pay-swap":
            self = .tokenBridgePaySwap(try ApiTokenBridgePaySwap(from: decoder))
        case "dns:change-record":
            self = .dnsChangeRecord(try ApiDnsChangeRecord(from: decoder))
        case "vesting:add-whitelist":
            self = .vestingAddWhitelist(try ApiVestingAddWhitelistPayload(from: decoder))
        case "single-nominator:withdraw":
            self = .singleNominatorWithdraw(try ApiSingleNominatorWithdrawPayload(from: decoder))
        case "single-nominator:change-validator":
            self = .singleNominatorChangeValidator(try ApiSingleNominatorChangeValidatorPayload(from: decoder))
        case "liquid-staking:vote":
            self = .liquidStakingVote(try ApiLiquidStakingVotePayload(from: decoder))
        case "jetton-staking:unstake":
            self = .jettonStakingUnstake(try ApiJettonStakePayload(from: decoder))
        case "teleitem:start-auction":
            self = .teleitemStartAuction(try ApiTeleitemStartAuctionPayload(from: decoder))
        case "teleitem:cancel-auction":
            self = .teleitemCancelAuction(try ApiTeleitemCancelAuctionPayload(from: decoder))
        case "teleitem:deploy":
            self = .teleitemDeploy(try ApiTeleitemDeployPayload(from: decoder))
        case "teleitem:bid-info":
            self = .teleitemBidInfo(try ApiTeleitemBidInfoPayload(from: decoder))
        case "teleitem:return-bid":
            self = .teleitemReturnBid(try ApiTeleitemReturnBidPayload(from: decoder))
        default:
            assertionFailure("Unknown type: \(type)")
            self = .unknown(ApiUnknownPayload(base64: type))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .comment(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .encryptedComment(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .nftTransfer(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .nftOwnershipAssigned(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .tokensTransfer(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .tokensTransferNonStandard(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .unknown(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .dedustNativeSwap(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .tokensBurn(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingDeposit(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingWithdrawal(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingWithdrawalNft(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .tokenBridgePaySwap(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .dnsChangeRecord(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .vestingAddWhitelist(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .singleNominatorWithdraw(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .singleNominatorChangeValidator(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingVote(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .jettonStakingUnstake(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .teleitemStartAuction(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .teleitemCancelAuction(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .teleitemDeploy(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .teleitemBidInfo(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .teleitemReturnBid(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        }
    }
}

public struct ApiCommentPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "comment"
    public var comment: String
}

public struct ApiEncryptedCommentPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "encrypted-comment"
    public var encryptedComment: String
}

public struct ApiNftTransferPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "nft:transfer"
    public var queryId: BigInt
    public var newOwner: String
    public var responseDestination: String
    public var customPayload: String?
    public var forwardAmount: BigInt
    public var forwardPayload: String?
    // Specific to UI
    public var nftAddress: String
    public var nftName: String?
    public var nft: ApiNft?
    public var comment: String?
}

public struct ApiNftOwnershipAssignedPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "nft:ownership-assigned"
    public var queryId: BigInt
    public var prevOwner: String
    // Specific to UI
    public var nftAddress: String
    public var nft: ApiNft?
    public var comment: String?
    public var bidAmount: BigInt?
    public var bidTs: Int?
}

public struct ApiTokensTransferPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "tokens:transfer"
    public var queryId: BigInt
    public var amount: BigInt
    public var destination: String
    public var responseDestination: String
    public var customPayload: String?
    public var forwardAmount: BigInt
    public var forwardPayload: String?
    public var forwardPayloadOpCode: Int?
    // Specific to UI
    public var slug: String
    public var tokenAddress: String
}

public struct ApiTokensTransferNonStandardPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "tokens:transfer-non-standard"
    public var queryId: BigInt
    public var amount: BigInt
    public var destination: String
    // Specific to UI
    public var slug: String
}

public struct ApiUnknownPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "unknown"
    public var base64: String
}

public struct ApiDedustNativeSwapPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "dedust:native-swap"
    public var queryId: BigInt
    public var amount: BigInt
    public var poolAddress: String
    public var toSlug: String
    public var toToken: ApiToken
    public var minimumAmountOut: BigInt
    public var recipientAddress: String
    public var deadline: Int

    public var minimumReceived: TokenAmount {
        TokenAmount(minimumAmountOut, toToken)
    }
}

public struct ApiTokensBurnPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "tokens:burn"
    public var queryId: BigInt
    public var amount: BigInt
    public var address: String
    public var customPayload: String?
    // Specific to UI
    public var slug: String
    public var isLiquidUnstakeRequest: Bool
}

public struct ApiLiquidStakingDepositPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "liquid-staking:deposit"
    public var queryId: BigInt
    public var appId: BigInt?
}

public struct ApiLiquidStakingWithdrawalNftPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "liquid-staking:withdrawal-nft"
    public var queryId: BigInt
}

public struct ApiLiquidStakingWithdrawalPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "liquid-staking:withdrawal"
    public var queryId: BigInt
}

public struct ApiTokenBridgePaySwap: Codable, Equatable, Hashable, Sendable {
    public var type: String = "token-bridge:pay-swap"
    public var queryId: BigInt
    public var swapId: String
}

public struct ApiDnsChangeRecord: Codable, Equatable, Hashable, Sendable {
    public struct Record: Codable, Equatable, Hashable, Sendable {
        public var type: String
        public var value: String?
        public var flags: Int?
        public var key: String?
    }
    public var type: String = "dns:change-record"
    public var queryId: BigInt
    public var record: Record
    // Specific to UI
    public var domain: String
}

public struct ApiVestingAddWhitelistPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "vesting:add-whitelist"
    public var queryId: BigInt
    public var address: String
}

public struct ApiSingleNominatorWithdrawPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "single-nominator:withdraw"
    public var queryId: BigInt
    public var amount: BigInt
}

public struct ApiSingleNominatorChangeValidatorPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "single-nominator:change-validator"
    public var queryId: BigInt
    public var address: String
}

public struct ApiLiquidStakingVotePayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "liquid-staking:vote"
    public var queryId: BigInt
    public var votingAddress: String
    public var expirationDate: Int
    public var vote: Bool
    public var needConfirmation: Bool
}

public struct ApiJettonStakePayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "jetton-staking:unstake"
    public var queryId: BigInt
    public var amount: BigInt
    public var isForce: Bool
}

public struct ApiTeleitemStartAuctionPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "teleitem:start-auction"
    public var queryId: BigInt
    public var nftAddress: String
    public var nftName: String?
    public var nft: ApiNft?
    public var beneficiaryAddress: String
    public var initialMinBid: BigInt
    public var maxBid: BigInt
    public var minBidStep: Int
    public var minExtendTime: Int
    public var duration: Int
}

public struct ApiTeleitemCancelAuctionPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "teleitem:cancel-auction"
    public var queryId: BigInt
    public var nftAddress: String
    public var nftName: String?
    public var nft: ApiNft?
}

public struct ApiTeleitemDeployPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "teleitem:deploy"
    public var tokenName: String
    public var beneficiaryAddress: String
    public var initialMinBid: BigInt
    public var maxBid: BigInt
    public var minBidStep: Int
    public var minExtendTime: Int
    public var duration: Int
}

public struct ApiTeleitemBidInfoPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "teleitem:bid-info"
    public var amount: BigInt
    public var bidTs: Int
}

public struct ApiTeleitemReturnBidPayload: Codable, Equatable, Hashable, Sendable {
    public var type: String = "teleitem:return-bid"
    public var queryId: BigInt
}
