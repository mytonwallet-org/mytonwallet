public enum AirSendTokenRecipientKind: String, Sendable, Codable, Hashable {
    case account
    case savedAddress
    case rawAddressOrDomain
}

public struct AirSendTokenRecipient: Sendable, Codable, Hashable {
    public var kind: AirSendTokenRecipientKind
    public var addressOrDomain: String?
    public var chain: String?
    public var accountId: String?

    public init(kind: AirSendTokenRecipientKind, addressOrDomain: String?, chain: String?, accountId: String?) {
        self.kind = kind
        self.addressOrDomain = addressOrDomain
        self.chain = chain
        self.accountId = accountId
    }
}

public enum AirSystemAction: Sendable {
    case scanQR
    case openReceive(accountId: String?, chain: String?)
    case openToken(accountId: String?, tokenSlug: String)
    case sendToken(accountId: String?, recipient: AirSendTokenRecipient?, tokenSlug: String?, amount: Double?, comment: String?)
}
