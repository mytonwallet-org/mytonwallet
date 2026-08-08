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
        model?.onToggleRequested = nil
        setHeight(targetHeight, notify: false)
    }

    func configure(model: TokenInfoModel, onHeightChange: @escaping () -> Void) {
        self.onHeightChange = onHeightChange
        if self.model !== model {
            installHostingView(model: model)
        }

        heightAnimator?.invalidate()
        heightAnimator = nil
        model.onToggleRequested = { [weak self] in
            self?.toggleExpanded()
        }
        hostingHeightConstraint?.constant = model.measuredExpandedHeight
        setHeight(targetHeight, notify: false)
    }

    func modelStateDidChange() {
        heightAnimator?.invalidate()
        heightAnimator = nil
        let newHeight = targetHeight
        setHeight(newHeight, notify: abs(currentHeight - newHeight) > 0.5)
    }

    private func installHostingView(model: TokenInfoModel) {
        hostingView?.removeFromSuperview()
        hostingHeightConstraint?.isActive = false
        self.model = model

        let hostingView = HostingView { [weak self, weak model] in
            if let model {
                TokenInfoView(model: model) { [weak self] height in
                    self?.updateExpandedHeight(height)
                }
            }
        }
        let hostingHeightConstraint = hostingView.heightAnchor.constraint(
            equalToConstant: model.measuredExpandedHeight
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

    private func toggleExpanded() {
        guard let model, heightAnimator == nil, model.canExpand else { return }

        let willExpand = !model.isExpanded
        model.setExpanded(willExpand)

        if UIAccessibility.isReduceMotionEnabled {
            setHeight(targetHeight, notify: true)
            return
        }

        let animator = ValueAnimator(
            startValue: currentHeight,
            endValue: targetHeight,
            duration: TokenInfoModel.animationDuration,
            dampingRatio: 0.93
        )
        heightAnimator = animator
        animator.addUpdateBlock { [weak self] _, height in
            self?.setHeight(height, notify: true)
        }
        animator.addCompletionBlock { [weak self, weak animator] in
            guard let self, heightAnimator === animator else { return }
            setHeight(targetHeight, notify: true)
            heightAnimator = nil
        }
        animator.start()
    }

    private func setHeight(_ height: CGFloat, notify: Bool) {
        currentHeight = height
        if let model {
            let heightRange = max(model.measuredExpandedHeight - TokenInfoModel.collapsedHeight, 1)
            model.setExpansionProgress((height - TokenInfoModel.collapsedHeight) / heightRange)
        }
        if notify {
            onHeightChange?()
        }
    }

    private func updateExpandedHeight(_ height: CGFloat) {
        guard let model else { return }
        let height = max(height, TokenInfoModel.collapsedHeight)
        guard abs(model.measuredExpandedHeight - height) > 0.5 else { return }

        model.measuredExpandedHeight = height
        hostingHeightConstraint?.constant = height

        if heightAnimator == nil {
            let newHeight = targetHeight
            setHeight(newHeight, notify: abs(currentHeight - newHeight) > 0.5)
        }
    }
}
