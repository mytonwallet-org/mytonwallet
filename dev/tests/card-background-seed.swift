// Run from the repository root:
// swiftc mobile/ios/Air/SubModules/UIComponents/MtwCard/Rendering/CardBackgroundSeed.swift \
//   mobile/ios/Air/SubModules/UIComponents/MtwCard/Rendering/CardBackgroundLookup.swift \
//   dev/tests/card-background-seed.swift -o /tmp/card-background-seed-tests && /tmp/card-background-seed-tests
import Foundation

@main
enum CardBackgroundSeedChecks {
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        struct Catalog: Decodable { let attributes: [CardBackgroundAttribute] }
        let path = "mobile/ios/Air/SubModules/UIComponents/Resources/CardBackgrounds/CardBackgroundRecipes.json"
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let attributes = catalog.attributes
        let original = "1-11-2-1-6-5-7-3-5-5-4-2-2-4-2-5"
        let seed = try CardBackgroundSeed(cardId: original, attributes: attributes)
        // Golden row 1880 from the generator's export_with_cardId.csv.
        check(seed["Background"] == "Indigo")
        check(seed["Texture Type"] == "Uniform")
        check(seed["Texture Size"] == "1200")
        check(seed["Texture Rotation"] == "-135°")
        check(seed["Third Spot Position"] == "IV quarter")
        check(try CardBackgroundSeed.parse(seed.metadataJSON, attributes: attributes) == seed)
        check(try CardBackgroundSeed(traits: seed.traits, attributes: attributes) == seed)

        let nft: [String: Any] = ["attributes": seed.traits.map { key, value -> [String: Any] in
            ["trait_type": key, "value": key == "Texture Size" ? 1200 : value]
        }]
        let nftJSON = String(decoding: try JSONSerialization.data(withJSONObject: nft), as: UTF8.self)
        check(try CardBackgroundSeed.parse(nftJSON, attributes: attributes) == seed)
        let maxMotion = "{\"version\":1,\"cardId\":\"\(original)\",\"motionSeed\":4294967295}"
        check(try CardBackgroundSeed.parse(maxMotion, attributes: attributes).motionSeed == UInt32.max)

        var black = seed.traits
        black["Card Type"] = "🗝 Black"
        for key in Array(black.keys) { black[key] = key == "Card Type" ? "🗝 Black" : key.hasPrefix("Texture") ? "🦄 Virgin" : "⭐️ Premium" }
        let blackSeed = try CardBackgroundSeed(traits: black, attributes: attributes)
        check(blackSeed.cardId == "5-13-6-3-1-1-1-7-1-1-8-6-5-6-4-6")

        // Published NFT metadata fixtures; the number is one above the on-chain index.
        let remoteData = try Data(contentsOf: URL(fileURLWithPath: "dev/tests/fixtures/card-background-1881.json"))
        let remote = try CardBackgroundRemoteCard.decode(remoteData, number: 1881, attributes: attributes)
        check(remote.seed == seed)
        check(remote.metadataURL.lastPathComponent == "cards-item-0758.json")
        check(remote.referenceURL.lastPathComponent == "1881.webp")
        let blackData = try Data(contentsOf: URL(fileURLWithPath: "dev/tests/fixtures/card-background-1.json"))
        let remoteBlack = try CardBackgroundRemoteCard.decode(blackData, number: 1, attributes: attributes)
        check(remoteBlack.seed == blackSeed)
        check(remoteBlack.metadataURL.lastPathComponent == "cards-item-0000.json")
        check(CardBackgroundRemoteCard.metadataURL(number: 65537).lastPathComponent == "cards-item-10000.json")
        for input in ["1881", "#1881", "  #001881\n"] {
            check(try CardBackgroundRemoteCard.cardNumber(input) == 1881)
        }
        for input in ["", "#", "0", "-1", "1.5", "1/2", "１２", "1e3", "9999999999999999999999999"] {
            do {
                _ = try CardBackgroundRemoteCard.cardNumber(input)
                fatalError("Accepted invalid card number: \(input)")
            } catch { }
        }
        do {
            _ = try CardBackgroundRemoteCard.decode(remoteData, number: 1880, attributes: attributes)
            fatalError("Accepted another card’s metadata")
        } catch { }
        let malformedMetadata = ["{}", "{\"id\":true}", "{\"id\":1881}", "{\"id\":1881,\"attributes\":[]}"]
        for input in malformedMetadata {
            do {
                _ = try CardBackgroundRemoteCard.decode(Data(input.utf8), number: 1881, attributes: attributes)
                fatalError("Accepted incomplete NFT metadata")
            } catch { }
        }

        let invalid = [
            "", "1-2-3", original + "-1", original.replacingOccurrences(of: "1-11", with: "0-11"),
            original.replacingOccurrences(of: "1-11", with: "6-11"), "-" + original,
            original.replacingOccurrences(of: "1-11", with: "1.0-11"),
            "{\"cardId\":\"\(original)\",\"version\":2}",
            "{\"cardId\":\"\(original)\",\"version\":true}",
            "{\"mtwCardRecipe\":\"invalid\"}",
            "{\"cardId\":\"\(original)\",\"motionSeed\":-1}",
            "{\"cardId\":\"\(original)\",\"motionSeed\":4294967296}",
            "{\"cardId\":\"\(original)\",\"motionSeed\":true}",
            "{\"cardId\":\"\(original)\",\"motionSeed\":1.5}",
            "{\"attributes\":[]}", "{\"cardId\":12}", "{",
        ]
        for input in invalid {
            do {
                _ = try CardBackgroundSeed.parse(input, attributes: attributes)
                fatalError("Accepted invalid seed: \(input)")
            } catch { }
        }
        print("Passed golden trait mapping, published Standard/Black NFT fixtures, card-number validation and index mapping, mismatched metadata rejection, numeric NFT traits, recipe round trips, UInt32 limits, Black/Virgin ordering, and \(invalid.count) invalid seeds.")
    }
}
