import Foundation
import CoreFoundation

/// Public My Wallet collection metadata uses the zero-based NFT index in hexadecimal.
/// The number printed on the card and the wallet background filenames are one-based.
public struct CardBackgroundRemoteCard {
    public let number: Int
    public let name: String
    public let seed: CardBackgroundSeed
    public let metadataURL: URL
    public let referenceURL: URL
    public let nftPreviewURL: URL?

    public static func cardNumber(_ input: String) throws -> Int {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = Int(value), number > 0 else {
            throw CardBackgroundSeed.InvalidSeed(message: "Enter a positive card number, such as 1881 or #1881.")
        }
        return number
    }

    public static func metadataURL(number: Int) -> URL {
        precondition(number > 0)
        let index = String(number - 1, radix: 16)
        let paddedIndex = String(repeating: "0", count: max(0, 4 - index.count)) + index
        return URL(string: "https://api.tonnames.org/nft/cards-item-\(paddedIndex).json")!
    }

    public static func fetch(number: Int, attributes: [CardBackgroundAttribute], session: URLSession = .shared) async throws -> Self {
        let url = metadataURL(number: number)
        let data = try await fetchData(from: url, session: session)
        return try decode(data, number: number, attributes: attributes)
    }

    public static func decode(_ data: Data, number: Int, attributes: [CardBackgroundAttribute]) throws -> Self {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(),
              id.stringValue == String(number) else {
            throw CardBackgroundSeed.InvalidSeed(message: "The metadata does not identify card #\(number).")
        }
        let seed = try CardBackgroundSeed.parse(String(decoding: data, as: UTF8.self), attributes: attributes)
        let preview = (json["image"] as? String).flatMap(URL.init(string:))
        return Self(
            number: number,
            name: json["name"] as? String ?? "My Wallet Card #\(number)",
            seed: seed,
            metadataURL: metadataURL(number: number),
            // Same background asset as ApiNftMetadata.mtwCardBackgroundUrl and getCardNftImageUrl.
            referenceURL: URL(string: "https://static.mytonwallet.org/cards/v2/cards/\(number).webp")!,
            nftPreviewURL: preview?.scheme == "https" ? preview : nil
        )
    }

    public static func fetchData(from url: URL, session: URLSession = .shared) async throws -> Data {
        let (data, response) = try await session.data(for: URLRequest(url: url, timeoutInterval: 30))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let message = response.statusCode == 404
                ? "This card or its published image could not be found. Check the number and try again."
                : "The card server returned HTTP \(response.statusCode). Try again."
            throw CardBackgroundSeed.InvalidSeed(message: message)
        }
        return data
    }
}
