//
//  SettingsHeaderView.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

let defaultHeight: CGFloat = 210.0
let avatarFromTop: CGFloat = 17.0
let walletInfoTop: CGFloat = 86.0

class SettingsHeaderView: WTouchPassView, WThemedView {
    
    private weak var vc: WViewController?
    init(vc: WViewController) {
        self.vc = vc
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var walletNameLeadingConstraint: NSLayoutConstraint!

    private var qrButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(named: "QRIcon", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate), for: .normal)
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            btn.isHidden = true
        }
        return btn
    }()
    
    private let blurView = WBlurView()
    
    private lazy var navBarView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        blurView.alpha = 0
        view.addSubview(blurView)
        view.addSubview(qrButton)
        qrButton.addTarget(self, action: #selector(qrPressed), for: .touchUpInside)
        NSLayoutConstraint.activate([
            blurView.leftAnchor.constraint(equalTo: view.leftAnchor),
            blurView.rightAnchor.constraint(equalTo: view.rightAnchor),
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            qrButton.heightAnchor.constraint(equalToConstant: 44),
            qrButton.widthAnchor.constraint(equalToConstant: 44),
            qrButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            qrButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6)
        ])
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            blurView.isHidden = true
        }
        return view
    }()
    
    private var avatarImageView: IconView = IconView(size: 100)
    
    private var avatarBlurView: WBlurredContentView = {
        let v = WBlurredContentView()
        return v
    }()
    
    private var walletNameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textAlignment = .center
        return label
    }()
    
    private let walletBalanceContainer: WSensitiveData<UILabel> = .init(cols: 8, rows: 2, cellSize: 8, cornerRadius: 4, theme: .adaptive, alignment: .leading)

    private var addressLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17)
        label.textAlignment = .center
        return label
    }()
    
    private var separatorDotLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17)
        label.textAlignment = .center
        label.text = "·"
        return label
    }()

    private var balanceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17)
        label.textAlignment = .center
        return label
    }()
    
    private lazy var descriptionStackView: UIStackView = {
        walletBalanceContainer.addContent(balanceLabel)
        let stackView = UIStackView(arrangedSubviews: [addressLabel, separatorDotLabel, walletBalanceContainer])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 4
        return stackView
    }()
    
    private lazy var walletInfoView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(walletNameLabel)
        view.addSubview(descriptionStackView)
        walletNameLeadingConstraint = walletNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([
            walletNameLabel.topAnchor.constraint(equalTo: view.topAnchor),
            walletNameLeadingConstraint,
            walletNameLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionStackView.topAnchor.constraint(equalTo: walletNameLabel.bottomAnchor, constant: 0),
            descriptionStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            descriptionStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            descriptionStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
        ])
        return view
    }()
    
    private var separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            view.isHidden = true
        }
        return view
    }()

    private var bottomConstraint: NSLayoutConstraint!
    private var avatarWidthConstraint: NSLayoutConstraint!
    private var avatarTopConstraint: NSLayoutConstraint!
    private var avatarCenterXConstraint: NSLayoutConstraint!
    private var walletInfoViewXConstraint: NSLayoutConstraint!
    private var walletInfoViewTopConstraint: NSLayoutConstraint!

    func setupViews(settingsVC: SettingsVC) {
        shouldAcceptTouchesOutside = true

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarBlurView)
        avatarBlurView.addSubview(avatarImageView)
        addSubview(navBarView)
        addSubview(walletInfoView)
        addSubview(separatorView)

        let safeAreaGuide = settingsVC.windowSafeAreaGuide
        
        bottomConstraint = bottomAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: defaultHeight)
        avatarTopConstraint = avatarImageView.topAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: 15)
        walletInfoViewTopConstraint = walletInfoView.topAnchor.constraint(equalTo: navBarView.bottomAnchor, constant: walletInfoTop)
        
        NSLayoutConstraint.activate([
            avatarTopConstraint,
            avatarImageView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            
            avatarBlurView.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -50),
            avatarBlurView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 50),
            avatarBlurView.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -50),
            avatarBlurView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 50),

            navBarView.topAnchor.constraint(equalTo: topAnchor),
            navBarView.leftAnchor.constraint(equalTo: leftAnchor),
            navBarView.rightAnchor.constraint(equalTo: rightAnchor),
            navBarView.bottomAnchor.constraint(equalTo: safeAreaGuide.topAnchor, constant: 40),
            
            walletInfoView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
            walletInfoView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -24),
            walletInfoViewTopConstraint,
            
            separatorView.bottomAnchor.constraint(equalTo: navBarView.bottomAnchor),
            separatorView.leftAnchor.constraint(equalTo: navBarView.leftAnchor),
            separatorView.rightAnchor.constraint(equalTo: navBarView.rightAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 0.33),

            bottomConstraint
        ])

        updateTheme()
        
        avatarImageView.isUserInteractionEnabled = true
        avatarImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(headerTapped)))
    }
    
    var tapCount = 0
    @objc private func headerTapped() {
        tapCount += 1
        if tapCount == 5 {
            WalletContextManager.delegate?.switchToCapacitor()
        }
    }

    public func updateTheme() {
        addressLabel.textColor = WTheme.secondaryLabel
        separatorDotLabel.textColor = WTheme.secondaryLabel
        balanceLabel.textColor = WTheme.secondaryLabel
        separatorView.backgroundColor = WTheme.separator
    }
    
    func config() {
        let account = AccountStore.account!
        avatarImageView.config(with: account)
        walletNameLabel.text = account.displayName
        updateDescriptionLabel()
    }
    
    func updateDescriptionLabel() {
        guard let account = AccountStore.account else {
            return
        }
        let formattedAddress = formatStartEndAddress(account.firstAddress)
        
        addressLabel.text = formattedAddress
        
        if let totalBalance = BalanceStore.accountBalanceData[account.id]?.totalBalance {
            balanceLabel.text = totalBalance.formatted(.baseCurrencyEquivalent)
            separatorDotLabel.isHidden = false
            walletBalanceContainer.isDisabled = false
            walletBalanceContainer.isHidden = false
        } else {
            separatorDotLabel.isHidden = true
            balanceLabel.text = ""
            walletBalanceContainer.isDisabled = true
            walletBalanceContainer.isHidden = true
        }
    }
    
    func update(scrollOffset: CGFloat) {
        let scrollMultiplier: CGFloat = scrollOffset > 0 ? 0.85 : 1
        avatarTopConstraint.constant = avatarFromTop - scrollOffset * scrollMultiplier

        let blurProgress: CGFloat = 1.0 - min(1.0, max(0.0, (155.0 - scrollOffset * scrollMultiplier) / 155.0))
        avatarBlurView.blurRadius = blurProgress * 30
        avatarImageView.alpha = min(1.0, max(0.0, (190.0 - scrollOffset * scrollMultiplier) / 40.0))
        
        blurView.alpha = min(1.0, max(0.0, (scrollOffset - 130.0) / 30.0))

        if scrollOffset < 0 {
            walletInfoViewTopConstraint.constant = walletInfoTop - scrollOffset
            if separatorView.alpha > 0 {
                UIView.animate(withDuration: 0.3) {
                    self.separatorView.alpha = 0
                    self.blurView.alpha = 1
                }
            }
            walletNameLabel.font = .systemFont(ofSize: 28, weight: .semibold)
            descriptionStackView.alpha = 1
            descriptionStackView.transform = .identity
        } else {
            let collapseProgress: CGFloat = min(1, scrollOffset / (defaultHeight - 50))
            walletInfoViewTopConstraint.constant = interpolate(from: walletInfoTop, to: S.walletInfoTopCollapsedConstant, progress: collapseProgress)
            walletNameLabel.font = .systemFont(ofSize: interpolate(from: 28, to: 17, progress: collapseProgress), weight: .semibold)
            descriptionStackView.alpha = 1 - collapseProgress
            let scale: CGFloat = 0.75 + 0.25 * (1 - collapseProgress)
            descriptionStackView.transform = .identity
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: 0, y: -7 * collapseProgress)
            let targetAlpha: CGFloat = collapseProgress < 1 ? 0 : 1
            if (targetAlpha < 1 && separatorView.alpha == 1) || (targetAlpha == 1 && separatorView.alpha < 1) {
                UIView.animate(withDuration: 0.3) {
                    self.separatorView.alpha = targetAlpha
                }
            }
            let additionalSpacing: CGFloat
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                additionalSpacing = 36
            } else {
                additionalSpacing = 16
            }
            walletNameLeadingConstraint.constant = 16 + collapseProgress * additionalSpacing
        }
    }
    
    @objc private func qrPressed() {
        AppActions.showReceive(chain: nil, title: lang("Your Address"))
    }
}

extension S {
    static var walletInfoTopCollapsedConstant: CGFloat {
        if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
            -29
        } else {
            -32.5
        }
    }
}
