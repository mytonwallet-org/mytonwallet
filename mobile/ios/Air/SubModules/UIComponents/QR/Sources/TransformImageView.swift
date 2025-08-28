import Foundation
import UIKit
import SwiftSignalKit

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
    private var disposable = MetaDisposable()

    private var currentTransform: ((TransformImageArguments) -> DrawingContext?)?
    private var currentArguments: TransformImageArguments?
    private var argumentsPromise = ValuePromise<TransformImageArguments>(ignoreRepeated: true)

    deinit {
        self.disposable.dispose()
    }
    
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
        self.disposable.set(nil)
        self.currentArguments = nil
        self.currentTransform = nil
        self.image = nil
    }
    
    public func setSignal(_ signal: Signal<(TransformImageArguments) -> DrawingContext?, NoError>, attemptSynchronously: Bool = false, dispatchOnDisplayLink: Bool = true) {
        let argumentsPromise = self.argumentsPromise
        
        let data = combineLatest(signal, argumentsPromise.get())
        
        let resultData: Signal<((TransformImageArguments) -> DrawingContext?, TransformImageArguments), NoError>
        if attemptSynchronously {
            resultData = data
        } else {
            resultData = data
            |> deliverOn(Queue.concurrentDefaultQueue())
        }
        
        let result = resultData
        |> mapToThrottled { transform, arguments -> Signal<((TransformImageArguments) -> DrawingContext?, TransformImageArguments, UIImage?)?, NoError> in
            return deferred {
                if let context = transform(arguments) {
                    return .single((transform, arguments, context.generateImage()))
                } else {
                    return .single(nil)
                }
            }
        }
        
        self.disposable.set((result |> deliverOnMainQueue).start(next: { [weak self] next in
            let apply: () -> Void = {
                if let strongSelf = self {
                    if strongSelf.image == nil {
                        if strongSelf.contentAnimations.contains(.firstUpdate) && !attemptSynchronously {
                            strongSelf.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
                        }
                    } else if strongSelf.contentAnimations.contains(.subsequentUpdates) {
                        let tempLayer = CALayer()
                        tempLayer.frame = strongSelf.bounds
                        tempLayer.contentsGravity = strongSelf.layer.contentsGravity
                        tempLayer.contents = strongSelf.image
                        strongSelf.layer.addSublayer(tempLayer)
                        tempLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false, completion: { [weak tempLayer] _ in
                            tempLayer?.removeFromSuperlayer()
                        })
                    }
                    
                    var imageUpdate: UIImage?
                    if let (transform, arguments, image) = next {
                        strongSelf.currentTransform = transform
                        strongSelf.currentArguments = arguments
                        strongSelf.image = image
                        imageUpdate = image
                    }
                    if let imageUpdated = strongSelf.imageUpdated {
                        imageUpdated(imageUpdate)
                    }
                }
            }
            if dispatchOnDisplayLink && !attemptSynchronously {
                //displayLinkDispatcher.dispatch {
                    apply()
                //}
            } else {
                apply()
            }
        }))
    }
    
    public func asyncLayout() -> (TransformImageArguments) -> (() -> Void) {
        let currentTransform = self.currentTransform
        let currentArguments = self.currentArguments
        return { [weak self] arguments in
            let updatedImage: UIImage?
            if currentArguments != arguments {
                updatedImage = currentTransform?(arguments)?.generateImage()
            } else {
                updatedImage = nil
            }
            return {
                guard let strongSelf = self else {
                    return
                }
                if let image = updatedImage {
                    strongSelf.image = image
                    strongSelf.currentArguments = arguments
                }
                strongSelf.argumentsPromise.set(arguments)
            }
        }
    }

}
