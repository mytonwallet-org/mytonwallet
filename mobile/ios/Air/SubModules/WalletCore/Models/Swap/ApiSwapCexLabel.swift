import Foundation

public enum ApiSwapCexLabel: Equatable, Hashable, Codable, Sendable {
    case changelly
    case nearIntents
    case other(String)

    public init?(rawValue: String) {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        switch rawValue {
        case "changelly":
            self = .changelly
        case "near-intents":
            self = .nearIntents
        default:
            self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .changelly:
            "changelly"
        case .nearIntents:
            "near-intents"
        case .other(let rawValue):
            rawValue
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let cexLabel = ApiSwapCexLabel(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "ApiSwapCexLabel raw value cannot be empty")
        }
        self = cexLabel
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension Optional where Wrapped == ApiSwapCexLabel {
    var isChangellyOrLegacy: Bool {
        self == nil || self == .changelly
    }
}
