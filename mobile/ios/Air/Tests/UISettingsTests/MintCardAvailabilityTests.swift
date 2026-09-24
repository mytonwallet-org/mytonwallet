import Testing
import UIKit
import WalletContext
import WalletCore
@testable import UISettings

@MainActor
@Suite("Mint card availability contrast")
struct MintCardAvailabilityTests {
    @Test
    func countdownReplacesProgressWithPlainTotalAndRestoresItWhenStockArrives() throws {
        var info = try #require(DebugPromotionPreset.cardMintingCardsInfo[.standard])
        info.all = 10
        info.notMinted = 0
        info.startsAt = "2027-01-15T08:00:00Z"
        let view = MintCardAvailabilityView(frame: CGRect(x: 0, y: 0, width: 370, height: 36))
        view.configure(info, animated: false)
        view.layoutIfNeeded()
        let backdrop = try #require(view.subviews.first { $0 is UIVisualEffectView })
        #expect(backdrop.isHidden)
        #expect(view.accessibilityLabel == L10n.amountUniqueCardsTotal(amount: 10))
        info.notMinted = 1
        view.configure(info, animated: false)
        view.layoutIfNeeded()
        #expect(!backdrop.isHidden)
        #expect(view.accessibilityLabel?.contains(L10n.amountLeft(amount: localizedIntegerString(1))) == true)
    }

    @Test
    func bothLabelsChangeInkAtTheFillBoundaryInEitherDirection() throws {
        for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
            for remaining in [10, 90] {
                var info = try #require(DebugPromotionPreset.cardMintingCardsInfo[.standard])
                info.all = 100
                info.notMinted = remaining
                let view = MintCardAvailabilityView(frame: CGRect(x: 0, y: 0, width: 370, height: 36))
                view.semanticContentAttribute = direction
                view.configure(info, animated: false)
                view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 2
                let rendered = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { context in
                    UIColor.darkGray.setFill()
                    context.fill(view.bounds)
                    view.layer.render(in: context.cgContext)
                }
                let image = try #require(rendered.cgImage)
                let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
                let fillWidth = 362 * Double(remaining) / 100
                let isRTL = direction == .forceRightToLeft
                let boundary = (isRTL ? 366 - fillWidth : 4 + fillWidth) * 2
                let labels = view.subviews.flatMap(\.subviews).compactMap { $0 as? UILabel }
                let crossing = try #require(labels.first { $0.frame.minX * 2 < boundary && $0.frame.maxX * 2 > boundary })
                var filledInkPixels = 0
                var outsideInkPixels = 0
                for x in Int(crossing.frame.minX * 2)..<Int(crossing.frame.maxX * 2) {
                    for y in 16..<image.height - 16 {
                        let offset = (y * image.width + x) * 4
                        let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                        let inFill = isRTL ? Double(x) > boundary + 2 : Double(x) < boundary - 2
                        let outsideFill = isRTL ? Double(x) < boundary - 2 : Double(x) > boundary + 2
                        if inFill, abs(r - 132) < 6, abs(g - 145) < 6, abs(b - 165) < 6 { filledInkPixels += 1 }
                        if outsideFill, r > 248, g > 248, b > 248 { outsideInkPixels += 1 }
                    }
                }
                #expect(filledInkPixels > 0)
                #expect(outsideInkPixels > 0)
            }
        }
    }
}
