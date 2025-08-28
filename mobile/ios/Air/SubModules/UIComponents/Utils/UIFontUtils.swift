//
//  UIFontUtils.swift
//  UIComponents
//
//  Created by Sina on 5/10/24.
//

import UIKit
import WalletContext

public extension UIFont {
    
    class func registerAirFonts() {
        if UIFont(name: "SFCompactRounded-Medium", size: 17) == nil {
            UIFont.registerFont(withFilenameString: "SFCompactDisplayMedium.otf", bundle: AirBundle)
            UIFont.registerFont(withFilenameString: "SFCompactRoundedBold.otf", bundle: AirBundle)
            UIFont.registerFont(withFilenameString: "SFCompactRoundedSemibold.otf", bundle: AirBundle)
            UIFont.registerFont(withFilenameString: "SFCompactRoundedMedium.otf", bundle: AirBundle)
        }
    }
    
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

    static func registerFont(withFilenameString filenameString: String, bundle: Bundle) {
        guard let pathForResourceString = bundle.path(forResource: filenameString, ofType: nil) else {
            assertionFailure("UIFont+:  Failed to register font - path for resource not found.")
            return
        }
        
        guard let fontData = NSData(contentsOfFile: pathForResourceString) else {
            assertionFailure("UIFont+:  Failed to register font - font data could not be loaded.")
            return
        }
        
        guard let dataProvider = CGDataProvider(data: fontData) else {
            assertionFailure("UIFont+:  Failed to register font - data provider could not be loaded.")
            return
        }
        
        guard let font = CGFont(dataProvider) else {
            assertionFailure("UIFont+:  Failed to register font - font could not be loaded.")
            return
        }
        
        var errorRef: Unmanaged<CFError>? = nil
        if (CTFontManagerRegisterGraphicsFont(font, &errorRef) == false) {
            assertionFailure("UIFont+:  Failed to register font - register graphics font failed - this font may have already been registered in the main bundle.")
        }
    }
    
}
