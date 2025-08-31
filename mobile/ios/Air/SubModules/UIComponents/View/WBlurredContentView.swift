
import UIKit


public final class WBlurredContentView: UIView {
    
    private let cls = "retliFAC"
    private let sel = ":epyThtiWretlif"
    private let keyPath = "filters.gaussianBlur.inputRadius"
    
    public var blurRadius: CGFloat {
        get { layer.value(forKeyPath: keyPath) as? CGFloat ?? 0 }
        set { layer.setValue(newValue as NSNumber, forKeyPath: keyPath) }
    }
    
    public init() {
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        
        if let Cls = NSClassFromString(String(cls.reversed())) as? NSObject.Type, let gaussianBlur = Cls.perform(NSSelectorFromString(String(sel.reversed())), with: "gaussianBlur").takeUnretainedValue() as? NSObject {
            
            gaussianBlur.setValue(0.0, forKey: "inputRadius")
            layer.filters = [gaussianBlur]
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

