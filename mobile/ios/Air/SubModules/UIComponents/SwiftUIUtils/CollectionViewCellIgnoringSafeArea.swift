
import SwiftUI
import UIKit

public final class CollectionViewCellIgnoringSafeArea: UICollectionViewCell {
    
    public override var safeAreaInsets: UIEdgeInsets {
        get { .zero }
        set { }
    }
}
