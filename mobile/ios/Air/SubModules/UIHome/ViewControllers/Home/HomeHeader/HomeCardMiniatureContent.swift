import UIKit
import UIKitNavigation
import UIComponents
import WalletCore

final class HomeCardMiniatureContent: UIView {
    private let content = MtwCardMiniatureContentView()
    private var appearanceObservation: ObserveToken?
    private var opacityObservation: ObserveToken?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(headerViewModel: HomeHeaderViewModel, accountContext: AccountContext) {
        prepareForReuse()
        appearanceObservation = observe { [weak self] in
            self?.content.configure(nft: accountContext.nft)
        }
        opacityObservation = observe { [weak self] in
            self?.content.alpha = headerViewModel.cardOpacity
        }
    }

    func prepareForReuse() {
        appearanceObservation?.cancel()
        appearanceObservation = nil
        opacityObservation?.cancel()
        opacityObservation = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.frame = bounds
    }
}
