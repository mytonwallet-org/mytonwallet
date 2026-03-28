import UIKit

struct NftDetailsContentPalette {
    let baseColor: UIColor
    let subtleBackgroundColor: UIColor
    let edgeColor: UIColor
    let secondaryTextColor: UIColor
    let highlightColor: UIColor
    
    static var defaultBackgroundColor: UIColor { .air.sheetBackground }
}

/// Page subviews should adopt this protocol to respond to NFT theme changes
protocol NftDetailsContentColorConsumer: UIView {
    
    /// Return `true` to process subviews as well, `false` otherwise
    func applyContentColorPalette(_ palette: NftDetailsContentPalette) -> Bool
}
