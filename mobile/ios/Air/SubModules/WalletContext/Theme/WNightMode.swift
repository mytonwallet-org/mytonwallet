//
//  WNightMode.swift
//  WalletContext
//
//  Created by Sina on 7/3/24.
//

import Foundation
import UIKit

public enum NightMode: String, Equatable, Hashable, Codable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    public var image: UIImage {
        switch self {
        case .system:
            return UIImage(named: "SystemTheme", in: AirBundle, compatibleWith: nil)!
        case .light:
            return UIImage(named: "LightTheme", in: AirBundle, compatibleWith: nil)!
        case .dark:
            return UIImage(named: "DarkTheme", in: AirBundle, compatibleWith: nil)!
        }
    }
    
    public var text: String {
        switch self {
        case .system:
            return lang("System")
        case .light:
            return lang("Light")
        case .dark:
            return lang("Dark")
        }
    }
    
    public var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        case .system:
            return .unspecified
        }
    }

    public var traitCollection: UITraitCollection {
        switch self {
        case .dark:
            return UITraitCollection(userInterfaceStyle: .dark)
        case .system:
            return UITraitCollection.current
        case .light:
            return UITraitCollection(userInterfaceStyle: .light)
        }
    }
}

public enum ResolvedTheme: String, Codable {
    case light = "light"
    case dark = "dark"
}

public extension ResolvedTheme {
    init(traitCollection: UITraitCollection) {
        self = traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}
