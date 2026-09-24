import UIKit

/// One small instanced quad per star; positions and phases are uploaded only once.
enum CardStarField {
    struct Star {
        var position: SIMD2<Float>
        var radius: Float
        var phase: Float
    }

    // Keep the lower-right corner clear of the mint-card wand.
    static let stars: [Star] = [
        SIMD2<Float>(30, 28), SIMD2(74, 18), SIMD2(127, 30), SIMD2(211, 18), SIMD2(293, 24),
        SIMD2(368, 32), SIMD2(344, 63), SIMD2(26, 85), SIMD2(379, 119), SIMD2(27, 147),
        SIMD2(59, 179), SIMD2(28, 214), SIMD2(101, 209), SIMD2(170, 214), SIMD2(238, 209),
        SIMD2(316, 212), SIMD2(370, 154), SIMD2(340, 165), SIMD2(377, 69), SIMD2(85, 56),
    ].enumerated().map { index, position in
        Star(position: position, radius: [6, 3, 4, 2.5, 3, 8, 3.5, 4, 5, 3, 7.5, 3, 4.5, 3, 2.5, 4, 6, 3.5, 4, 3][index], phase: Float(index) * 2.3999632)
    }

    static func drawResting(in context: CGContext) {
        for star in stars {
            let pulse = min(1, max(0, (0.5 + 0.5 * sin(star.phase) - 0.15) / 0.85))
            let twinkle = pulse * pulse * (3 - 2 * pulse)
            let radius = CGFloat(star.radius * (0.15 + 0.85 * twinkle))
            let x = CGFloat(star.position.x), y = CGFloat(star.position.y)
            context.setFillColor(UIColor(white: 1, alpha: CGFloat(twinkle * 0.65)).cgColor)
            context.move(to: CGPoint(x: x, y: y - radius))
            for point in [CGPoint(x: x + radius, y: y), CGPoint(x: x, y: y + radius),
                          CGPoint(x: x - radius, y: y), CGPoint(x: x, y: y - radius)] {
                context.addQuadCurve(to: point, control: CGPoint(x: x, y: y))
            }
            context.fillPath()
        }
    }
}
