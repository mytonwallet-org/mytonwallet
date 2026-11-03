import AppIntents
import Foundation
import ImageIO
import UIKit
import WalletContext

@available(iOS 18.4, *)
enum TokenEntityImage {
    // URLCache respects server freshness and avoids downloading logos for every result.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 4_000_000, diskCapacity: 20_000_000, diskPath: "token-entity-icons")
        configuration.timeoutIntervalForRequest = 5
        return URLSession(configuration: configuration)
    }()

    static func load(_ imageURL: String?, tokenSlug: String) async -> DisplayRepresentation.Image? {
        guard let data = await loadData(imageURL, tokenSlug: tokenSlug) else { return fallback }
        return .init(data: data)
    }

    static func bundledData(tokenSlug: String) -> Data? {
        if let chain = ApiChain.allCases.first(where: { $0.nativeToken.slug == tokenSlug }),
           let data = UIImage(named: "chain_\(chain.rawValue)", in: AirBundle, compatibleWith: nil)?.pngData() {
            return thumbnail(data)
        }
        return nil
    }

    static func loadData(_ imageURL: String?, tokenSlug: String) async -> Data? {
        if let data = bundledData(tokenSlug: tokenSlug) { return data }
        guard let imageURL, let url = URL(string: imageURL), url.scheme == "https" else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= 2_000_000 else { return nil }
            return thumbnail(data)
        } catch {
            return nil
        }
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 120,
                kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static var fallback: DisplayRepresentation.Image { .init(systemName: "circle.hexagongrid") }
}
