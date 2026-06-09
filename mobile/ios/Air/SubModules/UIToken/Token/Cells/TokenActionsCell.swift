import UIKit
import UIActivityList
import UIComponents
import WalletCore
import WalletContext

final class TokenActionsCell: FirstRowCell {
    private var actionsView: TokenActionsView?
    private var heightConstraint: NSLayoutConstraint!
    private var actionsHeightConstraint: NSLayoutConstraint!
    private let topInset = CGFloat(16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setup(accountContext: AccountContext, token: ApiToken?) {
        guard actionsView == nil else { return }
        
        let actionsView = TokenActionsView(accountContext: accountContext, token: token)
        self.actionsView = actionsView
        contentView.addSubview(actionsView)
        
        actionsHeightConstraint = actionsView.heightAnchor.constraint(equalToConstant: TokenActionsView.rowHeight)

        heightConstraint = contentView.heightAnchor.constraint(equalToConstant: TokenActionsView.rowHeight + topInset)
        heightConstraint.priority = .defaultHigh

        var constraints: [NSLayoutConstraint] = [
            actionsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionsHeightConstraint,
            heightConstraint,
        ]
        if TokenActionsView.usesSplitHomeActionStyle {
            constraints.append(actionsView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor))
        } else {
            let horizontalInset = S.insetSectionHorizontalMargin
            constraints.append(contentsOf: [
                actionsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: horizontalInset),
                actionsView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -horizontalInset),
            ])
        }
        
        NSLayoutConstraint.activate(constraints)
    }
    
    func reduceButtonHeightFor(_ delta: CGFloat) {
        if !TokenActionsView.usesSplitHomeActionStyle {
            let newHeight = min(max(0.0, TokenActionsView.rowHeight + delta), TokenActionsView.rowHeight)
            actionsHeightConstraint.constant = newHeight
        }
    }

    func configure(token: ApiToken?, fundAvailable: Bool, sendAvailable: Bool, swapAvailable: Bool, earnAvailable: Bool) {
        guard let actionsView else { return }
        
        actionsView.token = token
        actionsView.sendAvailable = sendAvailable
        actionsView.swapAvailable = swapAvailable
        actionsView.earnAvailable = earnAvailable
        actionsView.fundAvailable = fundAvailable
        
        if actionsView.hasVisibleActions {
            heightConstraint.constant = TokenActionsView.rowHeight + topInset
            actionsView.isHidden = false
        } else {
            heightConstraint.constant = 4
            actionsView.isHidden = true
        }
    }
}
