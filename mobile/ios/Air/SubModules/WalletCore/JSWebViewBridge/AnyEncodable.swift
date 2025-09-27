//
//  AnyEncodable.swift
//  WalletCore
//
//  Created by Sina on 8/30/24.
//

import Foundation

// to easily encode/pass both objects and arrays :)
public struct AnyEncodable: Codable {
    private let _encode: (Encoder) throws -> Void

    public init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode(to:)
    }

    public func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }

    public init(arr: [Any]) {
        var encodableItems = [AnyEncodable]()
        for it in arr {
            if let it = it as? [String: Any] {
                encodableItems.append(AnyEncodable(dict: it))
            } else if let it = it as? [Any] {
                encodableItems.append(AnyEncodable(arr: it))
            }
        }
        self.init(encodableItems)
    }
    public init(dict: [String: Any]) {
        self.init(dict.mapValues { value in
            if let encodableValue = value as? Encodable {
                return AnyEncodable(encodableValue)
            } else if let encodableDict = value as? [String: Any] {
                return AnyEncodable(dict: encodableDict)
            } else if let arr = value as? [Any] {
                return AnyEncodable(arr: arr)
            } else if let boolValue = value as? Bool {
                return AnyEncodable(boolValue)
            } else if let intValue = value as? Int {
                return AnyEncodable(intValue)
            } else if let doubleValue = value as? Double {
                return AnyEncodable(doubleValue)
            } else if let stringValue = value as? String {
                return AnyEncodable(stringValue)
            } else {
                fatalError("Unsupported value type")
            }
        })
    }

    public init(from decoder: any Decoder) throws {
        print("decoder: \(decoder)")
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyEncodable].self) {
            self = AnyEncodable(dict: dict)
        } else if let arr = try? container.decode([AnyEncodable].self) {
            self = AnyEncodable(arr: arr)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = AnyEncodable(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = AnyEncodable(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = AnyEncodable(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = AnyEncodable(stringValue)
        } else {
            print("failed to parse any known type")
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "failed to parse any known type")
        }
        print("self: \(self)")
    }
}

public func asAnyEncodables<each T: Encodable>(_ values: repeat each T) -> [AnyEncodable] {
    var result: [AnyEncodable] = []
    for value in repeat each values {
        result.append(AnyEncodable(value))
    }
    return result
}
