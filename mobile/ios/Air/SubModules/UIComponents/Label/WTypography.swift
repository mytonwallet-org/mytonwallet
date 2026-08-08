import CoreText
import ContextMenuKit
import SwiftUI
import UIKit
import WalletContext

public enum WTextContent: Equatable, Sendable {
    /// Content that follows the app language and may use its localized typeface.
    case `default`
    /// Content such as addresses, amounts, and symbols that should keep the system typeface.
    case technical
}

/// Controls whether a text style keeps its default point size or follows Dynamic Type.
public enum WTextScaling: Equatable, Sendable {
    /// Keeps the style at its documented point size. Use for layouts with fixed metrics.
    case fixed
    /// Scales the style relative to its matching system text style.
    case dynamic
}

public enum WTextStyle: Hashable, Sendable {
    /// SF Pro 34 pt Bold. Example: the primary title in `ExploreVC`.
    case largeTitle
    /// SF Pro 32 pt Semibold. Example: the prompt title in `WordCheckView`.
    case onboardingTitle
    /// SF Pro 28 pt Semibold. Example: the title label in `HeaderView`.
    case screenTitle
    /// SF Pro 28 pt Bold. Example: the heading in `StartupFailureView`.
    case startupTitle
    /// SF Pro 22.5 pt Bold. Example: a category title in `ExploreVC`.
    case sectionTitle
    /// SF Pro 22 pt Regular. Example: the stub title in `TopTabsRootViewController`.
    case title2
    /// SF Pro 22 pt Bold. Example: a section heading in `DebugView`.
    case title2Strong
    /// SF Pro 20 pt Regular. Example: the prompt in `PasscodeScreenView`.
    case title3
    /// SF Pro 20 pt Medium. Example: the plugin symbol in `PluginCellContent`; use with technical content.
    case largeSymbol
    /// SF Pro 20 pt Heavy. Example: the heading in `PromotionVC`.
    case promotionTitle
    /// SF Pro 20 pt Semibold. Example: the payment status in `WalletConnectPayLoadingVC`.
    case statusTitle
    /// SF Pro 13 pt Regular, or 17 pt Semibold in iOS 26 mode. Example: an `InsetSection` header.
    case sectionHeader
    /// SF Pro 17 pt Regular. Example: the primary label in `WalletSeeAllCell`.
    case body
    /// SF Pro 17 pt Medium. Example: the title in `WalletAssetsEmptyCell`.
    case bodyEmphasized
    /// SF Pro 17 pt Semibold. Example: a title in `NavigationHeader`.
    case bodyStrong
    /// SF Pro 17 pt Bold. Example: the warning symbol in `DappOriginWarning`; use with technical content.
    case bodyBold
    /// SF Pro 16 pt Regular. Example: the collection name in `NftDetailsCollectionButton`.
    case callout
    /// SF Pro 16 pt Medium. Example: the token name in `WalletTokenCell`.
    case calloutEmphasized
    /// SF Pro 16 pt Semibold. Example: the action label in `HiddenByUserCell`.
    case calloutStrong
    /// SF Pro 16 pt Bold. Example: the standard title in `OpenButtonStyle`.
    case calloutBold
    /// SF Pro 15 pt Regular. Example: a value in `NftDetailsAttributesGrid`.
    case subheadline
    /// SF Pro 15 pt Medium. Example: the inactive search prompt in `ExploreSearch`.
    case subheadlineEmphasized
    /// SF Pro 15 pt Semibold. Example: a dapp title in `SearchRowView`.
    case subheadlineStrong
    /// SF Pro 15 pt Bold. Example: a suggested prompt in `AgentHintsSectionCell`.
    case subheadlineBold
    /// SF Pro 14 pt Regular. Example: the description in `WalletAssetsEmptyCell`.
    case supporting
    /// SF Pro 14 pt Medium. Example: the NFT name in `NftCell`.
    case supportingEmphasized
    /// SF Pro 14 pt Semibold. Example: the close symbol in `NftRenewDomainWarningView`.
    case supportingStrong
    /// SF Pro 14 pt Bold. Example: the URL warning symbol in `DappHeaderView`; use with technical content.
    case supportingBold
    /// SF Pro 13 pt Regular. Example: the collection name in `NftPreviewRow`.
    case footnote
    /// SF Pro 13 pt Medium. Example: a title in `WScalableButton`.
    case footnoteEmphasized
    /// SF Pro 13 pt Semibold. Example: the message in `WarningView`.
    case footnoteStrong
    /// SF Pro 12 pt Regular. Example: the collection subtitle in `NftCell`.
    case caption
    /// SF Pro 12 pt Medium. Example: a folder caption in `DappFoldersView`.
    case captionEmphasized
    /// SF Pro 12 pt Semibold. Example: the label in `NftDomainExpirationBannerView`.
    case captionStrong
    /// SF Pro 12 pt Bold. Example: the compact title in `NftNoImagePlaceholderView`.
    case captionBold
    /// SF Pro 11 pt Regular. Example: the timestamp in `AgentMessageCells`.
    case caption2
    /// SF Pro 11 pt Medium. Example: system-status text in `AgentMessageCells`.
    case caption2Emphasized
    /// SF Pro 11 pt Semibold. Example: the menu chevron in `SendPayloadInputSection`.
    case caption2Strong
    /// SF Pro 10 pt Regular. Example: the “Tap to reveal” hint in `ActivityView`.
    case micro
    /// SF Pro 9 pt Semibold. Example: the compact label in `NftDomainExpirationBannerView`.
    case compactBadge
    /// SF Pro 10 pt Semibold. Example: the text in `BadgeView`.
    case badge
    /// SF Pro 10 pt Medium. Example: a compact tab label in `CustomizeAppTabs`.
    case badgeEmphasized
    /// SF Pro 10 pt Bold. Example: the disclosure chevron in `TokenInfoView`; use with technical content.
    case badgeBold
    /// SF Pro 13 pt Semibold. Example: the large variant in `BadgeView`.
    case largeBadge
    /// SF Pro 18 pt Regular. Example: an SF Symbol in `SearchRowView`; use with technical content.
    case symbol
    /// SF Pro 18 pt Medium. Example: the delete symbol in `ReorderableCollectionViewCell`; use with technical content.
    case symbolEmphasized
    /// SF Pro 23 pt Medium. Example: the back chevron in `WNavigationBar`; use with technical content.
    case navigationSymbol
    /// SF Pro 17 pt Semibold. Example: the title in a primary `WButton`.
    case button
    /// SF Pro 17 pt Medium. Example: the title in a thick capsule `WButton`.
    case capsuleButton
    /// SF Pro 15 pt Medium. Example: the title in a compact `WButton`.
    case compactButton
    /// SF Pro 24 pt Semibold. Example: the primary value in `TokenAmountEntry`.
    case amount
    /// SF Pro 20 pt Semibold. Example: the secondary value in `TokenAmountEntry`.
    case amountSecondary
    /// SF Pro 24 pt Medium. Example: the currency symbol in `TokenAmountEntry`.
    case amountSymbol
    /// SF Pro 24 pt Semibold. Example: the account name in `SettingsHeaderView`.
    case prominentTitle
    /// SF Pro 20 pt Bold. Example: the regular title in `NftNoImagePlaceholderView`.
    case emptyStateTitle
}

@MainActor
public enum WTypography {
    private static var didAttemptVazirmatnRegistration = false

    public static func uiFont(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) -> UIFont {
        uiFont(
            style,
            content: content,
            scaling: scaling,
            language: .current
        )
    }

    public static func font(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) -> Font {
        guard scaling == .dynamic else {
            return Font(uiFont(style, content: content))
        }

        let metrics = style.metrics
        if content == .default, Language.current == .fa {
            registerVazirmatnIfNeeded()
            if UIFont(
                name: metrics.weight.vazirmatnFontName,
                size: metrics.pointSize
            ) != nil {
                return .custom(
                    metrics.weight.vazirmatnFontName,
                    size: metrics.pointSize,
                    relativeTo: style.dynamicTypeStyle.swiftUITextStyle
                )
            }
            assertionFailure(
                "Missing font \(metrics.weight.vazirmatnFontName)"
            )
        }

        return .system(
            style.dynamicTypeStyle.swiftUITextStyle,
            design: .default,
            weight: metrics.weight.swiftUIFontWeight
        )
    }

    public static func configureDependentComponents() {
        ContextMenuTypography.configure(fonts: .init(
            title: uiFont(.body),
            subtitle: uiFont(.supporting),
            badge: uiFont(.footnote),
            symbol: uiFont(.footnoteStrong, content: .technical)
        ))
    }

    static func uiFont(
        _ style: WTextStyle,
        content: WTextContent,
        scaling: WTextScaling = .fixed,
        language: Language,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let metrics = style.metrics
        let systemFont = UIFont.systemFont(
            ofSize: metrics.pointSize,
            weight: metrics.weight.uiFontWeight
        )
        let baseFont: UIFont
        if content == .default, language == .fa {
            registerVazirmatnIfNeeded()
            if let font = UIFont(
                name: metrics.weight.vazirmatnFontName,
                size: metrics.pointSize
            ) {
                baseFont = font
            } else {
                assertionFailure(
                    "Missing font \(metrics.weight.vazirmatnFontName)"
                )
                baseFont = systemFont
            }
        } else {
            baseFont = systemFont
        }

        guard scaling == .dynamic else {
            return baseFont
        }
        return UIFontMetrics(
            forTextStyle: style.dynamicTypeStyle.uiKitTextStyle
        ).scaledFont(
            for: baseFont,
            compatibleWith: traitCollection
        )
    }

    private static func registerVazirmatnIfNeeded() {
        guard UIFont(name: "Vazirmatn-Regular", size: 17) == nil,
              !didAttemptVazirmatnRegistration else {
            return
        }
        didAttemptVazirmatnRegistration = true
        for name in [
            "Vazirmatn-Regular",
            "Vazirmatn-Medium",
            "Vazirmatn-SemiBold",
            "Vazirmatn-Bold",
        ] {
            guard let url = AirBundle.url(
                forResource: name,
                withExtension: "ttf"
            ) else {
                assertionFailure("Missing font resource \(name).ttf")
                continue
            }
            CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                nil
            )
        }
    }
}

public extension Text {
    @MainActor
    func textStyle(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) -> Text {
        font(WTypography.font(
            style,
            content: content,
            scaling: scaling
        ))
    }
}

public extension View {
    @MainActor
    func textStyle(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) -> some View {
        font(WTypography.font(
            style,
            content: content,
            scaling: scaling
        ))
    }
}

public extension UILabel {
    func applyTextStyle(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) {
        font = WTypography.uiFont(
            style,
            content: content,
            scaling: scaling
        )
        adjustsFontForContentSizeCategory = scaling == .dynamic
    }
}

public extension UITextField {
    func applyTextStyle(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) {
        font = WTypography.uiFont(
            style,
            content: content,
            scaling: scaling
        )
        adjustsFontForContentSizeCategory = scaling == .dynamic
    }
}

public extension UITextView {
    func applyTextStyle(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) {
        font = WTypography.uiFont(
            style,
            content: content,
            scaling: scaling
        )
        adjustsFontForContentSizeCategory = scaling == .dynamic
    }
}

public extension UIListContentConfiguration {
    @MainActor
    mutating func applyTextStyle(
        _ style: WTextStyle,
        content: WTextContent = .default,
        scaling: WTextScaling = .fixed
    ) {
        textProperties.font = WTypography.uiFont(
            style,
            content: content,
            scaling: scaling
        )
        textProperties.adjustsFontForContentSizeCategory = scaling == .dynamic
    }
}

private extension WTextStyle {
    var dynamicTypeStyle: WDynamicTypeStyle {
        switch self {
        case .largeTitle, .onboardingTitle:
            .largeTitle
        case .screenTitle, .startupTitle:
            .title1
        case .sectionTitle, .title2, .title2Strong:
            .title2
        case .title3, .largeSymbol, .promotionTitle, .statusTitle,
             .emptyStateTitle:
            .title3
        case .sectionHeader:
            IOS_26_MODE_ENABLED ? .headline : .footnote
        case .body, .bodyEmphasized, .bodyStrong, .bodyBold,
             .button, .capsuleButton:
            .body
        case .callout, .calloutEmphasized, .calloutStrong, .calloutBold:
            .callout
        case .subheadline, .subheadlineEmphasized, .subheadlineStrong,
             .subheadlineBold, .supporting, .supportingEmphasized,
             .supportingStrong, .supportingBold, .compactButton:
            .subheadline
        case .footnote, .footnoteEmphasized, .footnoteStrong,
             .largeBadge:
            .footnote
        case .caption, .captionEmphasized, .captionStrong, .captionBold:
            .caption1
        case .caption2, .caption2Emphasized, .caption2Strong, .micro,
             .compactBadge, .badge, .badgeEmphasized, .badgeBold:
            .caption2
        case .symbol, .symbolEmphasized, .navigationSymbol:
            .body
        case .amount, .amountSymbol, .prominentTitle:
            .title2
        case .amountSecondary:
            .title3
        }
    }

    var metrics: WTextStyleMetrics {
        switch self {
        case .largeTitle:
            WTextStyleMetrics(pointSize: 34, weight: .bold)
        case .onboardingTitle:
            WTextStyleMetrics(pointSize: 32, weight: .semibold)
        case .screenTitle:
            WTextStyleMetrics(pointSize: 28, weight: .semibold)
        case .startupTitle:
            WTextStyleMetrics(pointSize: 28, weight: .bold)
        case .sectionTitle:
            WTextStyleMetrics(pointSize: 22.5, weight: .bold)
        case .title2:
            WTextStyleMetrics(pointSize: 22, weight: .regular)
        case .title2Strong:
            WTextStyleMetrics(pointSize: 22, weight: .bold)
        case .title3:
            WTextStyleMetrics(pointSize: 20, weight: .regular)
        case .largeSymbol:
            WTextStyleMetrics(pointSize: 20, weight: .medium)
        case .promotionTitle:
            WTextStyleMetrics(pointSize: 20, weight: .heavy)
        case .statusTitle:
            WTextStyleMetrics(pointSize: 20, weight: .semibold)
        case .sectionHeader:
            if IOS_26_MODE_ENABLED {
                WTextStyleMetrics(pointSize: 17, weight: .semibold)
            } else {
                WTextStyleMetrics(pointSize: 13, weight: .regular)
            }
        case .body:
            WTextStyleMetrics(pointSize: 17, weight: .regular)
        case .bodyEmphasized:
            WTextStyleMetrics(pointSize: 17, weight: .medium)
        case .bodyStrong:
            WTextStyleMetrics(pointSize: 17, weight: .semibold)
        case .bodyBold:
            WTextStyleMetrics(pointSize: 17, weight: .bold)
        case .callout:
            WTextStyleMetrics(pointSize: 16, weight: .regular)
        case .calloutEmphasized:
            WTextStyleMetrics(pointSize: 16, weight: .medium)
        case .calloutStrong:
            WTextStyleMetrics(pointSize: 16, weight: .semibold)
        case .calloutBold:
            WTextStyleMetrics(pointSize: 16, weight: .bold)
        case .subheadline:
            WTextStyleMetrics(pointSize: 15, weight: .regular)
        case .subheadlineEmphasized:
            WTextStyleMetrics(pointSize: 15, weight: .medium)
        case .subheadlineStrong:
            WTextStyleMetrics(pointSize: 15, weight: .semibold)
        case .subheadlineBold:
            WTextStyleMetrics(pointSize: 15, weight: .bold)
        case .supporting:
            WTextStyleMetrics(pointSize: 14, weight: .regular)
        case .supportingEmphasized:
            WTextStyleMetrics(pointSize: 14, weight: .medium)
        case .supportingStrong:
            WTextStyleMetrics(pointSize: 14, weight: .semibold)
        case .supportingBold:
            WTextStyleMetrics(pointSize: 14, weight: .bold)
        case .footnote:
            WTextStyleMetrics(pointSize: 13, weight: .regular)
        case .footnoteEmphasized:
            WTextStyleMetrics(pointSize: 13, weight: .medium)
        case .footnoteStrong:
            WTextStyleMetrics(pointSize: 13, weight: .semibold)
        case .caption:
            WTextStyleMetrics(pointSize: 12, weight: .regular)
        case .captionEmphasized:
            WTextStyleMetrics(pointSize: 12, weight: .medium)
        case .captionStrong:
            WTextStyleMetrics(pointSize: 12, weight: .semibold)
        case .captionBold:
            WTextStyleMetrics(pointSize: 12, weight: .bold)
        case .caption2:
            WTextStyleMetrics(pointSize: 11, weight: .regular)
        case .caption2Emphasized:
            WTextStyleMetrics(pointSize: 11, weight: .medium)
        case .caption2Strong:
            WTextStyleMetrics(pointSize: 11, weight: .semibold)
        case .micro:
            WTextStyleMetrics(pointSize: 10, weight: .regular)
        case .compactBadge:
            WTextStyleMetrics(pointSize: 9, weight: .semibold)
        case .badge:
            WTextStyleMetrics(pointSize: 10, weight: .semibold)
        case .badgeEmphasized:
            WTextStyleMetrics(pointSize: 10, weight: .medium)
        case .badgeBold:
            WTextStyleMetrics(pointSize: 10, weight: .bold)
        case .largeBadge:
            WTextStyleMetrics(pointSize: 13, weight: .semibold)
        case .symbol:
            WTextStyleMetrics(pointSize: 18, weight: .regular)
        case .symbolEmphasized:
            WTextStyleMetrics(pointSize: 18, weight: .medium)
        case .navigationSymbol:
            WTextStyleMetrics(pointSize: 23, weight: .medium)
        case .button:
            WTextStyleMetrics(pointSize: 17, weight: .semibold)
        case .capsuleButton:
            WTextStyleMetrics(pointSize: 17, weight: .medium)
        case .compactButton:
            WTextStyleMetrics(pointSize: 15, weight: .medium)
        case .amount:
            WTextStyleMetrics(pointSize: 24, weight: .semibold)
        case .amountSecondary:
            WTextStyleMetrics(pointSize: 20, weight: .semibold)
        case .amountSymbol:
            WTextStyleMetrics(pointSize: 24, weight: .medium)
        case .prominentTitle:
            WTextStyleMetrics(pointSize: 24, weight: .semibold)
        case .emptyStateTitle:
            WTextStyleMetrics(pointSize: 20, weight: .bold)
        }
    }
}

private struct WTextStyleMetrics {
    let pointSize: CGFloat
    let weight: WTextWeight
}

private enum WDynamicTypeStyle {
    case largeTitle
    case title1
    case title2
    case title3
    case headline
    case body
    case callout
    case subheadline
    case footnote
    case caption1
    case caption2

    var uiKitTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption1: .caption1
        case .caption2: .caption2
        }
    }

    var swiftUITextStyle: Font.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title1: .title
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption1: .caption
        case .caption2: .caption2
        }
    }
}

private enum WTextWeight {
    case regular
    case medium
    case semibold
    case bold
    case heavy

    var uiFontWeight: UIFont.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    var swiftUIFontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    var vazirmatnFontName: String {
        switch self {
        case .regular: "Vazirmatn-Regular"
        case .medium: "Vazirmatn-Medium"
        case .semibold: "Vazirmatn-SemiBold"
        case .bold: "Vazirmatn-Bold"
        case .heavy: "Vazirmatn-Bold"
        }
    }
}
