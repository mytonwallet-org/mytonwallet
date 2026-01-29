import UIKit
import WalletContext

public class WChartSegmentedControl: UISegmentedControl, WThemedView {
    
    private var isFirstRender = true
    private var backgroundLayer: CALayer?

    public override func layoutSubviews(){
        super.layoutSubviews()
                
        if #available(iOS 26, *) {
           if isFirstRender {
               for subview in subviews {
                   if subview is UIImageView {
                       subview.isHidden = true                       
                   }
               }
               isFirstRender = false
           }
        } else {            
            let imageViews = subviews.compactMap { $0 as? UIImageView }.prefix(numberOfSegments)
            imageViews.forEach { $0.isHidden = true }            

            if let selectorImageView {
                let inset: CGFloat = 5
                selectorImageView.bounds = selectorImageView.bounds.insetBy(dx: inset, dy: inset)
                selectorImageView.image = nil
                selectorImageView.layer.cornerRadius = selectorImageView.bounds.height / 2
                selectorImageView.layer.masksToBounds = true
                selectorImageView.layer.removeAnimation(forKey: "SelectionBounds")
                selectorImageView.isHidden = false
            }

            // Recreate every time since it may be unpredictably covered by other subviews
            backgroundLayer?.removeFromSuperlayer()
            let l = CALayer()
            l.frame = bounds
            layer.insertSublayer(l, at: 0)
            backgroundLayer = l
        }
        
        layer.cornerRadius = bounds.height / 2
        updateTheme()
    }
        
    public func updateTheme() {
        if #available(iOS 26, *) {
            selectedSegmentTintColor = WTheme.groupedItem
            backgroundColor = WTheme.balanceHeaderView.background
        } else {
            backgroundLayer?.backgroundColor = WTheme.balanceHeaderView.background.resolvedColor(with: traitCollection).cgColor
            selectorImageView?.layer.backgroundColor  = WTheme.groupedItem.resolvedColor(with: traitCollection).cgColor
        }
    }
    
    private var selectorImageView: UIImageView? {
        let selectorIndex = numberOfSegments
        guard subviews.indices.contains(selectorIndex), let imageView = subviews[selectorIndex] as? UIImageView else {
            return nil
        }
        return imageView
    }
}
