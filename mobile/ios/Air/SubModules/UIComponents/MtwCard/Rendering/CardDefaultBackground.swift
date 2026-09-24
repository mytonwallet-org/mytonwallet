import UIKit

/// The same cached artwork is used by the static fallback, previews and Metal.
@MainActor
enum CardDefaultBackground {
    struct Artwork {
        let layers: CardBackgroundLayers
        let image: UIImage
    }

    private static let myWallet = make(.myWallet)
    private static let gramWallet = make(.gramWallet)

    static func artwork(_ kind: CardSurfaceConfiguration.DefaultArtwork) -> Artwork {
        kind == .myWallet ? myWallet : gramWallet
    }

    private static func make(_ kind: CardSurfaceConfiguration.DefaultArtwork) -> Artwork {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 232)
        let base = render(size: rect.size, scale: 2, opaque: true) { context in
            if kind == .myWallet, let image = UIImage(named: "MyWalletCardBase", in: .module, compatibleWith: nil) {
                image.draw(in: rect)
            } else {
                // Reference blue: #5CC8FF → #0088FF at 46% → #0057C2, CSS 145°.
                let colors = [UIColor(red: 92.0 / 255, green: 200.0 / 255, blue: 1, alpha: 1).cgColor,
                              UIColor(red: 0, green: 136.0 / 255, blue: 1, alpha: 1).cgColor,
                              UIColor(red: 0, green: 87.0 / 255, blue: 194.0 / 255, alpha: 1).cgColor]
                let angle = 145 * CGFloat.pi / 180
                let direction = CGPoint(x: sin(angle), y: -cos(angle))
                let halfLength = (abs(direction.x) * rect.width + abs(direction.y) * rect.height) / 2
                if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 0.46, 1]) {
                    context.drawLinearGradient(gradient,
                        start: CGPoint(x: rect.midX - direction.x * halfLength, y: rect.midY - direction.y * halfLength),
                        end: CGPoint(x: rect.midX + direction.x * halfLength, y: rect.midY + direction.y * halfLength),
                        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
            }
        }
        let padding = CardBackgroundLayers.spotPadding
        let blobBounds = rect.insetBy(dx: -padding, dy: -padding)
        let blobs: [(CGPoint, CGSize, UIColor)] = kind == .myWallet ? [
            (CGPoint(x: 335, y: 30), CGSize(width: 190, height: 160), UIColor(red: 0.05, green: 0.94, blue: 1, alpha: 0.72)),
            (CGPoint(x: 65, y: 205), CGSize(width: 175, height: 145), UIColor(red: 0.06, green: 0.71, blue: 1, alpha: 0.6)),
            (CGPoint(x: 100, y: -10), CGSize(width: 180, height: 140), UIColor(red: 0.015, green: 0.23, blue: 0.93, alpha: 0.6)),
        ] : []
        let spots = blobs.map { center, radius, color in
            render(size: blobBounds.size, scale: 1, opaque: false) { context in
                context.translateBy(x: padding, y: padding)
                glow(context, center: center, radius: radius, color: color)
            }
        }
        let image = render(size: rect.size, scale: 2, opaque: true) { context in
            base.draw(in: rect)
            for spot in spots { spot.draw(in: blobBounds) }
            if kind == .gramWallet { CardStarField.drawResting(in: context) }
        }
        return Artwork(layers: CardBackgroundLayers(base: base, spots: spots, contrastOpacity: 0, contrastColor: -1), image: image)
    }

    private static func render(size: CGSize, scale: CGFloat, opaque: Bool, draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = opaque
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    private static func glow(_ context: CGContext, center: CGPoint, radius: CGSize, color: UIColor) {
        let colors = [color.cgColor, color.withAlphaComponent(color.cgColor.alpha * 0.55).cgColor, color.withAlphaComponent(0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 0.4, 1]) else { return }
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: radius.width, y: radius.height)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        context.restoreGState()
    }
}
