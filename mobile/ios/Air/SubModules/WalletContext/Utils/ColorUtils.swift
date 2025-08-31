//
//  ColorUtils.swift
//  WalletContext
//
//  Created by Sina on 3/16/24.
//

import UIKit
import ColorThiefSwift

private let log = Log("ColorUtils")


public extension UIColor {
    convenience init(hex hexString: String, alpha: CGFloat) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: alpha)
    }
    convenience init(hex hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: 1.0)
    }
    var alpha: CGFloat? {
        var alpha: CGFloat = .zero
        return getRed(nil, green: nil, blue: nil, alpha: &alpha) ? alpha : nil
    }

    convenience init(light: String, dark: String) {
        self.init { $0.userInterfaceStyle != .dark ? UIColor(hex: light) : UIColor(hex: dark) }
    }
}


extension UIImage {
    public func extractColor() -> UIColor? {
        assert(!Thread.isMainThread, "This method takes nontrivial amount of time and should not be called from the main thread")
        guard let color = ColorThief.getColor(from: self, quality: 10, ignoreWhite: true) else {
            log.error("Color extraction failed. Most likely image is empty: \(self, .public)")
            return nil
        }
        return color.makeUIColor()
    }
}

extension UIColor {
    func distance(to other: UIColor) -> CGFloat {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let color1 = self.resolvedColor(with: light)
        let color2 = other.resolvedColor(with: light)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        color1.getRed(&r1, green: &g1, blue: &b1, alpha: nil)
        color2.getRed(&r2, green: &g2, blue: &b2, alpha: nil)

        return sqrt(pow(abs(r1 - r2), 2) + pow(abs(g1 - g2), 2) + pow(abs(b1 - b2), 2))
    }
}


extension UIColor {
    public static func gradientColor(in rect: CGRect, colors: [CGColor], start: CGFloat = 0) -> UIColor? {
        let image = UIGraphicsImageRenderer(bounds: rect).image { renderer in
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) {
                renderer.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: start, y: 0),
                    end: CGPoint(x: rect.width, y: 0),
                    options: [.drawsBeforeStartLocation]
                )
            }
        }
        return UIColor(patternImage: image)
    }
}
