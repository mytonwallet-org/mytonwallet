import SwiftUI
import Testing
import UIKit
@testable import UIComponents

@MainActor
struct CardBackgroundRendererTests {
    @Test(arguments: [CardBackgroundResolution.thumbnail, .full])
    func generatedCardPaintsEveryEdgePixel(resolution: CardBackgroundResolution) throws {
        let library = try CardBackgroundLibrary.shared.get()
        // Glass without texture, spots, or contrast is solid white, including its edges.
        let seed = try CardBackgroundSeed(
            cardId: "1-12-1-1-1-1-1-7-1-1-1-1-1-1-1-1",
            attributes: library.attributes
        )
        let image = try CardBackgroundRenderer.shared.image(seed: seed, resolution: resolution, showContrast: false)
        let bitmap = try #require(image.cgImage)
        let bytesPerRow = bitmap.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * bitmap.height)
        try pixels.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(
                data: storage.baseAddress, width: bitmap.width, height: bitmap.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        }
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where x == 0 || x == bitmap.width - 1 || y == 0 || y == bitmap.height - 1 {
                let offset = y * bytesPerRow + x * 4
                #expect(pixels[offset..<(offset + 4)].allSatisfy { $0 == 255 }, "Unpainted edge pixel at (\(x), \(y))")
            }
        }
    }

    @Test(arguments: [CardBackgroundResolution.thumbnail, .full])
    func generatedCardCanBeRegisteredAndDisplayed(resolution: CardBackgroundResolution) throws {
        let library = try CardBackgroundLibrary.shared.get()
        let seed = try CardBackgroundSeed(
            cardId: "1-8-3-1-3-6-5-4-4-2-3-3-3-4-3-3",
            attributes: library.attributes
        )
        let image = try CardBackgroundRenderer.shared.image(seed: seed, resolution: resolution)
        let pixels = try #require(image.cgImage)
        #expect(pixels.width == resolution.rawValue)
        #expect(pixels.height == Int(ceil(CGFloat(resolution.rawValue) * 232 / 400)))

        // CoreUI on iOS 17 rejects sub-1 scales when SwiftUI registers an image.
        try #require(image.scale >= 1)
        _ = try #require(image.imageAsset)
        let preview = ImageRenderer(content: Image(uiImage: image).resizable().frame(width: 100, height: 58))
        #expect(preview.uiImage != nil)
    }
}
