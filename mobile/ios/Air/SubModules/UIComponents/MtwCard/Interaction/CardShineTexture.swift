import CoreImage
import UIKit

@MainActor
public enum CardShineTexture {
    public static let band: CGImage? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: CGSize(width: 512, height: 1), format: format).image { renderer in
            for x in 0..<512 {
                let distance = (Double(x) + 0.5 - 256) / 95
                let alpha = max(0, (exp(-distance * distance / 2) - 0.027) / 0.973)
                UIColor.white.withAlphaComponent(alpha).setFill()
                renderer.fill(CGRect(x: x, y: 0, width: 1, height: 1))
            }
        }.cgImage
    }()

    // The reference's two conic lobes and 18 px blur at a 400 pt card width, baked once.
    public static let radial: CGImage? = {
        let size = 512
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stops: [(angle: Double, alpha: Double)] = [
            (0, 0), (4, 0), (28, 0.18), (42, 0.45), (54, 1), (66, 0.45), (86, 0.18), (124, 0), (180, 0),
        ]
        for y in 0..<size {
            for x in 0..<size {
                let angle = (atan2(Double(x) + 0.5 - 256, 256 - Double(y) - 0.5) * 180 / .pi + 360)
                    .truncatingRemainder(dividingBy: 180)
                let index = stops.firstIndex { $0.angle >= angle } ?? (stops.count - 1)
                let lower = stops[max(0, index - 1)]
                let upper = stops[index]
                let fraction = upper.angle == lower.angle ? 0 : (angle - lower.angle) / (upper.angle - lower.angle)
                let value = UInt8((255 * (lower.alpha + (upper.alpha - lower.alpha) * fraction)).rounded())
                let offset = (y * size + x) * 4
                for component in 0..<4 { bytes[offset + component] = value }
            }
        }
        guard let raw = context.makeImage() else { return nil }
        let image = CIImage(cgImage: raw)
        let blurred = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 512 * 18.0 / 600])
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(blurred, from: image.extent)
    }()

    static func touchSpotExtent(cardWidth: CGFloat) -> CGFloat { cardWidth * 1.18 + 6 * 28 }

    /// CSS: 118% square, circle clipped before a 1.75rem Gaussian blur. Baked per card width.
    static func touchSpot(cardWidth: CGFloat) -> CGImage? {
        let size = 512
        let extent = Double(touchSpotExtent(cardWidth: cardWidth))
        let radius = Double(cardWidth) * 1.18 / 2
        guard radius > 0,
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stops: [(position: Double, alpha: Double)] = [(0, 0.27), (0.28, 0.1425), (0.58, 0.0525), (1, 0)]
        for y in 0..<size {
            for x in 0..<size {
                let distance = hypot(Double(x) + 0.5 - 256, Double(y) + 0.5 - 256) * extent / 512
                var alpha = 0.0
                if distance <= radius {
                    // CSS radial-gradient(circle) uses the square's farthest corner as 100%.
                    let position = distance / (radius * sqrt(2))
                    let index = stops.firstIndex { $0.position >= position } ?? 3
                    let lower = stops[max(0, index - 1)], upper = stops[index]
                    let fraction = (position - lower.position) / max(1e-12, upper.position - lower.position)
                    alpha = lower.alpha + (upper.alpha - lower.alpha) * fraction
                }
                let value = UInt8((255 * alpha).rounded())
                let offset = (y * size + x) * 4
                for component in 0..<4 { bytes[offset + component] = value }
            }
        }
        guard let raw = context.makeImage() else { return nil }
        let image = CIImage(cgImage: raw)
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 28 * 512 / extent])
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(blurred, from: image.extent)
    }

}
