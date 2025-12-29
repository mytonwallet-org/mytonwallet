//
//  UIFontUtils.swift
//  UIComponents
//
//  Created by Sina on 5/10/24.
//

import UIKit
import SwiftUI
import WalletContext

public extension UIFont {
    
    class func compact(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "SFCompactDisplay-Medium", size: size)!
    }
    
    class func rounded(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        switch weight {
        case .bold:
            return UIFont(name: "SFCompactRounded-Bold", size: size)!
        case .semibold:
            return UIFont(name: "SFCompactRounded-Semibold", size: size)!
        default:
            return UIFont(name: "SFCompactRounded-Medium", size: size)!
        }
    }
    
    class func roundedNative(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        let font: UIFont
        
        if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        } else {
            font = systemFont
        }
        return font
    }
}

public extension Font {
    static func nunito(size: CGFloat) -> Font {
        let font = UIFont(name: "Nunito-ExtraBold", size: size)!
        return Font(font)
    }
    
    static func compactMedium(size: CGFloat) -> Font {
        let font = UIFont(name: "SFCompactDisplay-Medium", size: size)!
        return Font(font)
    }
}
