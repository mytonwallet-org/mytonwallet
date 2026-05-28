import Foundation
import UIKit
import UIComponents

private let largeButtonSize = CGSize(width: 72.0, height: 72.0)

private func generateEmptyButtonImage(icon: UIImage?,
                                      strokeColor: UIColor?,
                                      fillColor: UIColor,
                                      knockout: Bool = false,
                                      angle: CGFloat = 0.0,
                                      buttonSize: CGSize = largeButtonSize) -> UIImage? {
    return generateImage(buttonSize, contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setBlendMode(.copy)
        if let strokeColor = strokeColor {
            context.setFillColor(strokeColor.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(x: 1.5, y: 1.5), size: CGSize(width: size.width - 3.0, height: size.height - 3.0)))
        } else {
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: CGSize(width: size.width, height: size.height)))
        }
        
        if let icon = icon {
            if !angle.isZero {
                context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
                context.rotate(by: angle)
                context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
            }
            let imageSize = icon.size
            let imageRect = CGRect(origin: CGPoint(x: floor((size.width - imageSize.width) / 2.0), y: floor((size.width - imageSize.height) / 2.0)), size: imageSize)
            if knockout {
                context.setBlendMode(.copy)
                context.clip(to: imageRect, mask: icon.cgImage!)
                context.setFillColor(UIColor.clear.cgColor)
                context.fill(imageRect)
            } else {
                context.setBlendMode(.normal)
                context.draw(icon.cgImage!, in: imageRect)
            }
        }
    })
}

private let emptyHighlightedFill = UIColor(white: 1.0, alpha: 0.3)
private let invertedFill = UIColor(white: 1.0, alpha: 1.0)

public final class GlassButton: UIButton {

    private let regularImage: UIImage!
    private let filledImage: UIImage!
    private let blurView: UIVisualEffectView!
    
    public init(icon: UIImage) {
        regularImage = generateEmptyButtonImage(icon: icon,
                                                strokeColor: nil,
                                                fillColor: .clear,
                                                buttonSize: largeButtonSize)
        filledImage = generateEmptyButtonImage(icon: icon,
                                                strokeColor: nil,
                                                fillColor: invertedFill,
                                                knockout: true,
                                                buttonSize: largeButtonSize)
        blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.clipsToBounds = true
        blurView.isUserInteractionEnabled = false
        insertSubview(blurView, at: 0)
        if let imageView = self.imageView {
            bringSubviewToFront(imageView)
        }
        NSLayoutConstraint.activate([
            blurView.leftAnchor.constraint(equalTo: leftAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.rightAnchor.constraint(equalTo: rightAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setImage(regularImage, for: .normal)
        let highlightedImage = generateEmptyButtonImage(icon: icon,
                                                        strokeColor: nil,
                                                        fillColor: emptyHighlightedFill,
                                                        buttonSize: largeButtonSize)
        setImage(highlightedImage, for: .highlighted)

        blurView.frame = self.bounds
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()

        blurView.layer.cornerRadius = frame.size.width / 2.0
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var isSelected: Bool {
        didSet {
            UIView.transition(with: self,
                              duration: 0.4,
                              options: .transitionCrossDissolve,
                              animations: {
                self.setImage(self.isSelected ? self.filledImage : self.regularImage, for: .normal)
           }, completion: nil)
        }
    }

}
