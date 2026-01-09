
import Foundation

public enum AnyTransferPayload: Equatable, Hashable, Sendable {
    case comment(text: String, shouldEncrypt: Bool?)
    case binary(data: [UInt8])
    case base64(data: String)
}

public extension AnyTransferPayload {
    var comment: String? {
        switch self {
        case .comment(let text, let shouldEncrypt):
            shouldEncrypt == true ? nil : text
        default:
            nil
        }
    }
}

extension AnyTransferPayload: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "comment":
            self = try .comment(
                text: container.decode(String.self, forKey: .text), 
                shouldEncrypt: container.decodeIfPresent(Bool.self, forKey: .shouldEncrypt)
            )
        case "binary":
            self = try .binary(
                data: container.decode([UInt8].self, forKey: .data)
            )
        case "base64":
            self = try .base64(
                data: container.decode(String.self, forKey: .data)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .comment(let text, let shouldEncrypt):
            try container.encode("comment", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(shouldEncrypt, forKey: .shouldEncrypt)
        case .binary(let data):
            try container.encode("binary", forKey: .type)
            try container.encode(data, forKey: .data)
        case .base64(let data):
            try container.encode("base64", forKey: .type)
            try container.encode(data, forKey: .data)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case shouldEncrypt
        case data
    }
}
