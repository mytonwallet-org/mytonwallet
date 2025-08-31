import Foundation
import WalletContext

// MARK: This code has been generated based on TypeScript definitions. Do not edit manually.

public typealias Cell = AnyEncodable

public enum AnyPayload {
    case string(String)
    case cell(Cell) // from external import
    case uint8Array([UInt8])
}

public enum ApiParsedPayload: Equatable, Hashable, Codable, Sendable {
    case comment(MCommentPayload)
    case encryptedComment(MEncryptedCommentPayload)
    case nftTransfer(MNftTransferPayload)
    case nftOwnershipAssigned(MNftOwnershipAssignedPayload)
    case tokensTransfer(MTokensTransferPayload)
    case tokensTransferNonStandard(MTokensTransferNonStandardPayload)
    case unknown(MUnknownPayload)
    case tokensBurn(MTokensBurnPayload)
    case liquidStakingDeposit(MLiquidStakingDepositPayload)
    case liquidStakingWithdrawal(MLiquidStakingWithdrawalPayload)
    case liquidStakingWithdrawalNft(MLiquidStakingWithdrawalNftPayload)
    case tokenBridgePaySwap(MTokenBridgePaySwap)
    case dnsChangeRecord(MDnsChangeRecord)
    case vestingAddWhitelist(MVestingAddWhitelistPayload)
    case singleNominatorWithdraw(MSingleNominatorWithdrawPayload)
    case singleNominatorChangeValidator(MSingleNominatorChangeValidatorPayload)
    case liquidStakingVote(MLiquidStakingVotePayload)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "comment":
            let payload = try MCommentPayload(from: decoder)
            self = .comment(payload)
        case "encrypted-comment":
            let payload = try MEncryptedCommentPayload(from: decoder)
            self = .encryptedComment(payload)
        case "liquid-staking:deposit":
            let payload = try MLiquidStakingDepositPayload(from: decoder)
            self = .liquidStakingDeposit(payload)
        case "liquid-staking:vote":
            let payload = try MLiquidStakingVotePayload(from: decoder)
            self = .liquidStakingVote(payload)
        case "liquid-staking:withdrawal-nft":
            let payload = try MLiquidStakingWithdrawalNftPayload(from: decoder)
            self = .liquidStakingWithdrawalNft(payload)
        case "liquid-staking:withdrawal":
            let payload = try MLiquidStakingWithdrawalPayload(from: decoder)
            self = .liquidStakingWithdrawal(payload)
        case "single-nominator:change-validator":
            let payload = try MSingleNominatorChangeValidatorPayload(from: decoder)
            self = .singleNominatorChangeValidator(payload)
        case "single-nominator:withdraw":
            let payload = try MSingleNominatorWithdrawPayload(from: decoder)
            self = .singleNominatorWithdraw(payload)
        case "vesting:add-whitelist":
            let payload = try MVestingAddWhitelistPayload(from: decoder)
            self = .vestingAddWhitelist(payload)
        case "tokens:burn":
            let payload = try MTokensBurnPayload(from: decoder)
            self = .tokensBurn(payload)
        case "tokens:transfer-non-standard":
            let payload = try MTokensTransferNonStandardPayload(from: decoder)
            self = .tokensTransferNonStandard(payload)
        case "tokens:transfer":
            let payload = try MTokensTransferPayload(from: decoder)
            self = .tokensTransfer(payload)
        case "unknown":
            let payload = try MUnknownPayload(from: decoder)
            self = .unknown(payload)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown type: \(type)")
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)        
        switch self {
        case .comment(let payload):
            try container.encode("comment", forKey: .type)
            try payload.encode(to: encoder)
        case .encryptedComment(let payload):
            try container.encode("encrypted-comment", forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingDeposit(let payload):
            try container.encode("liquid-staking:deposit", forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingVote(let payload):
            try container.encode("liquid-staking:vote", forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingWithdrawalNft(let payload):
            try container.encode("liquid-staking:withdrawal-nft", forKey: .type)
            try payload.encode(to: encoder)
        case .liquidStakingWithdrawal(let payload):
            try container.encode("liquid-staking:withdrawal", forKey: .type)
            try payload.encode(to: encoder)
        case .singleNominatorChangeValidator(let payload):
            try container.encode("single-nominator:change-validator", forKey: .type)
            try payload.encode(to: encoder)
        case .singleNominatorWithdraw(let payload):
            try container.encode("single-nominator:withdraw", forKey: .type)
            try payload.encode(to: encoder)
        case .vestingAddWhitelist(let payload):
            try container.encode("vesting:add-whitelist", forKey: .type)
            try payload.encode(to: encoder)
        case .tokensBurn(let payload):
            try container.encode("tokens:burn", forKey: .type)
            try payload.encode(to: encoder)
        case .tokensTransferNonStandard(let payload):
            try container.encode("tokens:transfer-non-standard", forKey: .type)
            try payload.encode(to: encoder)
        case .tokensTransfer(let payload):
            try container.encode("tokens:transfer", forKey: .type)
            try payload.encode(to: encoder)
        case .unknown(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .nftTransfer(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .nftOwnershipAssigned(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .tokenBridgePaySwap(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        case .dnsChangeRecord(let payload):
            try container.encode(payload.type, forKey: .type)
            try payload.encode(to: encoder)
        }
    }
}

public struct MCommentPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "comment"
    public var comment: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.comment = try container.decode(String.self, forKey: .comment)
    }
}

public struct MEncryptedCommentPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "encrypted-comment"
    public var encryptedComment: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.encryptedComment = try container.decode(String.self, forKey: .encryptedComment)
    }
}

public struct MNftOwnershipAssignedPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "nft:ownership-assigned"
    public var queryId: BigInt
    public var prevOwner: String
    public var nftAddress: String
    public var nft: ApiNft?
    public var comment: String?
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.prevOwner = try container.decode(String.self, forKey: .prevOwner)
        self.nftAddress = try container.decode(String.self, forKey: .nftAddress)
        self.nft = try container.decodeIfPresent(ApiNft.self, forKey: .nft)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }
}

public struct MNftTransferPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "nft:transfer"
    public var queryId: BigInt
    public var newOwner: String
    public var responseDestination: String
    public var customPayload: String?
    public var forwardAmount: BigInt
    public var forwardPayload: String?
    public var nftAddress: String
    public var nftName: String?
    public var nft: ApiNft?
    public var comment: String?
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.newOwner = try container.decode(String.self, forKey: .newOwner)
        self.responseDestination = try container.decode(String.self, forKey: .responseDestination)
        self.customPayload = try container.decodeIfPresent(String.self, forKey: .customPayload)
        self.forwardAmount = try container.decode(BigInt.self, forKey: .forwardAmount)
        self.forwardPayload = try container.decodeIfPresent(String.self, forKey: .forwardPayload)
        self.nftAddress = try container.decode(String.self, forKey: .nftAddress)
        self.nftName = try container.decodeIfPresent(String.self, forKey: .nftName)
        self.nft = try container.decodeIfPresent(ApiNft.self, forKey: .nft)
        self.comment = try container.decodeIfPresent(String.self, forKey: .comment)
    }
}

public struct MLiquidStakingDepositPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "liquid-staking:deposit"
    public var queryId: BigInt
    public var appId: BigInt?
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.appId = try container.decodeIfPresent(BigInt.self, forKey: .appId)
    }
}

public struct MLiquidStakingVotePayload: Equatable, Hashable, Codable, Sendable {
    public let type = "liquid-staking:vote"
    public var queryId: BigInt
    public var votingAddress: String
    public var expirationDate: Int
    public var vote: Bool
    public var needConfirmation: Bool
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.votingAddress = try container.decode(String.self, forKey: .votingAddress)
        self.expirationDate = try container.decode(Int.self, forKey: .expirationDate)
        self.vote = try container.decode(Bool.self, forKey: .vote)
        self.needConfirmation = try container.decode(Bool.self, forKey: .needConfirmation)
    }
}

public struct MLiquidStakingWithdrawalNftPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "liquid-staking:withdrawal-nft"
    public var queryId: BigInt
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
    }
}

public enum MDNSCategoryHashMapKeys: String, Equatable, Hashable, Codable, Sendable  {
    case dnsNextResolver = "dns_next_resolver"
    case wallet = "wallet"
    case site = "site"
    case storage = "storage"
}

public enum MDnsChangeRecordRecord: Equatable, Hashable, Codable, Sendable  {
    case known(type: MDNSCategoryHashMapKeys, value: String?, flags: Int?)
    case unknown(key: String, value: String?)
}

public struct MDnsChangeRecord: Equatable, Hashable, Codable, Sendable  {
    let type = "dns:change-record"
    var queryId: BigInt
    var record: MDnsChangeRecordRecord
    var domain: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.record = try container.decode(MDnsChangeRecordRecord.self, forKey: .record)
        self.domain = try container.decode(String.self, forKey: .domain)
    }
}

public struct MTokenBridgePaySwap: Equatable, Hashable, Codable, Sendable {
    public let type = "token-bridge:pay-swap"
    public var queryId: BigInt
    public var swapId: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.swapId = try container.decode(String.self, forKey: .swapId)
    }
}

public struct MLiquidStakingWithdrawalPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "liquid-staking:withdrawal"
    public var queryId: BigInt
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
    }
}

public struct MSingleNominatorChangeValidatorPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "single-nominator:change-validator"
    public var queryId: BigInt
    public var address: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.address = try container.decode(String.self, forKey: .address)
    }
}

public struct MSingleNominatorWithdrawPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "single-nominator:withdraw"
    public var queryId: BigInt
    public var amount: BigInt
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.amount = try container.decode(BigInt.self, forKey: .amount)
    }
}

public struct MVestingAddWhitelistPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "vesting:add-whitelist"
    public var queryId: BigInt
    public var address: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.address = try container.decode(String.self, forKey: .address)
    }
}

public struct MTokensBurnPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "tokens:burn"
    public var queryId: BigInt
    public var amount: BigInt
    public var address: String
    public var customPayload: String?
    public var slug: String
    public var isLiquidUnstakeRequest: Bool
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.amount = try container.decode(BigInt.self, forKey: .amount)
        self.address = try container.decode(String.self, forKey: .address)
        self.customPayload = try container.decodeIfPresent(String.self, forKey: .customPayload)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.isLiquidUnstakeRequest = try container.decode(Bool.self, forKey: .isLiquidUnstakeRequest)
    }
}

public struct MTokensTransferNonStandardPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "tokens:transfer-non-standard"
    public var queryId: BigInt
    public var amount: BigInt
    public var destination: String
    public var slug: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.amount = try container.decode(BigInt.self, forKey: .amount)
        self.destination = try container.decode(String.self, forKey: .destination)
        self.slug = try container.decode(String.self, forKey: .slug)
    }
}

public struct MTokensTransferPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "tokens:transfer"
    public var queryId: BigInt
    public var amount: BigInt
    public var destination: String
    public var responseDestination: String
    public var customPayload: String?
    public var forwardAmount: BigInt
    public var forwardPayload: String?
    public var slug: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.queryId = try container.decode(BigInt.self, forKey: .queryId)
        self.amount = try container.decode(BigInt.self, forKey: .amount)
        self.destination = try container.decode(String.self, forKey: .destination)
        self.responseDestination = try container.decode(String.self, forKey: .responseDestination)
        self.customPayload = try container.decodeIfPresent(String.self, forKey: .customPayload)
        self.forwardAmount = try container.decode(BigInt.self, forKey: .forwardAmount)
        self.forwardPayload = try container.decodeIfPresent(String.self, forKey: .forwardPayload)
        self.slug = try container.decode(String.self, forKey: .slug)
    }
}

public struct MUnknownPayload: Equatable, Hashable, Codable, Sendable {
    public let type = "unknown"
    public var base64: String
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.base64 = try container.decode(String.self, forKey: .base64)
    }
}
