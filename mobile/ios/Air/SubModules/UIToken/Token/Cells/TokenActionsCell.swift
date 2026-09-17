import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext

final class TokenActionsCell: FirstRowCell {
    private var actionsView: TokenActionsView?
    private var actionsHostView: UIView?
    private var heightConstraint: NSLayoutConstraint?
    private var actionsHeightConstraint: NSLayoutConstraint?
    private var installedConstraints: [NSLayoutConstraint] = []
    private var accountContext: AccountContext?
    private var token: ApiToken?
    private var sendAvailable = false
    private var earnAvailable = false
    private let topInset = CGFloat(16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setup(accountContext: AccountContext, token: ApiToken?) {
        self.accountContext = accountContext
        self.token = token
        updateActionsViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateActionsViewIfNeeded()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateActionsViewIfNeeded()
    }

    private func updateActionsViewIfNeeded() {
        guard let accountContext else { return }
        let usesSplitHomeActionStyle = TokenActionsView.usesSplitHomeActionStyle(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            availableWidth: availableWidth
        )
        guard actionsView?.usesSplitHomeActionStyle != usesSplitHomeActionStyle else {
            applyConfiguration()
            return
        }

        NSLayoutConstraint.deactivate(installedConstraints)
        actionsHostView?.removeFromSuperview()

        let actionsView = TokenActionsView(
            accountContext: accountContext,
            token: token,
            usesSplitHomeActionStyle: usesSplitHomeActionStyle
        )
        self.actionsView = actionsView

        let actionsHostView: UIView
        if #available(iOS 26, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = actionsView.glassSpacing
            let glassContainerView = UIVisualEffectView(effect: effect)
            glassContainerView.translatesAutoresizingMaskIntoConstraints = false
            glassContainerView.contentView.addSubview(actionsView)
            NSLayoutConstraint.activate([
                actionsView.leadingAnchor.constraint(equalTo: glassContainerView.contentView.leadingAnchor),
                actionsView.trailingAnchor.constraint(equalTo: glassContainerView.contentView.trailingAnchor),
                actionsView.topAnchor.constraint(equalTo: glassContainerView.contentView.topAnchor),
                actionsView.bottomAnchor.constraint(equalTo: glassContainerView.contentView.bottomAnchor),
            ])
            actionsHostView = glassContainerView
        } else {
            actionsHostView = actionsView
        }
        self.actionsHostView = actionsHostView
        contentView.addSubview(actionsHostView)

        let actionsHeightConstraint = actionsView.heightAnchor.constraint(equalToConstant: actionsView.rowHeight)
        self.actionsHeightConstraint = actionsHeightConstraint

        let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: actionsView.rowHeight + topInset)
        heightConstraint.priority = .defaultHigh
        self.heightConstraint = heightConstraint

        var constraints: [NSLayoutConstraint] = [
            actionsHostView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionsHeightConstraint,
            heightConstraint,
        ]
        if usesSplitHomeActionStyle {
            constraints.append(actionsHostView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor))
        } else {
            let horizontalInset = S.insetSectionHorizontalMargin
            constraints.append(contentsOf: [
                actionsHostView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                actionsHostView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
        installedConstraints = constraints
        applyConfiguration()
    }

    private var availableWidth: CGFloat {
        if contentView.bounds.width > 0 {
            return contentView.bounds.width
        }
        return bounds.width
    }
    
    func reduceButtonHeightFor(_ delta: CGFloat) {
        guard let actionsView, !actionsView.usesSplitHomeActionStyle else {
            return
        }
        let rowHeight = actionsView.rowHeight
        let newHeight = min(max(0.0, rowHeight + delta), rowHeight)
        actionsHeightConstraint?.constant = newHeight
    }

    func configure(token: ApiToken?, sendAvailable: Bool, earnAvailable: Bool) {
        self.token = token
        self.sendAvailable = sendAvailable
        self.earnAvailable = earnAvailable
        updateActionsViewIfNeeded()
        applyConfiguration()
    }

    private func applyConfiguration() {
        guard let actionsView, let actionsHostView else { return }
        
        actionsView.token = token
        actionsView.fundAvailable = accountContext?.account.supportsReceive == true
        actionsView.sendAvailable = sendAvailable
        actionsView.earnAvailable = earnAvailable
        
        if actionsView.hasVisibleActions {
            if actionsHostView.isHidden {
                actionsHeightConstraint?.constant = actionsView.rowHeight
            }
            heightConstraint?.constant = actionsView.rowHeight + topInset
            actionsHostView.isHidden = false
        } else {
            heightConstraint?.constant = 4
            actionsHostView.isHidden = true
        }
    }
}
