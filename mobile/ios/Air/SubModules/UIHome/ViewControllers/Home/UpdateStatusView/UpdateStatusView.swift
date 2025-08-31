//
//  UpdateStatusView.swift
//  UIWalletHome
//
//  Created by Sina on 5/4/23.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

@MainActor
public class UpdateStatusView: UIStackView, WThemedView {
    
    public init() {
        super.init(frame: CGRect.zero)
        setupViews()
    }
    
    override public init(frame: CGRect) {
        fatalError()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var activityIndicator: WActivityIndicator!
    private var activityIndicatorContainer: UIStackView!
    private var statusLabel: WReplacableLabel!
    private let updatingColor = WTheme.secondaryLabel
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        spacing = 0
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44)
        ])

        alignment = .center
        activityIndicator = WActivityIndicator()
        activityIndicatorContainer = UIStackView()
        activityIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorContainer.addArrangedSubview(activityIndicator)
        addArrangedSubview(activityIndicatorContainer)
        statusLabel = WReplacableLabel()
        addArrangedSubview(statusLabel)
        
        updateTheme()
    }
    
    enum State: Equatable {
        case waitingForNetwork
        case updating
        case updated
    }
    
    private(set) var state: State = .updated
    private(set) var title: String = AccountStore.account?.displayName ?? ""
    
    func setState(newState: State, animatedWithDuration: TimeInterval?) {
        var duration = animatedWithDuration
        if let a = duration {
            duration = min(a, 0.2)
        }
        let newTitle = AccountStore.account?.displayName ?? ""
        state = newState
        title = newTitle
        let indicatorAlpha: CGFloat
        var nextFont: UIFont = .systemFont(ofSize: 17, weight: .semibold)
        switch newState {
        case .waitingForNetwork:
            indicatorAlpha = 1
            activityIndicator.startAnimating(animated: false)
            statusLabel.setText(lang("Waiting for network…"), animatedWithDuration: duration, animateResize: false) {
                UIView.animate(withDuration: 0.2, animations: {
                    self.statusLabel.leadingPadding = 4
                    self.statusLabel.label.font = nextFont
                    self.statusLabel.label.textColor = self.updatingColor
                    self.activityIndicatorContainer.alpha = 1
                })
            }
        case .updating:
            indicatorAlpha = 1
            activityIndicator.startAnimating(animated: false)
            statusLabel.setText(lang("Updating…"), animatedWithDuration: duration, animateResize: false) {
                self.statusLabel.leadingPadding = 4
                self.statusLabel.label.font = nextFont
                self.statusLabel.label.textColor = self.updatingColor
                UIView.animate(withDuration: 0.2, animations: {
                    self.activityIndicatorContainer.alpha = 1
                })
            }
        case .updated:
            indicatorAlpha = 0
            nextFont = .systemFont(ofSize: 17, weight: .semibold)
            statusLabel.setText(title, animatedWithDuration: duration, animateResize: false, wasHidden: false) {
                self.statusLabel.leadingPadding = 0
                self.statusLabel.label.font = nextFont
                self.statusLabel.label.textColor = WTheme.primaryLabel
                self.activityIndicator.stopAnimating(animated: false)
            }
        }
        let apply = {
            self.activityIndicatorContainer.alpha = indicatorAlpha
            self.activityIndicatorContainer.transform = indicatorAlpha == 0 ? CGAffineTransform(translationX: 0, y: -12) : .identity
        }
        if let duration {
            UIView.animate(withDuration: duration, animations: apply)
        } else {
            apply()
        }
    }
    
    public nonisolated func updateTheme() {
        DispatchQueue.main.async { [self] in
            activityIndicator.tintColor = updatingColor
            switch state {
            case .updated:
                statusLabel.label.textColor = WTheme.primaryLabel
            case .waitingForNetwork, .updating:
                statusLabel.label.textColor = updatingColor
            }
        }
    }
}
