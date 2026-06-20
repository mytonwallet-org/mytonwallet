import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext

final class TokenActionsCell: FirstRowCell {
    private var actionsView: TokenActionsView?
    private var heightConstraint: NSLayoutConstraint?
    private var actionsHeightConstraint: NSLayoutConstraint?
    private var installedConstraints: [NSLayoutConstraint] = []
    private var accountContext: AccountContext?
    private var token: ApiToken?
    private var sendAvailable = false
    private var swapAvailable = false
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
        actionsView?.removeFromSuperview()

        let actionsView = TokenActionsView(
            accountContext: accountContext,
            token: token,
            usesSplitHomeActionStyle: usesSplitHomeActionStyle
        )
        self.actionsView = actionsView
        contentView.addSubview(actionsView)

        let actionsHeightConstraint = actionsView.heightAnchor.constraint(equalToConstant: actionsView.rowHeight)
        self.actionsHeightConstraint = actionsHeightConstraint

        let heightConstraint = contentView.heightAnchor.constraint(equalToConstant: actionsView.rowHeight + topInset)
        heightConstraint.priority = .defaultHigh
        self.heightConstraint = heightConstraint

        var constraints: [NSLayoutConstraint] = [
            actionsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionsHeightConstraint,
            heightConstraint,
        ]
        if usesSplitHomeActionStyle {
            constraints.append(actionsView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor))
        } else {
            let horizontalInset = S.insetSectionHorizontalMargin
            constraints.append(contentsOf: [
                actionsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                actionsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
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

    func configure(token: ApiToken?, sendAvailable: Bool, swapAvailable: Bool, earnAvailable: Bool) {
        self.token = token
        self.sendAvailable = sendAvailable
        self.swapAvailable = swapAvailable
        self.earnAvailable = earnAvailable
        updateActionsViewIfNeeded()
        applyConfiguration()
    }

    private func applyConfiguration() {
        guard let actionsView else { return }
        
        actionsView.token = token
        actionsView.sendAvailable = sendAvailable
        actionsView.swapAvailable = swapAvailable
        actionsView.earnAvailable = earnAvailable
        
        if actionsView.hasVisibleActions {
            actionsHeightConstraint?.constant = actionsView.rowHeight
            heightConstraint?.constant = actionsView.rowHeight + topInset
            actionsView.isHidden = false
        } else {
            heightConstraint?.constant = 4
            actionsView.isHidden = true
        }
    }
}
