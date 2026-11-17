import Perception
import SwiftUI
import UIComponents
import UIHome
import UIKit
import WalletCore

/// Home's promotion banners floating above the shared search toolbar on the root tabs of the top-tabs layout. They
/// replace the ones in the Wallet list when Wallet is not the first tab, and are the same banners with the same
/// actions and dismissal. The split layout keeps its banners in the sidebar.
private struct RootPromotionOverlayView: View {
    let accountContext: AccountContext

    var body: some View {
        WithPerceptionTracking {
            if HomePromotionPlacement.shared.isOverlay {
                HomeAccountBannersView(accountContext: accountContext, style: .overlay)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("promotion_overlay")
            }
        }
        // The host is pinned by its bottom and can still have the previous height when the banners change, so they
        // stay at its bottom rather than jump by half the change. The host's intrinsic height stays the banners'.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .bottom)
    }
}

/// Reports its view's height once Auto Layout has sized it to the banners
private final class RootPromotionOverlayHostingController: UIHostingController<RootPromotionOverlayView> {
    var onLayout: ((CGFloat) -> Void)?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        onLayout?(view.bounds.height)
    }
}

@MainActor
final class RootPromotionOverlayController {
    /// How far the cards reach past the toolbar on each side, which puts them 16 pt from the edges of a phone's screen
    private let toolbarOverhang: CGFloat = 12
    private let gapToToolbar: CGFloat = 10
    /// How far the banners reach above the toolbar, 0 without banners. The root tabs they float over keep their
    /// content clear of it.
    private(set) var reservedHeight: CGFloat = 0
    var onReservedHeightChange: (() -> Void)?
    private lazy var host: RootPromotionOverlayHostingController = {
        let host = RootPromotionOverlayHostingController(
            rootView: RootPromotionOverlayView(accountContext: AccountContext(source: .current))
        )
        host.sizingOptions = .intrinsicContentSize
        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.isHidden = true
        host.onLayout = { [weak self] height in
            self?.updateReservedHeight(bannersHeight: height)
        }
        return host
    }()

    /// Places the overlay in the toolbar's viewport, so it follows the toolbar and is clipped to the content panel,
    /// behind the toolbar's container, so a field growing above the toolbar stays in front. `toolbar` is the visible
    /// toolbar in that container, which the cards center on and follow in width. Returns constraints for the caller
    /// to activate and later deactivate together with its own.
    func install(in viewport: UIView, below container: UIView, above toolbar: UIView) -> [NSLayoutConstraint] {
        guard container.superview === viewport, toolbar.isDescendant(of: container) else { return [] }
        let view = host.view!
        viewport.insertSubview(view, belowSubview: container)
        return [
            view.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: -toolbarOverhang),
            view.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: toolbarOverhang),
            view.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -gapToToolbar),
        ]
    }

    private func updateReservedHeight(bannersHeight: CGFloat) {
        let height = bannersHeight > 0 ? bannersHeight + gapToToolbar : 0
        guard height != reservedHeight else { return }
        reservedHeight = height
        onReservedHeightChange?()
    }

    /// Fades with `isHidden`, never alpha, which would drop the glass and the blur
    func setVisible(_ isVisible: Bool) {
        guard host.view.superview != nil, host.view.isHidden == isVisible else { return }
        UIView.transition(with: host.view, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.host.view.isHidden = !isVisible
        }
    }
}
