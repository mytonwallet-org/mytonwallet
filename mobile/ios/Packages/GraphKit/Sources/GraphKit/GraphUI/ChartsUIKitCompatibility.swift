import UIKit

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        let red = CGFloat((rgb >> 16) & 0xff) / 255.0
        let green = CGFloat((rgb >> 8) & 0xff) / 255.0
        let blue = CGFloat(rgb & 0xff) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

final class HapticFeedback {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    func tap() {
        generator.impactOccurred()
    }
}

extension CALayer {
    func addShakeAnimation() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [-8.0, 8.0, -6.0, 6.0, -3.0, 3.0, 0.0]
        animation.duration = 0.32
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        add(animation, forKey: "charts.shake")
    }
}

enum ChartImageFactory {
    static func chevronLeft(color: UIColor) -> UIImage? {
        makeChevron(systemName: "chevron.left", color: color)
    }

    static func chevronRight(color: UIColor) -> UIImage? {
        makeChevron(systemName: "chevron.right", color: color)
    }

    private static func makeChevron(systemName: String, color: UIColor) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 12.0, weight: .semibold)
        return UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal)
    }
}
