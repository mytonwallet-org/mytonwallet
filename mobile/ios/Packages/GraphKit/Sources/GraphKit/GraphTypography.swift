import UIKit

public enum GraphTypography {
    public struct Fonts {
        public let supporting: UIFont
        public let supportingEmphasized: UIFont
        public let supportingBold: UIFont
        public let caption: UIFont
        public let technicalSupportingBold: UIFont
        public let technicalCaptionBold: UIFont
        public let technicalAxis: UIFont
        public let technicalFallback: UIFont
        public let technicalSymbol: UIFont

        public init(
            supporting: UIFont,
            supportingEmphasized: UIFont,
            supportingBold: UIFont,
            caption: UIFont,
            technicalSupportingBold: UIFont,
            technicalCaptionBold: UIFont,
            technicalAxis: UIFont,
            technicalFallback: UIFont,
            technicalSymbol: UIFont
        ) {
            self.supporting = supporting
            self.supportingEmphasized = supportingEmphasized
            self.supportingBold = supportingBold
            self.caption = caption
            self.technicalSupportingBold = technicalSupportingBold
            self.technicalCaptionBold = technicalCaptionBold
            self.technicalAxis = technicalAxis
            self.technicalFallback = technicalFallback
            self.technicalSymbol = technicalSymbol
        }
    }

    private static var fonts = Fonts(
        supporting: .systemFont(ofSize: 14, weight: .regular),
        supportingEmphasized: .systemFont(ofSize: 14, weight: .medium),
        supportingBold: .systemFont(ofSize: 14, weight: .bold),
        caption: .systemFont(ofSize: 12, weight: .regular),
        technicalSupportingBold: .systemFont(ofSize: 14, weight: .bold),
        technicalCaptionBold: .systemFont(ofSize: 12, weight: .bold),
        technicalAxis: .systemFont(ofSize: 11, weight: .regular),
        technicalFallback: .systemFont(ofSize: 14, weight: .regular),
        technicalSymbol: .systemFont(ofSize: 14, weight: .medium)
    )

    public static func configure(fonts: Fonts) {
        self.fonts = fonts
    }

    static var supportingFont: UIFont { fonts.supporting }
    static var supportingEmphasizedFont: UIFont { fonts.supportingEmphasized }
    static var supportingBoldFont: UIFont { fonts.supportingBold }
    static var captionFont: UIFont { fonts.caption }
    static var technicalSupportingBoldFont: UIFont { fonts.technicalSupportingBold }
    static var technicalCaptionBoldFont: UIFont { fonts.technicalCaptionBold }
    static var technicalAxisFont: UIFont { fonts.technicalAxis }
    static var technicalFallbackFont: UIFont { fonts.technicalFallback }
    static var technicalSymbolFont: UIFont { fonts.technicalSymbol }

    static func technicalPieValueFont(pointSize: CGFloat) -> UIFont {
        .systemFont(ofSize: pointSize, weight: .bold)
    }
}
