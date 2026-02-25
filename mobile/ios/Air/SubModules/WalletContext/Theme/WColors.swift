//
//  WColors.swift
//  WalletContext
//
//  Created by Sina on 3/16/24.
//

import UIKit
import SwiftUI


public extension UIColor {
    static func airBundle(_ named: String) -> UIColor {
        UIColor(named: named, in: AirBundle, compatibleWith: nil)!
    }
}

public extension Color {
    static func airBundle(_ named: String) -> Color {
        Color(named, bundle: AirBundle)
    }
}

private let ACCENT_COLORS_LIGHT: [String] = [
    "#31AFC7", "#35C759", "#FF9500", "#FF2C55",
    "#AF52DE", "#5856D7", "#73AAED", "#FFB07A",
    "#B76C78", "#9689D1", "#E572CC", "#6BA07A",
    "#338FCC", "#1FC863", "#929395", "#E4B102",
]
private let ACCENT_COLORS_DARK: [String] = [
    "#3AB5CC", "#32D74B", "#FF9F0B", "#FF325A",
    "#BF5AF2", "#7977FF", "#73AAED", "#FFB07A",
    "#B76C78", "#9689D1", "#E572CC", "#6BA07A",
    "#338FCC", "#2CD36F", "#C3C5C6", "#DDBA00",
]

public let ACCENT_COLORS: [UIColor] = zip(ACCENT_COLORS_LIGHT, ACCENT_COLORS_DARK).map { UIColor(light: $0, dark: $1) } + [UIColor.label]

public let ACCENT_RADIOACTIVE_INDEX = 13
public let ACCENT_SILVER_INDEX = 14
public let ACCENT_GOLD_INDEX = 15
public let ACCENT_BNW_INDEX = 16

public func closestAccentColor(for color: UIColor) -> UIColor {
    ACCENT_COLORS.min(by: { $0.distance(to: color) < $1.distance(to: color) })!
}

public struct _WColorsType {
    
    var primary: UIColor
    
    public let background: UIColor = .airBundle("BackgroundColor")
    
    public let groupedBackground: UIColor = .airBundle("GroupedBackgroundColor")
    let sidebarBackground: UIColor = .airBundle("SidebarBackgroundColor")

    let groupedItem: UIColor = .airBundle("GroupedItemColor")
    public let sheetBackground: UIColor = .airBundle("SheetBackgroundColor")
    let modularBackground: UIColor = .airBundle("ModularBackgroundColor")

    let backgroundReverse: UIColor = .airBundle("BackgroundReverseColor")
    public let thumbBackground: UIColor = .airBundle("ThumbBackgroundColor")
    
    let secondaryLabel: UIColor = .airBundle("AirSecondaryLabelColor")
    let secondaryFill: UIColor = .airBundle("SecondaryFillColor")
    public let folderFill: UIColor = .airBundle("FolderFillColor")
    
    let separator: UIColor = .airBundle("AirSeparatorColor")
    let separatorDarkBackground: UIColor = .airBundle("AirSeparatorDarkBackgroundColor")
    
    let headerBackground: UIColor = .airBundle("HeaderBackgroundColor")
    public let headerSecondaryLabel: UIColor = .airBundle("HeaderSecondaryLabelColor")
    let headerSkeleton: UIColor = .airBundle("HeaderSkeletonColor")
    
    public let highlight: UIColor = .airBundle("HighlightColor")
    public let altHighlight: UIColor = .airBundle("AltHighlightColor")
    
    let sheetOpaqueBar: UIColor = .airBundle("SheetOpaqueBarColor")
    let browserOpaqueBar: UIColor = .airBundle("BrowserOpaqueBarColor")
    let pickerBackground: UIColor = .airBundle("PickerBackgroundColor")
    public let blurBackground: UIColor = .airBundle("BlurBackgroundColor")
    public let blurDim: UIColor = .airBundle("BlurDimColor")
    public let textPurple: UIColor = .airBundle("TextPurple")
    public let activityNftFill: UIColor = .airBundle("ActivityNftFill")
    
    public let gradients = [
        [#colorLiteral(red: 1, green: 0.5333333611, blue: 0.3686274588, alpha: 1).cgColor, #colorLiteral(red: 1, green: 0.3176470697, blue: 0.4156863093, alpha: 1).cgColor],
        [#colorLiteral(red: 1, green: 0.8039215803, blue: 0.4156863093, alpha: 1).cgColor, #colorLiteral(red: 1, green: 0.6588235497, blue: 0.360784322, alpha: 1).cgColor],
        [#colorLiteral(red: 0.6274510026, green: 0.870588243, blue: 0.4941176474, alpha: 1).cgColor, #colorLiteral(red: 0.3294117749, green: 0.7960784435, blue: 0.4078431427, alpha: 1).cgColor],
        [#colorLiteral(red: 0.3254902065, green: 0.9294118285, blue: 0.8392157555, alpha: 1).cgColor, #colorLiteral(red: 0.1568627506, green: 0.7882353067, blue: 0.7176470757, alpha: 1).cgColor],
        [#colorLiteral(red: 0.4470588267, green: 0.8352941275, blue: 0.9921568632, alpha: 1).cgColor, #colorLiteral(red: 0.1647058874, green: 0.6196078658, blue: 0.9450980425, alpha: 1).cgColor],
        [#colorLiteral(red: 0.5098039508, green: 0.6941176653, blue: 1, alpha: 1).cgColor, #colorLiteral(red: 0.4, green: 0.3725490272, blue: 1, alpha: 1).cgColor],
        [#colorLiteral(red: 0.8784313798, green: 0.6352941394, blue: 0.9529411793, alpha: 1).cgColor, #colorLiteral(red: 0.8392156959, green: 0.4117647111, blue: 0.9294117689, alpha: 1).cgColor]
    ]
    
    public var redGradient: [UIColor] = [
        UIColor.airBundle("RedGradient0"),
        UIColor.airBundle("RedGradient1"),
    ]
    public var greenGradient: [UIColor] = [
        UIColor.airBundle("GreenGradient0"),
        UIColor.airBundle("GreenGradient1"),
    ]
    public var blueGradient: [UIColor] = [
        UIColor.airBundle("BlueGradient0"),
        UIColor.airBundle("BlueGradient1"),
    ]
    public var grayGradient: [UIColor] = [
        UIColor.airBundle("GrayGradient0"),
        UIColor.airBundle("GrayGradient1"),
    ]
    public var indigoGradient: [UIColor] = [
        UIColor.airBundle("PurpleGradient0"),
        UIColor.airBundle("PurpleGradient1"),
    ]
    
    init(primary: UIColor) {
        self.primary = primary
    }
}

public var WColors: _WColorsType = _WColorsType(primary: .airBundle("TC1_PrimaryColor"))

public extension UIColor {
    static var air: _WColorsType { WColors }
}


public extension Color {
    struct Air {
        public let checkmarkDisabled: Color = .airBundle("CheckmarkDisabledColor")
        public let menuSeparator: Color = .airBundle("MenuSeparator")
        public let menuWideSeparator: Color = .airBundle("MenuWideSeparator")
        public let primaryLabel: Color = Color(UIColor.label)
        public let secondaryLabel: Color = .airBundle("AirSecondaryLabelColor")
        public let groupedItem: Color = .airBundle("GroupedItemColor")
        public let groupedBackground: Color = .airBundle("GroupedBackgroundColor")
        public let background: Color = .airBundle("BackgroundColor")
        public let sidebarBackground: Color = .airBundle("SidebarBackgroundColor")
        public let sheetBackground: Color = .airBundle("SheetBackgroundColor")
        public let highlight: Color = .airBundle("HighlightColor")
        public let altHighlight: Color = .airBundle("AltHighlightColor")
        public let secondaryFill: Color = .airBundle("SecondaryFillColor")
        public let error: Color = .red
        public let folderFill: Color = .airBundle("FolderFillColor")
      
        public var tint: Color { Color(WTheme.tint) }
    }
    
    static let air = Air()
}
