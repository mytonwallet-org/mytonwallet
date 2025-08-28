
import UIKit
import SwiftUI

extension UIImage {
    public static func airBundle(_ named: String) -> UIImage {
        UIImage(named: named, in: AirBundle, compatibleWith: nil)!
    }
}

extension Image {
    public static func airBundle(_ name: String) -> Image {
        Image(name, bundle: AirBundle)
    }
}
