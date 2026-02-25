import UIKit
import SwiftUI

public enum CompactDisplayWeight {
    case medium
}

public enum CompactRoundedWeight {
    case bold
    case semibold
}

public extension UIFont {
    
    class func compactRounded(ofSize size: CGFloat, weight: CompactRoundedWeight) -> UIFont {
        switch weight {
        case .bold: UIFont(name: "SFCompactRounded-Bold", size: size)!
        case .semibold: UIFont(name: "SFCompactRounded-Semibold", size: size)!
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
    
    static func compactDisplay(size: CGFloat, weight: CompactDisplayWeight) -> Font {
        switch weight {
        case .medium: Font(UIFont(name: "SFCompactDisplay-Medium", size: size)!)
        }
    }
    
    static func compactRounded(size: CGFloat, weight: CompactRoundedWeight) -> Font {
        Font(UIFont.compactRounded(ofSize: size, weight: weight))
    }
}
