//
//  BottomActionsView.swift
//  UICreateWallet
//
//  Created by Sina on 4/14/23.
//

import UIKit

public struct BottomAction {
    var title: String
    var onPress: () -> ()
    public init(title: String, onPress: @escaping () -> Void) {
        self.title = title
        self.onPress = onPress
    }
}

public class BottomActionsView: UIView {

    static let buttonsSpacing = CGFloat(16)
    public static var reserveHeight: CGFloat {
        WButton.height(for: .primary) + BottomActionsView.buttonsSpacing
    }

    public init(primaryAction: BottomAction,
         secondaryAction: BottomAction? = nil,
         // if `reserveSecondaryActionHeight` be true, on nil secondaryAction, the view will reserve the secondaryAction's height.
         reserveSecondaryActionHeight: Bool = true) {
        super.init(frame: CGRect.zero)
        setupView(primaryAction: primaryAction, secondaryAction: secondaryAction, reserveSecondaryActionHeight: reserveSecondaryActionHeight)
    }
    
    override init(frame: CGRect) {
        fatalError()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private var primaryAction: BottomAction? = nil
    private var secondaryAction: BottomAction? = nil
    public var primaryButton: WButton!
    public var secondaryButton: WButton!

    private func setupView(primaryAction: BottomAction,
                           secondaryAction: BottomAction? = nil,
                           reserveSecondaryActionHeight: Bool = true) {
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        
        translatesAutoresizingMaskIntoConstraints = false
        
        // add primary action
        primaryButton = WButton(style: .primary)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        primaryButton.setTitle(primaryAction.title, for: .normal)
        primaryButton.addTarget(self, action: #selector(primaryPressed(_:)), for: .touchUpInside)
        addSubview(primaryButton)
        NSLayoutConstraint.activate([
            primaryButton.topAnchor.constraint(equalTo: topAnchor),
            primaryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // secondary button
        if let secondaryAction {
            secondaryButton = WButton(style: .clearBackground)
            secondaryButton.translatesAutoresizingMaskIntoConstraints = false
            secondaryButton.setTitle(secondaryAction.title, for: .normal)
            secondaryButton.titleLabel?.applyTextStyle(.button)
            secondaryButton.addTarget(self, action: #selector(secondaryPressed(_:)), for: .touchUpInside)
            addSubview(secondaryButton)
            NSLayoutConstraint.activate([
                secondaryButton.topAnchor.constraint(equalTo: primaryButton.bottomAnchor, constant: BottomActionsView.buttonsSpacing),
                secondaryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
                secondaryButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                secondaryButton.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            primaryButton.bottomAnchor.constraint(equalTo: bottomAnchor,
                                                  constant: reserveSecondaryActionHeight ? -BottomActionsView.reserveHeight : 0).isActive = true
        }
    }
    
    @objc func primaryPressed(_ sender: UIButton) {
        primaryAction?.onPress()
    }

    @objc func secondaryPressed(_ sender: UIButton) {
        secondaryAction?.onPress()
    }
}
