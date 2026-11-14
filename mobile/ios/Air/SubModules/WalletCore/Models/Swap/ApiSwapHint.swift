public struct ApiSwapHint: Equatable, Hashable, Codable, Sendable {
    public var type: String
    public var token: String?
    public var providerName: String?
    public var url: String?
    public var minimumAmount: String?
    public var additionalAmount: String?
    public var symbol: String?

    private enum CodingKeys: String, CodingKey {
        case type, token, providerName, url, minimumAmount, additionalAmount, symbol
    }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        type = (try? container?.decode(String.self, forKey: .type)) ?? ""
        token = try? container?.decode(String.self, forKey: .token)
        providerName = try? container?.decode(String.self, forKey: .providerName)
        url = try? container?.decode(String.self, forKey: .url)
        minimumAmount = try? container?.decode(String.self, forKey: .minimumAmount)
        additionalAmount = try? container?.decode(String.self, forKey: .additionalAmount)
        symbol = try? container?.decode(String.self, forKey: .symbol)
    }
}
