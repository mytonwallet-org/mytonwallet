
import Foundation
import WalletContext

public struct ApiDappTransfer: ApiTransferToSignProtocol, Equatable, Hashable, Decodable, Sendable {
    
    public var toAddress: String
    public var amount: BigInt
    public var rawPayload: String?
    public var payload: ApiParsedPayload?
    public var stateInit: String?

    public var isScam: Bool?
    /** Whether the transfer should be treated with cautiousness, because its payload is unclear */
    public var isDangerous: Bool
    public var normalizedAddress: String
    /** The transfer address to show in the UI */
    public var displayedToAddress: String
    public var networkFee: BigInt
    
    public init(toAddress: String, amount: BigInt, rawPayload: String? = nil, payload: ApiParsedPayload? = nil, stateInit: String? = nil, isScam: Bool? = nil, isDangerous: Bool, normalizedAddress: String, displayedToAddress: String, networkFee: BigInt) {
        self.toAddress = toAddress
        self.amount = amount
        self.rawPayload = rawPayload
        self.payload = payload
        self.stateInit = stateInit
        self.isScam = isScam
        self.isDangerous = isDangerous
        self.normalizedAddress = normalizedAddress
        self.displayedToAddress = displayedToAddress
        self.networkFee = networkFee
    }
}

public extension ApiDappTransfer {            
    var isNftTransferPayload: Bool {
        if case .nftTransfer = payload {
            return true
        }

        return false
    }

    var nftTransferPayload: ApiNftTransferPayload? {
        if case .nftTransfer(let payload) = self.payload {
            return payload
        }

        return nil
    }

    var transferPayloadToken: ApiToken? {
        guard let slug = transferPayloadTokenSlug else { return nil }
        return TokenStore.getToken(slug: slug)
    }

    func displayedAmounts(chain: ApiChain, includeNativeFee: Bool) -> [TokenAmount] {
        var amounts: [TokenAmount] = []

        switch payload {
        case .tokensTransfer(let p):
            amounts.append(TokenAmount(p.amount, tokenForPayload(slug: p.slug, chain: chain)))
        case .tokensTransferNonStandard(let p):
            amounts.append(TokenAmount(p.amount, tokenForPayload(slug: p.slug, chain: chain)))
        default:
            break
        }

        let nativeAmount = amount + (includeNativeFee ? networkFee : 0)
        if nativeAmount != 0 || (!isNftTransferPayload && amounts.isEmpty) {
            amounts.append(TokenAmount(nativeAmount, TokenStore.getNativeToken(chain: chain)))
        }

        return amounts
    }

    func getToken(chain: ApiChain) -> ApiToken {
        let slug = payloadTokenSlug
        
        // For missed slug (for example, TON transfers go as .comment() with no slug records at all,
        // let's use native network tokens
        if slug == nil {
            return TokenStore.getNativeToken(chain: chain)
        }
        
        // Get token for slug or fallback to one-time fake one
        guard let slug else { return TokenStore.getNativeToken(chain: chain) }
        return tokenForPayload(slug: slug, chain: chain)
    }
    
    var effectiveAmount: BigInt {
        var result = amount
        switch payload {
        case .tokensTransfer(let p): result = p.amount
        case .tokensTransferNonStandard(let p): result = p.amount
        case .tokensBurn(let p): result = p.amount
        default:
            break
        }
        return result
    }

    private var transferPayloadTokenSlug: String? {
        switch payload {
        case .tokensTransfer(let p): p.slug
        case .tokensTransferNonStandard(let p): p.slug
        default: nil
        }
    }

    private var payloadTokenSlug: String? {
        switch payload {
        case .tokensTransfer(let p): p.slug
        case .tokensTransferNonStandard(let p): p.slug
        case .tokensBurn(let p): p.slug
        default: nil
        }
    }

    private func tokenForPayload(slug: String, chain: ApiChain) -> ApiToken {
        if let token = TokenStore.getToken(slug: slug) {
            return token
        }

        return .init(
            slug: slug,
            name: "[Unknown]",
            symbol: "[Unknown]",
            decimals: 9,
            chain: chain
        )
    }
}
