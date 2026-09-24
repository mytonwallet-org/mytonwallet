import UIKit
import UIKitNavigation
import UIComponents
import WalletCore

final class HomeCardPromotionView: UIView {
    private let artwork = MtwCardPromotionView()
    private var promotionObservation: ObserveToken?
    private var opacityObservation: ObserveToken?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(headerViewModel: HomeHeaderViewModel, accountContext: AccountContext) {
        prepareForReuse()
        promotionObservation = observe { [weak self] in
            self?.artwork.configure(promotion: accountContext.activePromotion)
        }
        opacityObservation = observe { [weak self] in
            self?.alpha = headerViewModel.cardOpacity
        }
    }

    func prepareForReuse() {
        promotionObservation?.cancel()
        promotionObservation = nil
        opacityObservation?.cancel()
        opacityObservation = nil
        artwork.prepareForReuse()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        artwork.frame = bounds
    }
}
