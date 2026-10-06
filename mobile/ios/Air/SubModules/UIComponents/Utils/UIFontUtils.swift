import UIKit
import SwiftUI

public extension UIFont {
    
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
    static func calSans(size: CGFloat) -> Font {
        let font = UIFont(name: "CalSans-Regular", size: size)!
        return Font(font)
    }
}
