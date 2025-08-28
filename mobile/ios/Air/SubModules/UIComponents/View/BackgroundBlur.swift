
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins
import QuartzCore


public struct BackgroundBlur: UIViewRepresentable {
    
    public var radius: CGFloat
    
    public init(radius: CGFloat) {
        self.radius = radius
    }
    
    public func makeUIView(context: Context) -> BackgroundBlurView {
        BackgroundBlurView(radius: radius)
    }

    public func updateUIView(_ uiView: BackgroundBlurView, context: Context) {
    }
}


open class BackgroundBlurView: UIVisualEffectView {

    private let keyPath = "filters.gaussianBlur.inputRadius"
    
    public var blurRadius: CGFloat {
        get { blurLayer?.value(forKeyPath: keyPath) as? CGFloat ?? 0 }
        set { blurLayer?.setValue(newValue as NSNumber, forKeyPath: keyPath) }
    }
    
    private weak var blurLayer: CALayer?
    
    public init(radius: CGFloat) {
        super.init(effect: UIBlurEffect(style: .regular))
        for subview in subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        
        if let sublayer = layer.sublayers?[0], let filters = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            sublayer.filters = filters.filter { filter in
                "\(filter)" == "gaussianBlur"
            }
            self.blurLayer = sublayer
        }
        blurRadius = radius
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func didMoveToWindow() {
        // fixes visible pixelization at unblurred edge (https://github.com/nikstar/VariableBlur/issues/1)
        guard let window, let backdropLayer = subviews.first?.layer else { return }
        backdropLayer.setValue(window.traitCollection.displayScale, forKey: "scale")
    }
    
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // `super.traitCollectionDidChange(previousTraitCollection)` crashes the app
    }
}
