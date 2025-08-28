import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let BORDER_WIDTH: CGFloat = 1
private let BLACK_CARD_BORDER_WIDTH: CGFloat = 1.667

private let LINEAR_GRADIENT_COLORS = [
    UIColor(hex: "8C94B0", alpha: 0.5).cgColor,
    UIColor(hex: "BABCC2", alpha: 0.85).cgColor
]
private let BLACK_CARD_LINEAR_GRADIENT_COLORS = [
    UIColor(hex: "141518", alpha: 1.0).cgColor,
    UIColor(hex: "292929", alpha: 1.0).cgColor,
]
private let RADIOACTIVE_LINEAR_GRADIENT_COLORS = [
    UIColor(hex: "5CE850", alpha: 1.0).cgColor,
    UIColor(hex: "5CE850", alpha: 1.0).cgColor, // same color, no gradient
]
private let LINEAR_GRADIENT_START_POINT = CGPoint(x: 1, y: 0.4)
private let LINEAR_GRADIENT_END_POINT = CGPoint(x: 0, y: 0.6)
private let LINEAR_GRADIENT_LOCATIONS: [NSNumber] = [0.30, 0.45]
private let SHINE_COLORS = [
    UIColor(white: 1, alpha: 1).cgColor,
    UIColor(white: 1, alpha: 0).cgColor
]


final class CardBorder: WTouchPassView {
    
    private let linearGradient = CAGradientLayer()
    private let radialGradient = CAGradientLayer()
    
    private var currentNft: ApiNft?
    private var currentState: WalletCardView.State = .expanded
    
    private var shineType: ApiMtwCardBorderShineType? {
        if let shineType = currentNft?.metadata?.mtwCardBorderShineType {
            return shineType
        }
        if cardType?.isPremium == true {
            return .up
        }
        return nil
    }
    private var cardType: ApiMtwCardType? { currentNft?.metadata?.mtwCardType }
    private var borderWidth: CGFloat { cardType == .black ? BLACK_CARD_BORDER_WIDTH : BORDER_WIDTH }
    private var linearGradientColors: [CGColor] {
        if shineType == .radioactive {
            RADIOACTIVE_LINEAR_GRADIENT_COLORS
        } else {
            switch cardType {
            case .standard, .platinum, .gold, .silver, nil:
                LINEAR_GRADIENT_COLORS
            case .black:
                BLACK_CARD_LINEAR_GRADIENT_COLORS
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        backgroundColor = .clear
        clipsToBounds = true
        
        linearGradient.locations = LINEAR_GRADIENT_LOCATIONS
        linearGradient.startPoint = LINEAR_GRADIENT_START_POINT
        linearGradient.endPoint = LINEAR_GRADIENT_END_POINT
        layer.addSublayer(linearGradient)
        
        radialGradient.type = .radial
        radialGradient.colors = SHINE_COLORS
        radialGradient.locations = [0.0, 1.0]
        radialGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        radialGradient.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(radialGradient)
    }
    
    func update(accountId: String?, nft: ApiNft?) {
        self.currentNft = nft
        updateBorder()
        applyBorderMask()
    }
    
    func update(state: WalletCardView.State) {
        currentState = state
        if state == .collapsed {
            UIView.performWithoutAnimation {
                updateBorder()
                applyBorderMask()
            }
        } else {
            updateBorder()
            applyBorderMask()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = superview?.layer.cornerRadius ?? 16
        
        linearGradient.frame = bounds
        
        radialGradient.bounds = bounds
        radialGradient.position = bounds.center
        radialGradient.transform = shineTransform
        
        applyBorderMask()
    }
    
    private var shineTransform: CATransform3D {
        
        var transform = CATransform3DIdentity
        
        // translation to border
        let initialCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let translationX = borderPoint.x - initialCenter.x
        let translationY = borderPoint.y - initialCenter.y
        transform = CATransform3DTranslate(transform, translationX, translationY, 0)

        // rotate
        transform = CATransform3DRotate(transform, rotationAngle, 0, 0, 1)
        
        // scale
        transform = CATransform3DScale(transform, 1.0, 1.2, 1.0)

        return transform
    }
    
    private var borderPoint: CGPoint {
        switch shineType {
        case .up:
            CGPoint(x: 0.85 * bounds.width, y: 0    * bounds.height)
        case .down:
            CGPoint(x: 0.45 * bounds.width, y: 1    * bounds.height)
        case .left:
            CGPoint(x: 0    * bounds.width, y: 0.45 * bounds.height)
        case .right:
            CGPoint(x: 1    * bounds.width, y: 0.55 * bounds.height)
        case .radioactive, nil:
            .zero
        @unknown default:
            .zero
        }
    }
    
    private var rotationAngle: CGFloat {
        switch shineType {
        case .up:
            CGFloat.pi * -0.25
        case .down:
            CGFloat.pi * -0.45
        case .left:
            CGFloat.pi * 0.05
        case .right:
            CGFloat.pi * 0.05
        case .radioactive, nil:
            .zero
        @unknown default:
            .zero
        }
    }
    
    private func updateBorder() {
        let shouldShowBorder = currentState == .expanded && cardType != nil
        self.isHidden = !shouldShowBorder
        if shouldShowBorder {
            // linear
            linearGradient.opacity = 1
            linearGradient.colors = linearGradientColors

            // radial
            switch shineType {
            case .up, .down, .left, .right:
                radialGradient.opacity = 1
                radialGradient.transform = shineTransform
            case .radioactive, nil:
                radialGradient.opacity = 0
            @unknown default:
                assertionFailure()
                radialGradient.opacity = 0
            }
        } else {
            linearGradient.opacity = 0
            radialGradient.opacity = 0
        }
    }
    
    private func applyBorderMask() {
        let outerPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius)
        let insetRect = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        let innerPath = UIBezierPath(roundedRect: insetRect, cornerRadius: layer.cornerRadius - borderWidth)
        outerPath.append(innerPath)
        outerPath.usesEvenOddFillRule = true
        let maskLayer = CAShapeLayer()
        maskLayer.path = outerPath.cgPath
        maskLayer.fillRule = .evenOdd
        layer.mask = maskLayer
    }
}
