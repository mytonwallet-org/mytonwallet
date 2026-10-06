import SwiftUI
import Testing
import UIKit
@testable import UIComponents

@MainActor
struct CardBackgroundRendererTests {
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
