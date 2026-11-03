import UIKit

extension UIColor {
    /// The color `progress` of the way from this color to `color`, in sRGB components
    public func interpolate(to color: UIColor, progress: CGFloat) -> UIColor {
        let progress = min(1, max(0, progress))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var targetRed: CGFloat = 0, targetGreen: CGFloat = 0, targetBlue: CGFloat = 0, targetAlpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              color.getRed(&targetRed, green: &targetGreen, blue: &targetBlue, alpha: &targetAlpha) else {
            return progress < 0.5 ? self : color
        }
        return UIColor(
            red: red + (targetRed - red) * progress,
            green: green + (targetGreen - green) * progress,
            blue: blue + (targetBlue - blue) * progress,
            alpha: alpha + (targetAlpha - alpha) * progress
        )
    }

    /// Whether the two colors match in sRGB components within `tolerance`
    public func isApproximatelyEqual(to color: UIColor, tolerance: CGFloat = 0.004) -> Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        var otherRed: CGFloat = 0, otherGreen: CGFloat = 0, otherBlue: CGFloat = 0, otherAlpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              color.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha) else { return false }
        return abs(red - otherRed) <= tolerance && abs(green - otherGreen) <= tolerance
            && abs(blue - otherBlue) <= tolerance && abs(alpha - otherAlpha) <= tolerance
    }
}
