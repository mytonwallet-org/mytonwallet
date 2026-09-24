import UIKit
import UIKitNavigation
import UIComponents
import WalletCore

final class HomeCardBackground: UIView {
    private let backgroundView = MtwCardBackgroundView()
    private var appearanceObservation: ObserveToken?
    private var opacityObservation: ObserveToken?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(headerViewModel: HomeHeaderViewModel, accountContext: AccountContext) {
        appearanceObservation?.cancel()
        opacityObservation?.cancel()
        appearanceObservation = observe { [weak self] in
            let effects = headerViewModel.allowsCardEffects(for: accountContext.account.id)
            self?.backgroundView.configure(nft: accountContext.nft, isAnimationEnabled: effects, isShineEnabled: effects, surface: .current)
        }
        opacityObservation = observe { [weak self] in
            self?.alpha = headerViewModel.cardOpacity
        }
    }

    func setLight(_ light: CardSurfaceLight) {
        backgroundView.setLight(light)
    }

    func prepareForReuse() {
        appearanceObservation?.cancel()
        appearanceObservation = nil
        opacityObservation?.cancel()
        opacityObservation = nil
        backgroundView.cancelImageLoading()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
    }
}
