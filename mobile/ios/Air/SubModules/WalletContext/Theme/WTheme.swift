//
//  WTheme.swift
//  WalletContext
//
//  Created by Sina on 3/16/24.
//

import UIKit

// MARK: - Theme structure
public struct WThemePrimaryButton {
    public var background: UIColor
    public var tint: UIColor
    public var disabledBackground: UIColor
    public var disabledTint: UIColor
}

public struct WThemeAccentButton {
    public var background: UIColor
    public var tint: UIColor
}

public struct WThemeUnlockScreen {
    public var background: UIColor
    public var tint: UIColor
}

public struct WThemePasscodeInput {
    public var border: UIColor
    public var empty: UIColor
    public var fill: UIColor
    public var fillBorder: UIColor?
}

public struct WThemeWordInput {
    public var background: UIColor
}

public struct WThemeBackgroundHeaderView {
    public var background: UIColor
    public var headIcons: UIColor
    public var balance: UIColor
    public var balanceDecimals: UIColor
    public var secondary: UIColor
    public var skeleton: UIColor
}

public struct _WThemeType {
    public var primaryButton: WThemePrimaryButton
    public var accentButton: WThemeAccentButton
    public var unlockScreen: WThemeUnlockScreen
    public var setPasscodeInput: WThemePasscodeInput
    public var unlockPasscodeInput: WThemePasscodeInput
    public var unlockTaskPasscodeInput: WThemePasscodeInput
    public var wordInput: WThemeWordInput
    public var balanceHeaderView: WThemeBackgroundHeaderView
    
    /// White/black. Used for background in full-screen views.
    public var background: UIColor
    
    /// Light gray/black. Used for background of grouped lists such as Home and Settings.
    public var groupedBackground: UIColor
    
    ///  Light gray/dark gray. Used for sheets background.
    public var sheetBackground: UIColor
    
    /// White/dark gray. Used for grouped list cells.
    public var groupedItem: UIColor
    
    /// White/dark gray. Used for alerts and similar modular components.
    public var modularBackground: UIColor
    
    public var backgroundReverse: UIColor
    public var thumbBackground: UIColor
    public var tint: UIColor

    public var primaryLabel: UIColor
    public var secondaryLabel: UIColor
    public var secondaryFill: UIColor

    public let sheetOpaqueBar: UIColor
    public let browserOpaqueBar: UIColor
    public let pickerBackground: UIColor
    public var separator: UIColor
    public var separatorDarkBackground: UIColor
    public var border: UIColor
    public var highlight: UIColor
    public let menuBackground: UIColor
    public var positiveAmount: UIColor
    public var negativeAmount: UIColor
    public var error: UIColor
}

// MARK: - Theme and Theme generator
nonisolated(unsafe) public var WTheme: _WThemeType = generateTheme()

// This method changes WTheme to a new theme with customized colors
public func changeThemeColors(to index: Int?) {
    let accentColor: UIColor = if let index, index < ACCENT_COLORS.count {
        ACCENT_COLORS[index]
    } else {
        UIColor.airBundle("TC1_PrimaryColor")
    }
    WColors = _WColorsType(primary: accentColor)
    WTheme = generateTheme()
}

// Generate active theme using WColors
fileprivate func generateTheme() -> _WThemeType {
    return _WThemeType(
        primaryButton: WThemePrimaryButton(background: WColors.primary,
                                           tint: .white,
                                           disabledBackground: WColors.primary.withAlphaComponent(0.5),
                                           disabledTint: .white),
        accentButton: WThemeAccentButton(background: WColors.groupedItem,
                                         tint: WColors.primary),
        unlockScreen: WThemeUnlockScreen(background: WColors.primary,
                                         tint: .white),
        setPasscodeInput: WThemePasscodeInput(border: .separator,
                                              empty: WColors.background,
                                              fill: .label),
        unlockPasscodeInput: WThemePasscodeInput(border: .white,
                                                 empty: .clear,
                                                 fill: .white),
        unlockTaskPasscodeInput: WThemePasscodeInput(border: WColors.secondaryLabel,
                                                     empty: .clear,
                                                     fill: WColors.primary,
                                                     fillBorder: .clear),
        wordInput: WThemeWordInput(background: WColors.sheetBackground),
        balanceHeaderView: WThemeBackgroundHeaderView(background: WColors.headerBackground,
                                                      headIcons: WColors.primary,
                                                      balance: .label,
                                                      balanceDecimals: WColors.secondaryLabel,
                                                      secondary: WColors.headerSecondaryLabel,
                                                      skeleton: WColors.headerSkeleton),
        background: WColors.background,
        groupedBackground: WColors.groupedBackground,
        sheetBackground: WColors.sheetBackground,
        groupedItem: WColors.groupedItem,
        modularBackground: WColors.modularBackground,
        backgroundReverse: WColors.backgroundReverse,
        thumbBackground: WColors.thumbBackground,
        tint: WColors.primary,
        primaryLabel: .label,
        secondaryLabel: WColors.secondaryLabel,
        secondaryFill: WColors.secondaryFill,
        sheetOpaqueBar: WColors.sheetOpaqueBar,
        browserOpaqueBar: WColors.browserOpaqueBar,
        pickerBackground: WColors.pickerBackground,
        separator: WColors.separator,
        separatorDarkBackground: WColors.separatorDarkBackground,
        border: .separator,
        highlight: WColors.highlight,
        menuBackground: WColors.modularBackground,
        positiveAmount: .airBundle("TextGreen"),
        negativeAmount: .airBundle("TextRed"),
        error: .airBundle("TextRed")
    )
}

// MARK: - Available customized themes
public struct WAppearanceThemeColorsType {
    public let id: Int
    public let primary: UIColor
}

public var WAppearanceThemeColors: [WAppearanceThemeColorsType] = [
    WAppearanceThemeColorsType(
        id: 1,
        primary: UIColor(named: "TC1_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 2,
        primary: UIColor(named: "TC2_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 3,
        primary: UIColor(named: "TC3_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 4,
        primary: UIColor(named: "TC4_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 5,
        primary: UIColor(named: "TC5_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 6,
        primary: UIColor(named: "TC6_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 7,
        primary: UIColor(named: "TC7_PrimaryColor", in: AirBundle, compatibleWith: nil)!
    ),
    WAppearanceThemeColorsType(
        id: 8,
        primary: UIColor(red: 1, green: 0.69, blue: 0.48, alpha: 1)
    ),
    WAppearanceThemeColorsType(
        id: 9,
        primary: UIColor(red: 0.72, green: 0.43, blue: 0.47, alpha: 1)
    ),
    WAppearanceThemeColorsType(
        id: 10,
        primary: UIColor(red: 0.59, green: 0.54, blue: 0.82, alpha: 1)
    ),
    WAppearanceThemeColorsType(
        id: 11,
        primary: UIColor(red: 0.9, green: 0.45, blue: 0.8, alpha: 1)
    ),
    WAppearanceThemeColorsType(
        id: 12,
        primary: UIColor(red: 0.42, green: 0.63, blue: 0.48, alpha: 1)
    ),
    WAppearanceThemeColorsType(
        id: 13,
        primary: UIColor(red: 0.2, green: 0.56, blue: 0.8, alpha: 1)
    ),
    WAppearanceThemeColorsType(
        id: 14,
        primary: .label
    )
]

// MARK: - Themed views
public protocol WThemedView: AnyObject {
    @MainActor func updateTheme()
}
