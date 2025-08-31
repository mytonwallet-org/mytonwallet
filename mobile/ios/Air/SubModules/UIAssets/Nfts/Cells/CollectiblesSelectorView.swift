
import UIKit
import WalletCore
import WalletContext

final class CollectionSelectorView: UIView {
    
    init() {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var onSelect: ((String?) -> ())?
    
    func setup() {
        
    }
}
