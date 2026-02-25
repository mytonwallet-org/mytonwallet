
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
    func getToken(chain: ApiChain) -> ApiToken {
        var slug: String?
        switch payload {
        case .tokensTransfer(let p): slug = p.slug
        case .tokensTransferNonStandard(let p): slug = p.slug
        case .tokensBurn(let p): slug = p.slug
        default:
            break
        }
        
        // For missed slug (for example, TON transfers go as .comment() with no slug records at all,
        // let's use native network tokens
        if slug == nil {
            return TokenStore.getNativeToken(chain: chain)
        }
        
        // Get token for slug or fallback to one-time fake one
        guard let slug, let token = TokenStore.getToken(slug: slug) else {
            var fallbackToken = chain.nativeToken
            fallbackToken.symbol = "[Unknown]"
            return fallbackToken
        }
        return token
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
}
