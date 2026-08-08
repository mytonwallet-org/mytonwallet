import Testing
import UIKit
@testable import UIComponents

@MainActor
@Suite("WTypography")
struct WTypographyTests {
    @Test
    func `styles use fixed point sizes by default`() {
        #expect(WTypography.uiFont(.body).pointSize == 17)
        #expect(WTypography.uiFont(.supporting).pointSize == 14)
        #expect(WTypography.uiFont(.amount).pointSize == 24)
        #expect(WTypography.uiFont(.compactButton).pointSize == 15)
        #expect(WTypography.uiFont(.largeTitle).pointSize == 34)
        #expect(WTypography.uiFont(.title2).pointSize == 22)
        #expect(WTypography.uiFont(.micro).pointSize == 10)
    }

    @Test
    func `dynamic styles scale relative to their semantic tier`() {
        let defaultTraits = UITraitCollection(
            preferredContentSizeCategory: .large
        )
        let accessibilityTraits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )

        let defaultBody = WTypography.uiFont(
            .body,
            content: .technical,
            scaling: .dynamic,
            language: .fa,
            compatibleWith: defaultTraits
        )
        let body = WTypography.uiFont(
            .body,
            content: .technical,
            scaling: .dynamic,
            language: .fa,
            compatibleWith: accessibilityTraits
        )
        let title = WTypography.uiFont(
            .title2,
            content: .technical,
            scaling: .dynamic,
            language: .fa,
            compatibleWith: accessibilityTraits
        )
        let footnote = WTypography.uiFont(
            .footnote,
            content: .technical,
            scaling: .dynamic,
            language: .fa,
            compatibleWith: accessibilityTraits
        )

        #expect(defaultBody.pointSize == 17)
        #expect(body.pointSize > defaultBody.pointSize)
        #expect(title.pointSize > 22)
        #expect(footnote.pointSize > 13)
    }

    @Test
    func `dynamic Persian style preserves the localized typeface`() {
        let accessibilityTraits = UITraitCollection(
            preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge
        )
        let font = WTypography.uiFont(
            .body,
            content: .default,
            scaling: .dynamic,
            language: .fa,
            compatibleWith: accessibilityTraits
        )

        #expect(font.fontName == "Vazirmatn-Regular")
        #expect(font.pointSize > 17)
    }

    @Test
    func `UIKit helpers opt into content size category updates`() {
        let label = UILabel()
        label.applyTextStyle(.body, scaling: .dynamic)

        #expect(label.adjustsFontForContentSizeCategory)

        label.applyTextStyle(.body)
        #expect(!label.adjustsFontForContentSizeCategory)
    }

    @Test
    func `caption tiers use standard point sizes`() {
        #expect(WTypography.uiFont(.caption).pointSize == 12)
        #expect(WTypography.uiFont(.caption2).pointSize == 11)
    }

    @Test
    func `Persian default content uses Vazirmatn`() {
        let font = WTypography.uiFont(
            .body,
            content: .default,
            language: .fa
        )

        #expect(font.fontName == "Vazirmatn-Regular")
    }

    @Test
    func `Persian technical content keeps system font`() {
        let font = WTypography.uiFont(
            .body,
            content: .technical,
            language: .fa
        )

        #expect(font.fontName != "Vazirmatn-Regular")
        #expect(font.pointSize == 17)
    }

    @Test
    func `Persian styles select matching weight faces`() {
        #expect(WTypography.uiFont(
            .bodyEmphasized,
            content: .default,
            language: .fa
        ).fontName == "Vazirmatn-Medium")
        #expect(WTypography.uiFont(
            .bodyStrong,
            content: .default,
            language: .fa
        ).fontName == "Vazirmatn-SemiBold")
        #expect(WTypography.uiFont(
            .emptyStateTitle,
            content: .default,
            language: .fa
        ).fontName == "Vazirmatn-Bold")
        #expect(WTypography.uiFont(
            .promotionTitle,
            content: .default,
            language: .fa
        ).fontName == "Vazirmatn-Bold")
    }
}
