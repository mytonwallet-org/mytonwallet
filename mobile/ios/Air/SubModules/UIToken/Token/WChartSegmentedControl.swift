import UIKit
import WalletContext

public class WChartSegmentedControl: UISegmentedControl, WThemedView {

    private var isFirstRender = true

    public override func layoutSubviews(){
        super.layoutSubviews()

        if isFirstRender {
            for subview in subviews {
                if subview is UIImageView {
                    subview.isHidden = true
                }
            }
            isFirstRender = false
        }
        layer.cornerRadius = bounds.height / 2
        updateTheme()
    }
    
    public func updateTheme() {
        backgroundColor = WTheme.balanceHeaderView.background
        selectedSegmentTintColor = WTheme.groupedItem
    }
}
