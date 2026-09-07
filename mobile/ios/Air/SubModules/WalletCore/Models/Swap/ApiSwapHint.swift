public struct ApiSwapHint: Equatable, Hashable, Codable, Sendable {
    public var type: String
    public var token: String?
    public var providerName: String?
    public var url: String?

    private enum CodingKeys: String, CodingKey {
        case type, token, providerName, url
    }

    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        type = (try? container?.decode(String.self, forKey: .type)) ?? ""
        token = try? container?.decode(String.self, forKey: .token)
        providerName = try? container?.decode(String.self, forKey: .providerName)
        url = try? container?.decode(String.self, forKey: .url)
    }
}
