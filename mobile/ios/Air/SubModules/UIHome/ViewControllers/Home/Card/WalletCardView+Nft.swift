
import Foundation
import UIKit
import WalletCore
import WalletContext

internal extension ApiNft {
    
    struct GradientColors {
        let startColor: UIColor
        let endColor: UIColor
        let startPoint: CGFloat?
    }
    
    func gradientColors() -> GradientColors {
        switch self.metadata?.mtwCardType {
        case .black:
            return GradientColors(
                startColor: UIColor(white: 1, alpha: 0.5),
                endColor: UIColor(white: 1, alpha: 0.15),
                startPoint: nil
            )
        case .platinum:
            return GradientColors(
                startColor: UIColor(hex: "#FFFFFF"),
                endColor: UIColor(hex: "#888891"),
                startPoint: nil
            )
        case .gold:
            return GradientColors(
                startColor: UIColor(hex: "#694D13"),
                endColor: UIColor(hex: "#B07D1D"),
                startPoint: nil
            )
        case .silver:
            return GradientColors(
                startColor: UIColor(hex: "#272727"),
                endColor: UIColor(hex: "#989898"),
                startPoint: nil
            )
        case .standard, nil:
            let color = switch self.metadata?.mtwCardTextType {
            case .light, nil:
                UIColor.white
            case .dark:
                UIColor.black
            }
            return GradientColors(startColor: color, endColor: color, startPoint: nil)
        }
    }
    
    func gradientColor(in rect: CGRect) -> UIColor? {
        var rect = rect
        if rect.width == 0 || rect.height == 0 {
            rect = defaultGradientRect
        }
        
        let colors = gradientColors()
        
        if colors.startColor == colors.endColor {
            return colors.startColor
        }
        
        return UIColor.gradientColor(
            in: rect,
            colors: [colors.startColor.cgColor, colors.endColor.cgColor],
            start: colors.startPoint ?? 0
        )
    }
}

