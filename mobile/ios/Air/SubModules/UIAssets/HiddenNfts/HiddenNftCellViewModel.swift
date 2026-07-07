
import Perception
import WalletCore

@Perceptible
@MainActor
final class HiddenNftCellViewModel {
    var displayNft: DisplayNft

    var isHiddenByUser: Bool {
        get { displayNft.isHiddenByUser }
        set { displayNft.isHiddenByUser = newValue }
    }

    var isUnhiddenByUser: Bool {
        get { displayNft.isUnhiddenByUser }
        set { displayNft.isUnhiddenByUser = newValue }
    }

    init(_ displayNft: DisplayNft) {
        self.displayNft = displayNft
    }
}
