import UIKit
import UIComponents
import WalletContext
import WalletCore

/// The Info card of token and futures pages. SwiftUI content stays at its measured expanded height,
/// and this view animates only its clipping viewport.
final class TokenInfoCardView: UIView {
    /// Height the card currently occupies. A cell reports it to its layout; a standalone card applies it to itself.
    var currentHeight = TokenInfoModel.collapsedHeight {
        didSet { ownHeightConstraint?.constant = currentHeight }
    }
    private var model: TokenInfoModel?
    private var hostingView: HostingView?
    private var hostingHeightConstraint: NSLayoutConstraint?
    private var ownHeightConstraint: NSLayoutConstraint?
    private var heightAnimator: ValueAnimator?
    private var onHeightChange: (() -> Void)?
    private var onUserToggleAnimationChange: ((Bool) -> Void)?
    private var isUserToggleAnimationActive = false

    /// - Parameter sizesItself: Constrains the card's own height, for use outside a collection view.
    init(sizesItself: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .air.groupedItem
        layer.cornerRadius = S.homeInsetSectionCornerRadius
        layer.masksToBounds = true
        if sizesItself {
            let height = heightAnchor.constraint(equalToConstant: currentHeight)
            height.isActive = true
            ownHeightConstraint = height
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func prepareForReuse() {
        heightAnimator?.invalidate()
        heightAnimator = nil
        setUserToggleAnimationActive(false)
        model?.onToggleRequested = nil
        synchronizeHeight(notify: false)
    }

    func configure(
        model: TokenInfoModel,
        onHeightChange: @escaping () -> Void,
        onUserToggleAnimationChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.onHeightChange = onHeightChange
        if self.model !== model {
            installHostingView(model: model)
        }

        heightAnimator?.invalidate()
        heightAnimator = nil
        setUserToggleAnimationActive(false)
        self.onUserToggleAnimationChange = onUserToggleAnimationChange
        model.onToggleRequested = { [weak self] in
            self?.toggleExpanded()
        }
        hostingHeightConstraint?.constant = presentationHostingHeight(for: model)
        if model.pendingPresentationRevision == nil {
            synchronizeHeight(notify: false)
        } else {
            synchronizeTransitionStartHeight(notify: false)
        }
    }

    func modelStateDidChange() {
        guard heightAnimator == nil, model?.pendingPresentationRevision == nil else { return }
        synchronizeHeight(notify: true)
    }

    private func installHostingView(model: TokenInfoModel) {
        hostingView?.removeFromSuperview()
        hostingHeightConstraint?.isActive = false
        self.model = model

        let hostingView = HostingView { [weak self, weak model] in
            if let model {
                TokenInfoView(model: model) { [weak self] height, revision in
                    // SwiftUI can measure during collection-view self-sizing. Invalidating the
                    // layout re-entrantly leaves contentView at the previous fitted height.
                    Task { @MainActor [weak self, weak model] in
                        guard let self, let model, self.model === model else { return }
                        updateContentMeasurement(height: height, revision: revision)
                    }
                }
            }
        }
        let hostingHeightConstraint = hostingView.heightAnchor.constraint(
            equalToConstant: presentationHostingHeight(for: model)
        )
        self.hostingView = hostingView
        self.hostingHeightConstraint = hostingHeightConstraint

        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingHeightConstraint,
        ])
    }

    private var targetHeight: CGFloat {
        guard let model else { return TokenInfoModel.collapsedHeight }
        return model.isExpanded && model.canExpand
            ? model.measuredExpandedHeight
            : TokenInfoModel.collapsedHeight
    }

    private func presentationHostingHeight(for model: TokenInfoModel) -> CGFloat {
        // Once measured, the incoming content owns the host size even while the old layer fades out.
        guard model.pendingPresentationRevision != nil else {
            return model.state.isLoading
                ? TokenInfoModel.collapsedHeight
                : model.measuredExpandedHeight
        }
        return switch model.presentationOverlay {
        case .skeleton:
            TokenInfoModel.collapsedHeight
        case .content(let snapshot) where snapshot.state.canExpand && snapshot.expansionProgress > 0:
            snapshot.expandedHeight
        case .content, nil:
            model.state.isLoading
                ? TokenInfoModel.collapsedHeight
                : model.measuredExpandedHeight
        }
    }

    private func toggleExpanded() {
        guard let model, heightAnimator == nil, model.canExpand else { return }

        setUserToggleAnimationActive(true)
        if !model.hasBalance {
            model.toggleDescription()
            return
        }
        let willExpand = !model.isExpanded
        model.setExpanded(willExpand)
        let targetExpansionProgress = model.targetExpansionProgress

        if UIAccessibility.isReduceMotionEnabled || !AppStorageHelper.animations {
            setHeight(
                targetHeight,
                expansionProgress: targetExpansionProgress,
                notify: true
            )
            setUserToggleAnimationActive(false)
            return
        }

        animateHeight(
            to: targetHeight,
            targetExpansionProgress: targetExpansionProgress
        )
    }

    private func animateHeight(
        to targetHeight: CGFloat,
        targetExpansionProgress: CGFloat
    ) {
        heightAnimator?.invalidate()
        let startHeight = currentHeight
        let startExpansionProgress = model?.expansionProgress ?? targetExpansionProgress
        let animator = AssetInfoExpansion.animator(from: startHeight, to: targetHeight)
        heightAnimator = animator
        animator.addUpdateBlock { [weak self] progress, height in
            let expansionProgress = startExpansionProgress
                + (targetExpansionProgress - startExpansionProgress) * progress
            self?.setHeight(
                height,
                expansionProgress: expansionProgress,
                notify: abs(height - startHeight) > 0.01
            )
        }
        animator.addCompletionBlock { [weak self, weak animator] in
            guard let self, heightAnimator === animator else { return }
            setHeight(
                targetHeight,
                expansionProgress: targetExpansionProgress,
                notify: abs(currentHeight - targetHeight) > 0.01
            )
            heightAnimator = nil
            setUserToggleAnimationActive(false)
        }
        animator.start()
    }

    private func setUserToggleAnimationActive(_ isActive: Bool) {
        guard isUserToggleAnimationActive != isActive else { return }
        isUserToggleAnimationActive = isActive
        onUserToggleAnimationChange?(isActive)
    }

    private func setHeight(
        _ height: CGFloat,
        expansionProgress: CGFloat? = nil,
        notify: Bool
    ) {
        let heightChanged = abs(currentHeight - height) > 0.01
        currentHeight = height
        if let expansionProgress {
            model?.setExpansionProgress(expansionProgress)
        }
        if notify, heightChanged {
            onHeightChange?()
        }
    }

    private func updateContentMeasurement(height: CGFloat, revision: Int) {
        guard let model else { return }
        guard revision == model.layoutRevision else { return }
        if model.isConfiguringState {
            Task { @MainActor [weak self] in
                self?.updateContentMeasurement(height: height, revision: revision)
            }
            return
        }

        let previousTargetHeight = targetHeight
        if model.canExpand {
            model.updateMeasuredExpandedHeight(height)
            hostingHeightConstraint?.constant = model.measuredExpandedHeight
        }

        if model.pendingPresentationRevision == revision {
            beginPresentationTransition(revision: revision)
        } else if heightAnimator == nil {
            synchronizeHeight(notify: true)
        } else if abs(targetHeight - previousTargetHeight) > 0.5 {
            // Description measurements can settle after the presentation animation starts.
            animateHeight(
                to: targetHeight,
                targetExpansionProgress: model.targetExpansionProgress
            )
        }
    }

    private func beginPresentationTransition(revision: Int) {
        guard let model else { return }
        let animated = !UIAccessibility.isReduceMotionEnabled && AppStorageHelper.animations
        let newHeight = targetHeight
        let targetExpansionProgress = model.targetExpansionProgress

        model.beginPresentationTransition(revision: revision, animated: animated)

        if animated && (
            abs(currentHeight - newHeight) > 0.01
                || abs(model.expansionProgress - targetExpansionProgress) > 0.001
        ) {
            animateHeight(
                to: newHeight,
                targetExpansionProgress: targetExpansionProgress
            )
        } else {
            setHeight(
                newHeight,
                expansionProgress: targetExpansionProgress,
                notify: true
            )
            setUserToggleAnimationActive(false)
        }
    }

    private func synchronizeHeight(notify: Bool) {
        guard let model else { return }
        let newHeight = targetHeight
        setHeight(
            newHeight,
            expansionProgress: model.targetExpansionProgress,
            notify: notify
        )
    }

    private func synchronizeTransitionStartHeight(notify: Bool) {
        guard let model else { return }
        switch model.presentationOverlay {
        case .skeleton:
            setHeight(
                TokenInfoModel.collapsedHeight,
                expansionProgress: 0,
                notify: notify
            )
        case .content(let snapshot):
            let height = snapshot.state.canExpand && snapshot.expansionProgress > 0
                ? snapshot.expandedHeight
                : TokenInfoModel.collapsedHeight
            setHeight(
                height,
                expansionProgress: snapshot.expansionProgress,
                notify: notify
            )
        case nil:
            synchronizeHeight(notify: notify)
        }
    }
}
