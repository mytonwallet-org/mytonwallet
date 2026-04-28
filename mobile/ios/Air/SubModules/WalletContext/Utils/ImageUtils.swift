
import UIKit
import SwiftUI

extension UIImage {
    public static func airBundle(_ named: String) -> UIImage {
        UIImage(named: named, in: AirBundle, compatibleWith: nil)!
    }

    public static func airBundleOptional(_ named: String) -> UIImage? {
        UIImage(named: named, in: AirBundle, compatibleWith: nil)
    }

    public static func mainBundle(_ named: String) -> UIImage {
        UIImage(named: named, in: .main, compatibleWith: nil)!
    }

    public static func mainBundleOptional(_ named: String) -> UIImage? {
        UIImage(named: named, in: .main, compatibleWith: nil)
    }

    /// Resizes the image (useful in SwiftUI Text where .font() does not scale asset images).
    /// Uses aspect fit to preserve proportions.
    public func resizedToFit(size: CGSize) -> UIImage {
        let imageSize = self.size
        let widthRatio = size.width / imageSize.width
        let heightRatio = size.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let scaledSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (size.width - scaledSize.width) / 2,
            y: (size.height - scaledSize.height) / 2
        )
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }
}

extension Image {
    public static func airBundle(_ name: String) -> Image {
        Image(name, bundle: AirBundle)
    }
}
