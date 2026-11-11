import Testing
import UIKit
@testable import UIComponents

@Suite @MainActor
struct IconViewDarkGlyphTests {
    @Test func darkGlyphsGetABackingWhileFullCirclesAndLightGlyphsDoNot() {
        #expect(IconView.isDarkGlyph(icon(color: UIColor(red: 0.01, green: 0.14, blue: 0.12, alpha: 1), fillsCircle: false)))
        #expect(!IconView.isDarkGlyph(icon(color: .black, fillsCircle: true)))
        #expect(!IconView.isDarkGlyph(icon(color: .orange, fillsCircle: true)))
        #expect(!IconView.isDarkGlyph(icon(color: .white, fillsCircle: false)))
        #expect(!IconView.isDarkGlyph(UIGraphicsImageRenderer(size: CGSize(width: 56, height: 56)).image { _ in }))
    }

    @Test func roundArtworkIsToldApartFromSquaresAndGlyphs() {
        #expect(IconView.isRoundArtwork(icon(color: .orange, fillsCircle: true)))
        #expect(IconView.isRoundArtwork(UIGraphicsImageRenderer(size: CGSize(width: 56, height: 56)).image { context in
            UIColor.yellow.setStroke()
            context.cgContext.setLineWidth(10)
            context.cgContext.strokeEllipse(in: CGRect(x: 5, y: 5, width: 46, height: 46))
        }))
        #expect(!IconView.isRoundArtwork(UIGraphicsImageRenderer(size: CGSize(width: 56, height: 56)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 56, height: 56))
        }))
        #expect(!IconView.isRoundArtwork(icon(color: .black, fillsCircle: false)))
    }

    /// A circle filling the frame, or a diamond like Hyperliquid's ETH glyph.
    private func icon(color: UIColor, fillsCircle: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 56, height: 56)).image { context in
            color.setFill()
            if fillsCircle {
                context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 56, height: 56))
            } else {
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: 28, y: 8))
                diamond.addLine(to: CGPoint(x: 40, y: 28))
                diamond.addLine(to: CGPoint(x: 28, y: 48))
                diamond.addLine(to: CGPoint(x: 16, y: 28))
                diamond.close()
                diamond.fill()
            }
        }
    }
}
