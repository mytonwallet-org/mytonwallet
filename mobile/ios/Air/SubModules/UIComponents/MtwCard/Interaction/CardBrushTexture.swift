import UIKit

@MainActor
public enum CardBrushTexture {
    /// Neutral gray is unchanged by overlay blending; light and dark rings add fine grain.
    public static let radial: UIImage = {
        let size = CGSize(width: 400, height: 232)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor(white: 0.5, alpha: 1).setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            context.translateBy(x: size.width / 2, y: size.height / 2)
            let patterns: [(CGFloat, [(CGFloat, CGFloat, CGFloat)])] = [
                (11.7, [(0, 0.7, 0.32), (0.7, 1.25, -0.18)]),
                (5.2, [(0, 0.14, 0.22), (0.95, 1.85, -0.14), (1.85, 2.7, 0.16)]),
                (8.3, [(0, 0.45, -0.18), (1.15, 1.95, 0.28), (1.95, 2.15, -0.12), (4.2, 4.38, 0.12)]),
                (6.1, [(0, 0.22, 0.42), (0.22, 0.7, -0.2), (1.45, 1.58, 0.18), (2.5, 3.45, -0.16)]),
            ]
            for (period, strokes) in patterns {
                for offset in stride(from: CGFloat.zero, to: hypot(size.width, size.height), by: period) {
                    for (start, end, opacity) in strokes {
                        context.setStrokeColor((opacity > 0 ? UIColor.white : .black).withAlphaComponent(abs(opacity)).cgColor)
                        context.setLineWidth(end - start)
                        let radius = offset + (start + end) / 2
                        context.strokeEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2))
                    }
                }
            }
        }
    }()

    private static let cache: NSCache<UIImage, UIImage> = {
        let cache = NSCache<UIImage, UIImage>()
        cache.totalCostLimit = 6 * 1_024 * 1_024
        cache.countLimit = 4
        return cache
    }()

    static func applying(to image: UIImage) -> UIImage {
        if let cached = cache.object(forKey: image) { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        format.preferredRange = .standard
        let result = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            let bounds = CGRect(origin: .zero, size: image.size)
            image.draw(in: bounds)
            radial.draw(in: bounds, blendMode: .overlay, alpha: 0.15)
        }
        cache.setObject(result, forKey: image, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return result
    }
}
