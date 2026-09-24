import SwiftUI
import UIKit

public enum CardBackgroundResolution: Int, Sendable {
    case thumbnail = 256
    case full = 800
}

/// Cache complete still images and separate animation layers. The vector scene
/// and its blur filters are never part of the per-frame render tree.
@MainActor
public final class CardBackgroundRenderer {
    public static let shared = CardBackgroundRenderer()
    private let images = NSCache<NSString, UIImage>()
    private let animationLayers = NSCache<NSString, CardBackgroundLayers>()
    private var contrast: [String: Double] = [:]
    public private(set) var renderCount = 0
    public private(set) var cacheHitCount = 0
    public private(set) var lastRenderMilliseconds = 0.0

    private init() {
        images.totalCostLimit = 24 * 1_024 * 1_024
        images.countLimit = 64
        animationLayers.totalCostLimit = 16 * 1_024 * 1_024
        animationLayers.countLimit = 4
    }

    func layers(seed: CardBackgroundSeed, showContrast: Bool) throws -> CardBackgroundLayers {
        let key = "\(seed.cardId):\(showContrast)" as NSString
        if let cached = animationLayers.object(forKey: key) { return cached }
        let library = try CardBackgroundLibrary.shared.get()
        let opacity = showContrast && seed.isStandard ? contrastOpacity(seed: seed, library: library) : 0
        func render(_ layer: CardBackgroundArtwork.Layer, padding: CGFloat, scale: CGFloat) throws -> UIImage {
            let renderer = ImageRenderer(content: CardBackgroundArtwork(seed: seed, library: library, layer: layer, padding: padding)
                .frame(width: 400 + 2 * padding, height: 232 + 2 * padding))
            renderer.scale = scale
            renderer.isOpaque = layer == .base
            guard let image = renderer.uiImage else {
                throw CardBackgroundSeed.InvalidSeed(message: "Could not render the card background layers.")
            }
            return image
        }
        let base = try render(.base, padding: 0, scale: 2)
        var spots: [UIImage] = []
        if seed.isStandard {
            for (index, ordinal) in ["First", "Second", "Third"].enumerated() {
                guard seed["\(ordinal) Spot Color"] != "No" else { continue }
                // Soft blobs need only one pixel per canonical point. Padding keeps
                // off-card color available as the blob orbits its original anchor.
                spots.append(try render(.spot(index), padding: CardBackgroundLayers.spotPadding, scale: 1))
            }
        }
        let result = CardBackgroundLayers(base: base, spots: spots,
            contrastOpacity: Float(opacity),
            contrastColor: showContrast && seed.isStandard ? (seed["Text"] == "Dark" ? 1 : 0) : -1)
        animationLayers.setObject(result, forKey: key, cost: ([base] + spots).reduce(0) {
            $0 + ($1.cgImage.map { $0.bytesPerRow * $0.height } ?? 0)
        })
        return result
    }

    func cachedImage(seed: CardBackgroundSeed, resolution: CardBackgroundResolution, showContrast: Bool) -> UIImage? {
        images.object(forKey: "\(seed.cardId):\(resolution.rawValue):\(showContrast)" as NSString)
    }

    public func image(seed: CardBackgroundSeed, resolution: CardBackgroundResolution = .full, showContrast: Bool = true) throws -> UIImage {
        // The motion seed affects sampling coordinates, never the generated texture.
        let key = "\(seed.cardId):\(resolution.rawValue):\(showContrast)" as NSString
        if let image = images.object(forKey: key) {
            cacheHitCount += 1
            return image
        }
        let start = CACurrentMediaTime()
        let library = try CardBackgroundLibrary.shared.get()
        let opacity = showContrast && seed.isStandard ? contrastOpacity(seed: seed, library: library) : 0
        // Always lay out at the generator's size, even for thumbnails. In particular,
        // Canvas blur radii must not depend on the size of the consuming UI surface.
        let renderer = ImageRenderer(content: CardBackgroundArtwork(
            seed: seed, library: library, contrastOpacity: opacity, showContrast: showContrast
        ).frame(width: 400, height: 232))
        renderer.scale = CGFloat(resolution.rawValue) / 400
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let cgImage = image.cgImage else {
            throw CardBackgroundSeed.InvalidSeed(message: "Could not render the card background.")
        }
        images.setObject(image, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        renderCount += 1
        lastRenderMilliseconds = (CACurrentMediaTime() - start) * 1_000
        return image
    }

    private func contrastOpacity(seed: CardBackgroundSeed, library: CardBackgroundLibrary) -> Double {
        if let cached = contrast[seed.cardId] { return cached }
        let opacity = CardBackgroundContrast.opacity(seed: seed, library: library)
        if contrast.count >= 256 { contrast.removeAll(keepingCapacity: true) }
        contrast[seed.cardId] = opacity
        return opacity
    }
}

final class CardBackgroundLayers {
    // The rotated 400 × 232 viewport fits inside this padding at every angle.
    static let spotPadding: CGFloat = 128
    let base: UIImage
    let spots: [UIImage]
    let contrastOpacity: Float
    let contrastColor: Float

    init(base: UIImage, spots: [UIImage], contrastOpacity: Float, contrastColor: Float) {
        self.base = base
        self.spots = spots
        self.contrastOpacity = contrastOpacity
        self.contrastColor = contrastColor
    }
}

/// Reused by the Lab and production card surfaces, including static previews.
public struct CardBackgroundRaster: View {
    private let seed: CardBackgroundSeed
    private let resolution: CardBackgroundResolution
    private let showContrast: Bool
    @State private var rendered: (key: String, image: UIImage)?

    public init(seed: CardBackgroundSeed, resolution: CardBackgroundResolution = .full, showContrast: Bool = true) {
        self.seed = seed
        self.resolution = resolution
        self.showContrast = showContrast
        if let image = CardBackgroundRenderer.shared.cachedImage(seed: seed, resolution: resolution, showContrast: showContrast) {
            _rendered = State(initialValue: ("\(seed.cardId):\(resolution.rawValue):\(showContrast)", image))
        }
    }

    private var key: String { "\(seed.cardId):\(resolution.rawValue):\(showContrast)" }

    public var body: some View {
        Group {
            if let rendered, rendered.key == key {
                Image(uiImage: rendered.image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .task(id: key) {
            guard rendered?.key != key else { return }
            // Coalesce views requesting the same seed: rendering and insertion run
            // together on the main actor, so the next request immediately hits cache.
            await Task.yield()
            guard !Task.isCancelled else { return }
            if let image = try? CardBackgroundRenderer.shared.image(seed: seed, resolution: resolution, showContrast: showContrast) {
                rendered = (key, image)
            }
        }
        .onDisappear { rendered = nil }
        .accessibilityHidden(true)
    }
}
