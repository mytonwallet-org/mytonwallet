import UIKit
import UIActivityList
import UIComponents
import WalletContext
import WalletCore

final class TokenInfoCell: FirstRowCell {
    private let horizontalInset = CGFloat(16)
    private let clippingView = UIView()
    private var model: TokenInfoModel?
    private var hostingView: HostingView?
    private var hostingHeightConstraint: NSLayoutConstraint?
    private var currentHeight = TokenInfoModel.collapsedHeight
    private var heightAnimator: ValueAnimator?
    private var onHeightChange: (() -> Void)?
    private var onUserToggleAnimationChange: ((Bool) -> Void)?
    private var isUserToggleAnimationActive = false

    override var height: CGFloat? {
        get { currentHeight }
        set { currentHeight = newValue ?? 0 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        clippingView.translatesAutoresizingMaskIntoConstraints = false
        clippingView.backgroundColor = .air.groupedItem
        clippingView.layer.cornerRadius = S.homeInsetSectionCornerRadius
        clippingView.layer.masksToBounds = true
        contentView.addSubview(clippingView)
        NSLayoutConstraint.activate([
            clippingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            clippingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
            clippingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            clippingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        heightAnimator?.invalidate()
        heightAnimator = nil
        setUserToggleAnimationActive(false)
        model?.onToggleRequested = nil
        synchronizeHeight(notify: false)
    }

    func configure(
        model: TokenInfoModel,
        onHeightChange: @escaping () -> Void,
        onUserToggleAnimationChange: @escaping (Bool) -> Void
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
                    self?.updateContentMeasurement(height: height, revision: revision)
                }
            }
        }
        let hostingHeightConstraint = hostingView.heightAnchor.constraint(
            equalToConstant: presentationHostingHeight(for: model)
        )
        self.hostingView = hostingView
        self.hostingHeightConstraint = hostingHeightConstraint

        clippingView.addSubview(hostingView)
        // Keep SwiftUI at its expanded size and animate only this UIKit clipping viewport.
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: clippingView.topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: clippingView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: clippingView.trailingAnchor),
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

        let willExpand = !model.isExpanded
        setUserToggleAnimationActive(true)
        model.setExpanded(willExpand)
        let targetExpansionProgress = model.targetExpansionProgress

        if UIAccessibility.isReduceMotionEnabled {
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
        let animator = ValueAnimator(
            startValue: startHeight,
            endValue: targetHeight,
            duration: TokenInfoModel.animationDuration,
            dampingRatio: 0.93
        )
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

        if model.canExpand {
            model.updateMeasuredExpandedHeight(height)
            hostingHeightConstraint?.constant = model.measuredExpandedHeight
        }

        if model.pendingPresentationRevision == revision {
            beginPresentationTransition(revision: revision)
        } else if heightAnimator == nil {
            synchronizeHeight(notify: true)
        }
    }

    private func beginPresentationTransition(revision: Int) {
        guard let model else { return }
        let animated = !UIAccessibility.isReduceMotionEnabled
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
