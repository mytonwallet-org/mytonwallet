import Foundation
import CoreFoundation

public struct CardBackgroundAttribute: Decodable, Sendable {
    public let name: String
    public let options: [String]
}

/// The generator's 16 one-based trait indexes are the visual seed, not a PRNG seed.
public struct CardBackgroundSeed: Equatable, Sendable {
    public let cardId: String
    public let traits: [String: String]
    public let motionSeed: UInt32

    public subscript(_ name: String) -> String { traits[name] ?? "" }
    public var isStandard: Bool { self["Card Type"] == "🍀 Standard" }
    public var hasTexture: Bool { self["Texture Type"] != "🦄 Virgin" }

    struct Recipe: Codable {
        var version: Int = 1
        public let cardId: String
        public let motionSeed: UInt32
    }

    struct InvalidSeed: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    public init(cardId: String, attributes: [CardBackgroundAttribute], motionSeed: UInt32? = nil) throws {
        let parts = cardId.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == attributes.count else {
            throw InvalidSeed(message: "A card ID must contain all \(attributes.count) trait indexes, separated by hyphens.")
        }
        var traits: [String: String] = [:]
        var indexes: [Int] = []
        for (part, attribute) in zip(parts, attributes) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let index = Int(part), attribute.options.indices.contains(index - 1) else {
                throw InvalidSeed(message: "Invalid index for \(attribute.name). Expected 1–\(attribute.options.count).")
            }
            traits[attribute.name] = attribute.options[index - 1]
            indexes.append(index)
        }
        let canonical = indexes.map(String.init).joined(separator: "-")
        self.cardId = canonical
        self.traits = traits
        self.motionSeed = motionSeed ?? canonical.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        try validate()
    }

    public init(traits: [String: String], attributes: [CardBackgroundAttribute], motionSeed: UInt32? = nil) throws {
        let indexes = try attributes.map { attribute in
            guard let value = traits[attribute.name], let index = attribute.options.firstIndex(of: value) else {
                throw InvalidSeed(message: "Missing or unknown value for \(attribute.name).")
            }
            return String(index + 1)
        }
        try self.init(cardId: indexes.joined(separator: "-"), attributes: attributes, motionSeed: motionSeed)
    }

    public static func parse(_ input: String, attributes: [CardBackgroundAttribute]) throws -> Self {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.hasPrefix("{") else { return try Self(cardId: input, attributes: attributes) }
        guard let data = input.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvalidSeed(message: "Expected a card ID, recipe JSON, or NFT metadata with attributes.")
        }
        // Proposed metadata envelope; existing NFTs can instead supply their original attributes.
        if json["mtwCardRecipe"] != nil && !(json["mtwCardRecipe"] is [String: Any]) {
            throw InvalidSeed(message: "mtwCardRecipe must be a JSON object.")
        }
        let recipe = json["mtwCardRecipe"] as? [String: Any] ?? json
        if recipe["cardId"] != nil {
            if let version = recipe["version"] {
                guard let number = version as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.stringValue == "1" else {
                    throw InvalidSeed(message: "Unsupported recipe version. This Lab supports version 1.")
                }
            }
            guard let cardId = recipe["cardId"] as? String else {
                throw InvalidSeed(message: "cardId must be a string.")
            }
            var motionSeed: UInt32?
            if let value = recipe["motionSeed"] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      let parsed = UInt32(number.stringValue) else {
                    throw InvalidSeed(message: "motionSeed must be an unsigned 32-bit integer.")
                }
                motionSeed = parsed
            }
            return try Self(cardId: cardId, attributes: attributes, motionSeed: motionSeed)
        }
        guard let nftAttributes = json["attributes"] as? [[String: Any]] else {
            throw InvalidSeed(message: "Metadata needs cardId or the generator’s 16 NFT attributes.")
        }
        let names = Set(attributes.map(\.name))
        var traits: [String: String] = [:]
        for attribute in nftAttributes {
            guard let name = attribute["trait_type"] as? String, names.contains(name) else { continue }
            guard traits[name] == nil else { throw InvalidSeed(message: "Duplicate attribute: \(name).") }
            if let value = attribute["value"] as? String {
                traits[name] = value
            } else if let number = attribute["value"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                traits[name] = number.stringValue
            }
        }
        return try Self(traits: traits, attributes: attributes)
    }

    public var metadataJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try! encoder.encode(["mtwCardRecipe": Recipe(cardId: cardId, motionSeed: motionSeed)])
        return String(decoding: data, as: UTF8.self)
    }

    private func validate() throws {
        if isStandard, ["Background", "Text", "Shine"].contains(where: { self[$0] == "⭐️ Premium" }) {
            throw InvalidSeed(message: "Standard cards require a standard background, text, and shine.")
        }
        if hasTexture {
            guard ["Texture Size", "Texture Rotation", "Texture Position X", "Texture Position Y"].allSatisfy({ self[$0] != "🦄 Virgin" }),
                  self["Texture Color"] != "🦄 Virgin",
                  !isStandard || self["Texture Color"] != "⭐️ Premium" else {
                throw InvalidSeed(message: "A texture requires a color, size, rotation, and position.")
            }
        }
        if isStandard {
            for ordinal in ["First", "Second", "Third"] {
                let color = self["\(ordinal) Spot Color"]
                let position = self["\(ordinal) Spot Position"]
                guard color != "⭐️ Premium", color == "No" || (position != "No" && position != "⭐️ Premium") else {
                    throw InvalidSeed(message: "\(ordinal) Spot needs a standard color and a quadrant, or No color.")
                }
            }
        }
    }
}
