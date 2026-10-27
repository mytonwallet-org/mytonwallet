import UIKit
import Kingfisher

struct NftDetailsContentPalette {
    let baseColor: UIColor
    let subtleBackgroundColor: UIColor
    let edgeColor: UIColor
    let secondaryTextColor: UIColor
    let highlightColor: UIColor
    
    static let lightBase = NftDetailsContentPalette(
            baseColor: .black,
            subtleBackgroundColor: .black.withAlphaComponent(0.06),
            edgeColor: .white.withAlphaComponent(0.7),
            secondaryTextColor: .black.withAlphaComponent(0.75),
            highlightColor: .black.withAlphaComponent(0.2),
        )

    static let darkBase = NftDetailsContentPalette(
            baseColor: .white,
            subtleBackgroundColor: .white.withAlphaComponent(0.08),
            edgeColor: .white.withAlphaComponent(0.3),
            secondaryTextColor: .white.withAlphaComponent(0.75),
            highlightColor: .white.withAlphaComponent(0.6),
        )
}

@MainActor
class NftDetailsColorResolver {
    private let colorCache: NftDetailsColorCache

    private static var defaultBackgroundColor: UIColor { .air.sheetBackground }
    private static let loadingBackgroundColor = UIColor(white: 0.16, alpha: 1)
    private var thumbnailColors: [String: UIColor] = [:]
    
    private(set) var fallbackColor: UIColor

    init(colorCache: NftDetailsColorCache) {
        self.colorCache = colorCache
        fallbackColor = Self.defaultBackgroundColor
    }

    func update(traitCollection: UITraitCollection) {
        fallbackColor = Self.defaultBackgroundColor.resolvedColor(with: traitCollection)
    }

    func currentBaseColor(for model: NftDetailsItemModel) -> UIColor? {
        if case .loaded(let processed) = model.processedImageState {
            return processed.isPlaceholder ? fallbackColor : processed.baseColor
        }
        let (_, cached) = colorCache.color(forKey: model.id)
        if let cached { return cached }
        if let color = thumbnailColors[model.id] { return color }
        if let url = model.item.coverflowImageUrl,
           let image = ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey) {
            rememberThumbnail(image, for: model)
        }
        return thumbnailColors[model.id]
    }

    /// Use the same bottom-edge sample and shading as the full preview, before
    /// its asynchronous Core Image processing completes.
    func rememberThumbnail(_ image: UIImage, for model: NftDetailsItemModel) {
        guard thumbnailColors[model.id] == nil,
              let color = NftDetailsImageProcessor.bottomBackgroundColor(image) else { return }
        thumbnailColors[model.id] = NftDetailsImageProcessor.pageBackgroundColor(color)
    }

    func effectiveBaseColor(for model: NftDetailsItemModel) -> UIColor {
        if let color = currentBaseColor(for: model) { return color }
        switch model.processedImageState {
        case .loaded, .failed:
            return fallbackColor
        case .idle, .loading:
            guard model.item.imageUrl != nil else { return fallbackColor }
            return Self.loadingBackgroundColor
        }
    }

    func contentPalette(for model: NftDetailsItemModel) -> NftDetailsContentPalette {
        let c = effectiveBaseColor(for: model)
        return c.isLightColor ? .lightBase : .darkBase
    }
}

/// Page subviews should adopt this protocol to respond to NFT theme changes
protocol NftDetailsContentColorConsumer: UIView {
    
    /// Return `true` to process subviews as well, `false` otherwise
    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool
}

/// Small, cached bitmap for contrast decisions. Sampling never captures the UI
/// (which would include the navigation button itself).
struct NftDetailsImageSample {
    let image: UIImage
    private let side = 32
    private var pixels: [UInt8]

    init(image: UIImage) {
        self.image = image
        pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        if let cg = thumbnail.cgImage,
           let context = CGContext(data: &pixels, width: 32, height: 32, bitsPerComponent: 8,
                                   bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
    }

    func color(in rect: CGRect, over background: UIColor) -> UIColor {
        let clipped = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0, rect.width > 0, rect.height > 0 else { return background }
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let x0 = max(0, min(side - 1, Int(floor(clipped.minX * CGFloat(side)))))
        let y0 = max(0, min(side - 1, Int(floor(clipped.minY * CGFloat(side)))))
        let x1 = max(x0 + 1, min(side, Int(ceil(clipped.maxX * CGFloat(side)))))
        let y1 = max(y0 + 1, min(side, Int(ceil(clipped.maxY * CGFloat(side)))))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * side + x) * 4
                let alpha = CGFloat(pixels[i + 3]) / 255
                r += CGFloat(pixels[i]) / 255 + br * (1 - alpha)
                g += CGFloat(pixels[i + 1]) / 255 + bg * (1 - alpha)
                b += CGFloat(pixels[i + 2]) / 255 + bb * (1 - alpha)
            }
        }
        let count = CGFloat((x1 - x0) * (y1 - y0))
        let coverage = min(1, clipped.width * clipped.height / (rect.width * rect.height))
        return background.nftBlended(with: UIColor(red: r / count, green: g / count, blue: b / count, alpha: 1), fraction: coverage)
    }
}
