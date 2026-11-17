import SwiftUI
import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite(.serialized)
struct GramDiamondLifecycleTests {
    @Test(arguments: [96.0, 124.0])
    func renderFallbackWithoutMetalOrStickerViews(diamondSize: CGFloat) async throws {
        let fallback = GramDiamondWithParticles(diamondSize: diamondSize, isMetalAvailable: false)
        let renderer = ImageRenderer(content: fallback)
        let image = try #require(renderer.uiImage?.cgImage)
        #expect(image.width == Int(diamondSize))
        #expect(image.height == Int(diamondSize))
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        #expect(pixels[3] > 0)

        let host = UIHostingController(rootView: AnyView(fallback))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }

        for _ in 0..<2 {
            for size in [diamondSize, diamondSize / 2, diamondSize] {
                host.rootView = AnyView(GramDiamondWithParticles(diamondSize: size, isMetalAvailable: false))
                host.view.layoutIfNeeded()
                await drainMainQueue()
                host.view.layoutIfNeeded()
                #expect(!containsAnimatedView(in: host.view))
            }

            host.rootView = AnyView(EmptyView())
            host.view.layoutIfNeeded()
            await drainMainQueue()
            #expect(!containsAnimatedView(in: host.view))
        }
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func containsAnimatedView(in view: UIView) -> Bool {
        if view is TelegramDiamondContainerView || view is WAnimatedSticker || view is SparkleParticleBackgroundView {
            return true
        }
        return view.subviews.contains { containsAnimatedView(in: $0) }
    }
}
