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
import Dependencies
import SwiftNavigation

public final class UpdateStatusView: UIStackView {
    
    public let accountContext: AccountContext
    
    public init(accountContext: AccountContext) {
        self.accountContext = accountContext
        super.init(frame: .zero)
        setupViews()
        setupObservers()
    }

    public convenience init(accountSource: AccountSource) {
        self.init(accountContext: AccountContext(source: accountSource))
    }
    
    public override init(frame: CGRect) {
        fatalError()
    }
    
    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var activityIndicator: WActivityIndicator!
    private var activityIndicatorContainer: UIView!
    private var statusLabel: UILabel!
    private let updatingColor = UIColor.air.secondaryLabel
    private var arrowImage = UIImageView(image: .airBundle("HomeTitleArrow"))
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        spacing = 2
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44)
        ])

        alignment = .center
        activityIndicator = WActivityIndicator()
        activityIndicatorContainer = UIStackView()
        activityIndicatorContainer.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorContainer.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.topAnchor.constraint(equalTo: activityIndicatorContainer.topAnchor),
            activityIndicator.leadingAnchor.constraint(equalTo: activityIndicatorContainer.leadingAnchor),
            activityIndicator.trailingAnchor.constraint(equalTo: activityIndicatorContainer.trailingAnchor, constant: -4),
            activityIndicator.bottomAnchor.constraint(equalTo: activityIndicatorContainer.bottomAnchor),
        ])
        addArrangedSubview(activityIndicatorContainer)
        statusLabel = UILabel()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.allowsDefaultTighteningForTruncation = true
        addArrangedSubview(statusLabel)
        
        arrowImage.tintColor = UIColor.label
        arrowImage.setContentCompressionResistancePriority(.required, for: .horizontal)
        arrowImage.contentMode = .center
        addArrangedSubview(arrowImage, margin: UIEdgeInsets(top: 0, left: 4, bottom: -1, right: 0))
        
        let g = UITapGestureRecognizer(target: self, action: #selector(onTap))
        addGestureRecognizer(g)
    }

    private func setupObservers() {
        observe { [weak self] in
            guard let self else { return }
            _ = accountContext.account.displayName
            guard state == .updated || title.isEmpty else { return }
            setState(newState: state, animatedWithDuration: title.isEmpty ? nil : 0.2)
        }
    }
    
    @objc func onTap() {
        AppActions.showWalletSettings()
    }
    
    public enum State: Equatable {
        case waitingForNetwork
        case updating
        case updated
    }
    
    private(set) var state: State = .updated
    private(set) var title: String = ""
    private var currentAnimator: UIViewPropertyAnimator?
    private var animationCompletionHandler: (() -> Void)?

    public func setState(newState: State, animatedWithDuration duration: TimeInterval?) {
        let currentDisplayName = accountContext.account.displayName
        if state == newState &&
           (state != .updated || title == currentDisplayName) {
            return
        }
        var duration = duration
        if title.isEmpty {
            duration = nil
        }
        state = newState

        func applyNewTextIfCurrent() {
            title = currentDisplayName

            switch newState {
            case .waitingForNetwork:
                applyLoadingStyle()
                setText(lang("Waiting for network…"), animatedWithDuration: duration)

            case .updating:
                applyLoadingStyle()
                setText(lang("Updating…"), animatedWithDuration: duration)

            case .updated:
                applyUpdatedStyle()
                setText(title, animatedWithDuration: duration)
            }
        }

        if let d = duration, d > 0 {
            animationCompletionHandler = {
                applyNewTextIfCurrent()
                self.animationCompletionHandler = nil
            }

            if currentAnimator?.isRunning == true {
                return
            }

            let animator = UIViewPropertyAnimator(duration: d, curve: .easeInOut) {
                self.transform = CGAffineTransform(translationX: 0, y: -12)
                self.alpha = 0
            }
            currentAnimator = animator
            animator.addCompletion { [weak self] _ in
                self?.animationCompletionHandler?()
            }
            animator.startAnimation()
        } else {
            animationCompletionHandler = nil
            currentAnimator?.stopAnimation(true)
            currentAnimator = nil
            applyNewTextIfCurrent()
        }
    }

    private func applyLoadingStyle() {
        activityIndicator.startAnimating(animated: false)
        activityIndicatorContainer.isHidden = false
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = updatingColor
        arrowImage.isHidden = true
    }
    
    private func applyUpdatedStyle() {
        activityIndicator.stopAnimating(animated: false)
        activityIndicatorContainer.isHidden = true
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = UIColor.label
        arrowImage.isHidden = false
    }
    
    private func setText(_ text: String, animatedWithDuration: TimeInterval?) {
        statusLabel.text = text
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: animatedWithDuration ?? 0,
                                                       delay: 0,
                                                       options: [],
                                                       animations: { [weak self] in
            guard let self else { return }
            alpha = 1
            transform = .identity
        })
    }
}
