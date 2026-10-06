import CoreText
import Testing
import UIKit
import UIComponents

@MainActor
struct CompactFontsTests {
    // Metrics captured from the former bundled fonts, without automatic optical sizing.
    @Test(arguments: [17.0, 34.0, 56.0])
    func roundedPreservesCompactFaceAndMetrics(size: Double) {
        let font = UIFont.compactRounded(ofSize: size, weight: .bold)
        #expect(font.fontName == ".SFCompactRounded-Bold")
        checkMetrics(font, widthAt34: 189.4736328125, capHeightAt34: 22.77734375, xHeightAt34: 17.5146484375)
    }

    @Test(arguments: [17.0, 34.0, 56.0])
    func displayPreservesCompactFaceAndMetrics(size: Double) {
        let font = UIFont.compactDisplay(ofSize: size, weight: .medium)
        #expect(font.fontName == ".SFCompact-Medium")
        checkMetrics(font, widthAt34: 180.3759765625, capHeightAt34: 22.6611328125, xHeightAt34: 17.5478515625)
    }

    private func checkMetrics(_ font: UIFont, widthAt34: Double, capHeightAt34: Double, xHeightAt34: Double) {
        let scale = font.pointSize / 34
        let text = NSAttributedString(string: "$123,456.78", attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(text)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Allow the small outline/advance differences between OS and bundled font revisions.
        #expect(abs(width - widthAt34 * scale) < 0.05)
        #expect(abs(font.ascender - 32.373046875 * scale) < 0.001)
        #expect(abs(font.descender + 8.201171875 * scale) < 0.001)
        #expect(abs(font.lineHeight - 40.57421875 * scale) < 0.001)
        #expect(abs(font.capHeight - capHeightAt34 * scale) < 0.001)
        #expect(abs(font.xHeight - xHeightAt34 * scale) < 0.001)
    }
}
