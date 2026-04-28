import UIKit
import SwiftUI

public  class ThinGlassView: UIView {
    private let fillLayer = CALayer()
    private let edgeLayer = CAGradientLayer()
    
    public var cornerRadius: CGFloat = 26 {  didSet { setNeedsLayout() }  }
   
    public var edgeStrokeWidth: CGFloat = 0.7 { didSet { setNeedsLayout() } }
    
    public var fillColor: UIColor? { didSet { setNeedsLayout() } }
    
    public var edgeColor: UIColor? { didSet { setNeedsLayout() } }
   
    override public init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.addSublayer(fillLayer)
        layer.addSublayer(edgeLayer)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        updateGradients()
    }
    
    private func updateGradients() {
        // Background fill
        fillLayer.frame = bounds
        fillLayer.cornerRadius = cornerRadius
        fillLayer.cornerCurve = .continuous
        fillLayer.masksToBounds = true
        fillLayer.backgroundColor = fillColor?.cgColor ?? UIColor.clear.cgColor
                
        let edgeColor = self.edgeColor ?? .white
        edgeLayer.frame = bounds
        edgeLayer.type = .conic
        edgeLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        edgeLayer.endPoint = CGPoint(x: 0.5, y: 0)
        edgeLayer.locations = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.0]
        edgeLayer.colors = [
            edgeColor.withAlphaComponent(0.4).cgColor,
            edgeColor.withAlphaComponent(0.15).cgColor,
            edgeColor.withAlphaComponent(0.5).cgColor,
            edgeColor.withAlphaComponent(0.95).cgColor,
            edgeColor.withAlphaComponent(0.5).cgColor,
            edgeColor.withAlphaComponent(0.15).cgColor,
            edgeColor.withAlphaComponent(0.5).cgColor,
            edgeColor.withAlphaComponent(0.95).cgColor,
            edgeColor.withAlphaComponent(0.4).cgColor,
        ]
        
        let shape = CAShapeLayer()
        let w = edgeStrokeWidth
        let rect = bounds.insetBy(dx: w / 2, dy: w / 2)
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        shape.path = path.cgPath
        shape.lineWidth = w
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.fillColor = nil
        shape.strokeColor = edgeColor.cgColor // only alpha value is used here (works as a multiplier for gradient above)
        edgeLayer.mask = shape
    }
}

public struct ThinGlass: UIViewRepresentable {
    public var cornerRadius: CGFloat
    public var fillColor: UIColor?
    public var edgeColor: UIColor?

    public init(cornerRadius: CGFloat = 26, fillColor: UIColor? = nil, edgeColor: UIColor? = nil) {
        self.cornerRadius = cornerRadius
        self.fillColor = fillColor
        self.edgeColor = edgeColor
    }

    public func makeUIView(context: Context) -> ThinGlassView {
        ThinGlassView()
    }

    public func updateUIView(_ uiView: ThinGlassView, context: Context) {
        uiView.cornerRadius = cornerRadius
        uiView.fillColor = fillColor
        uiView.edgeColor = edgeColor
    }
}
