import Foundation
import WalletContext
import WalletCoreTypes

public struct ApiTonPlugin: Equatable, Hashable, Sendable, Decodable {
    public let address: String
    public let name: String?
    public let balance: BigInt
    public let isInitialized: Bool

    private enum CodingKeys: String, CodingKey {
        case address
        case name
        case balance
        case isInitialized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decode(String.self, forKey: .address)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        balance = try container.decodeBigIntIfPresent(forKey: .balance) ?? 0
        isInitialized = try container.decode(Bool.self, forKey: .isInitialized)
    }
}

public enum ApiWalletPermission: Equatable, Hashable, Sendable, Decodable {
    case approval(ApiTokenApproval)
    case delegation(ApiEvmDelegation)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case ApiTokenApproval.kind:
            self = .approval(try ApiTokenApproval(from: decoder))
        case ApiEvmDelegation.kind:
            self = .delegation(try ApiEvmDelegation(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported wallet permission kind"
            )
        }
    }

    public var chain: ApiChain {
        switch self {
        case .approval(let approval):
            approval.chain
        case .delegation(let delegation):
            delegation.chain
        }
    }

    public var title: String {
        switch self {
        case .approval(let approval):
            approval.tokenName
        case .delegation(let delegation):
            delegation.delegateLabel
        }
    }

    public func hasSameRevokeTarget(as other: ApiWalletPermission) -> Bool {
        switch (self, other) {
        case (.approval(let lhs), .approval(let rhs)):
            lhs.tokenSlug == rhs.tokenSlug && lhs.spenderAddress == rhs.spenderAddress
        case (.delegation(let lhs), .delegation(let rhs)):
            lhs.delegateAddress == rhs.delegateAddress
        default:
            false
        }
    }
}

public struct ApiTokenApproval: Equatable, Hashable, Sendable, Decodable {
    public static let kind = "approval"

    public let chain: ApiChain
    public let tokenAddress: String
    public let tokenSlug: String
    public let tokenName: String
    public let tokenSymbol: String
    public let tokenDecimals: Int
    public let tokenImage: String?
    public let spenderAddress: String
    public let spenderName: String?
    public let spenderIcon: String?
    public let allowance: String
    public let isUnlimited: Bool

    public var allowanceValue: BigInt {
        BigInt(allowance.removingBigIntPrefix()) ?? 0
    }

    public var spenderLabel: String {
        spenderName?.nilIfEmpty ?? formatStartEndAddress(spenderAddress)
    }

    public var token: ApiToken {
        TokenStore.getToken(slug: tokenSlug) ?? ApiToken(
            slug: tokenSlug,
            name: tokenName,
            symbol: tokenSymbol,
            decimals: tokenDecimals,
            chain: chain,
            tokenAddress: tokenAddress,
            image: tokenImage
        )
    }
}

public struct ApiEvmDelegation: Equatable, Hashable, Sendable, Decodable {
    public static let kind = "delegation"

    public let chain: ApiChain
    public let delegateAddress: String
    public let delegateName: String?
    public let delegateIcon: String?

    public var delegateLabel: String {
        delegateName?.nilIfEmpty ?? formatStartEndAddress(delegateAddress)
    }
}

public struct ApiRevokeWalletPermissionOptions: Encodable, Sendable {
    public let accountId: String
    public let password: String?
    public let kind: String
    public let tokenAddress: String?
    public let spenderAddress: String?
    public let delegateAddress: String?

    public init(accountId: String, password: String?, permission: ApiWalletPermission) {
        self.accountId = accountId
        self.password = password

        switch permission {
        case .approval(let approval):
            self.kind = ApiTokenApproval.kind
            self.tokenAddress = approval.tokenAddress
            self.spenderAddress = approval.spenderAddress
            self.delegateAddress = nil
        case .delegation(let delegation):
            self.kind = ApiEvmDelegation.kind
            self.tokenAddress = nil
            self.spenderAddress = nil
            self.delegateAddress = delegation.delegateAddress
        }
    }
}

public struct ApiRevokeWalletPermissionResult: Decodable, Sendable {
    public let txId: String?
    public let error: ApiAnyDisplayError?
}

private extension KeyedDecodingContainer {
    func decodeBigIntIfPresent(forKey key: Key) throws -> BigInt? {
        if let string = try decodeIfPresent(String.self, forKey: key) {
            return BigInt(string.removingBigIntPrefix())
        }
        if let int = try decodeIfPresent(Int.self, forKey: key) {
            return BigInt(int)
        }
        return nil
    }
}

private extension String {
    func removingBigIntPrefix() -> String {
        hasPrefix("bigint:") ? String(dropFirst("bigint:".count)) : self
    }
}
