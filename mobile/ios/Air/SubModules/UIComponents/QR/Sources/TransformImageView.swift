import Foundation
import UIKit

public struct TransformImageViewContentAnimations: OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public static let firstUpdate = TransformImageViewContentAnimations(rawValue: 1 << 0)
    public static let subsequentUpdates = TransformImageViewContentAnimations(rawValue: 1 << 1)
}

// This is ported version of `TransformImageNode`, just a little simplified and changed to work with UIKit
open class TransformImageView: UIImageView {
    public var imageUpdated: ((UIImage?) -> Void)?
    public var contentAnimations: TransformImageViewContentAnimations = []

    private var currentTransform: ((TransformImageArguments) -> DrawingContext?)?
    private var currentArguments: TransformImageArguments?
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        if #available(iOSApplicationExtension 11.0, iOS 11.0, *) {
            accessibilityIgnoresInvertColors = true
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func reset() {
        self.currentArguments = nil
        self.currentTransform = nil
        self.image = nil
    }
    
    public func setContent(_ transform: @escaping (TransformImageArguments) -> DrawingContext?, attemptSynchronously: Bool = false) {
        self.currentTransform = transform
        guard attemptSynchronously, let arguments = currentArguments else {
            return
        }
        let isInitial = self.image == nil
        let image = transform(arguments)?.generateImage()
        self.applyImage(image, arguments: arguments, animate: !attemptSynchronously && !isInitial)
    }
    
    public func asyncLayout() -> (TransformImageArguments) -> (() -> Void) {
        return { [weak self] arguments in
            let updatedImage: UIImage?
            if self?.currentArguments != arguments {
                updatedImage = self?.currentTransform?(arguments)?.generateImage()
            } else {
                updatedImage = nil
            }
            return {
                guard let strongSelf = self else {
                    return
                }
                if let image = updatedImage {
                    strongSelf.applyImage(image, arguments: arguments, animate: true)
                } else {
                    strongSelf.currentArguments = arguments
                }
            }
        }
    }
    
    private func applyImage(_ image: UIImage?, arguments: TransformImageArguments, animate: Bool) {
        let shouldAnimateFirst = self.image == nil && self.contentAnimations.contains(.firstUpdate) && animate
        let shouldAnimateSubsequent = self.image != nil && self.contentAnimations.contains(.subsequentUpdates) && animate
        
        if shouldAnimateFirst {
            self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
        } else if shouldAnimateSubsequent {
            let tempLayer = CALayer()
            tempLayer.frame = self.bounds
            tempLayer.contentsGravity = self.layer.contentsGravity
            tempLayer.contents = self.image
            self.layer.addSublayer(tempLayer)
            tempLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak tempLayer] _ in
                tempLayer?.removeFromSuperlayer()
            })
        }
        
        self.currentArguments = arguments
        self.image = image
        self.imageUpdated?(image)
    }

}
