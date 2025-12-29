//
//  SignDataPayload.swift
//  MyTonWalletAir
//
//  Created by nikstar on 29.09.2025.
//

import WalletContext

public enum SignDataPayload: Equatable, Hashable, Codable, Sendable {
    case text(SignDataPayloadText)
    case binary(SignDataPayloadBinary)
    case cell(SignDataPayloadCell)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = try .text(SignDataPayloadText(from: decoder))
        case "binary":
            self = try .binary(SignDataPayloadBinary(from: decoder))
        case "cell":
            self = try .cell(SignDataPayloadCell(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            try text.encode(to: encoder)
        case .binary(let binary):
            try binary.encode(to: encoder)
        case .cell(let cell):
            try cell.encode(to: encoder)
        }
    }
}

public struct SignDataPayloadText: Equatable, Hashable, Codable, Sendable {
    public var type: String = "text"
    public var text: String
}

public struct SignDataPayloadBinary: Equatable, Hashable, Codable, Sendable {
    public var type: String = "binary"
    public var bytes: String
}

public struct SignDataPayloadCell: Equatable, Hashable, Codable, Sendable {
    public var type: String = "cell"
    public var schema: String
    public var cell: String
}

