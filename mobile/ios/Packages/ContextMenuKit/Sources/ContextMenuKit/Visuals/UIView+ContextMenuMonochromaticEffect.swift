import UIKit

extension UIView {
    func setContextMenuMonochromaticEffect(tintColor: UIColor?) {
        var overrideStyle: UIUserInterfaceStyle = .unspecified
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 1.0
        if let tintColor, tintColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            if red == 0.0, green == 0.0, blue == 0.0, alpha == 1.0 {
                overrideStyle = .light
            } else if red == 1.0, green == 1.0, blue == 1.0, alpha == 1.0 {
                overrideStyle = .dark
            }
        }

        if self.overrideUserInterfaceStyle != overrideStyle {
            self.overrideUserInterfaceStyle = overrideStyle
        }

        guard #available(iOS 26.1, *), overrideStyle != .unspecified else {
            return
        }

        let selectors: [(Selector, NSNumber)] = [
            (ContextMenuPrivateMonochromaticRuntime.setAllowsTreatmentSelector, NSNumber(value: true)),
            (ContextMenuPrivateMonochromaticRuntime.setEnableTreatmentSelector, NSNumber(value: true)),
            (ContextMenuPrivateMonochromaticRuntime.setTreatmentSelector, NSNumber(value: 2))
        ]
        for (selector, value) in selectors {
            ContextMenuPrivateMonochromaticRuntime.setProperty(value, selector: selector, on: self)
        }
    }
}
