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
    
    /// Sidebar background in iPad split layout.
    public var sidebarBackground: UIColor
    
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

public func getAccentColorByIndex(_ index: Int?) -> UIColor {
    if let index, index < ACCENT_COLORS.count {
        ACCENT_COLORS[index]
    } else {
        UIColor.airBundle("TC1_PrimaryColor")
    }
}

// This method changes WTheme to a new theme with customized colors
public func changeThemeColors(to index: Int?) {
    let accentColor = getAccentColorByIndex(index)
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
        sidebarBackground: WColors.sidebarBackground,
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

// MARK: - Themed views
public protocol WThemedView: AnyObject {
    @MainActor func updateTheme()
}
