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

let defaultHeight = 210.0
let avatarFromTop = 17.0
let walletInfoTop = 86.0

class SettingsHeaderView: WTouchPassView, WThemedView {
    
    private weak var vc: WViewController?
    init(vc: WViewController) {
        self.vc = vc
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var qrButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(named: "QRIcon", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate), for: .normal)
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
        NSLayoutConstraint.activate([
            walletNameLabel.topAnchor.constraint(equalTo: view.topAnchor),
            walletNameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            walletNameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
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
        return view
    }()

    private var bottomConstraint: NSLayoutConstraint!
    private var avatarWidthConstraint: NSLayoutConstraint!
    private var avatarTopConstraint: NSLayoutConstraint!
    private var avatarCenterXConstraint: NSLayoutConstraint!
    private var walletInfoViewXConstraint: NSLayoutConstraint!
    private var walletInfoViewTopConstraint: NSLayoutConstraint!

    func setupViews() {
        shouldAcceptTouchesOutside = true

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarBlurView)
        avatarBlurView.addSubview(avatarImageView)
        addSubview(navBarView)
        addSubview(walletInfoView)
        addSubview(separatorView)

        bottomConstraint = bottomAnchor.constraint(equalTo: superview!.safeAreaLayoutGuide.topAnchor, constant: defaultHeight)
        avatarTopConstraint = avatarImageView.topAnchor.constraint(equalTo: superview!.safeAreaLayoutGuide.topAnchor, constant: 15)
        walletInfoViewTopConstraint = walletInfoView.topAnchor.constraint(equalTo: navBarView.bottomAnchor, constant: walletInfoTop)

        NSLayoutConstraint.activate([
            avatarTopConstraint,
            avatarImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            
            avatarBlurView.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -50),
            avatarBlurView.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 50),
            avatarBlurView.topAnchor.constraint(equalTo: avatarImageView.topAnchor, constant: -50),
            avatarBlurView.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 50),

            navBarView.topAnchor.constraint(equalTo: topAnchor),
            navBarView.leftAnchor.constraint(equalTo: leftAnchor),
            navBarView.rightAnchor.constraint(equalTo: rightAnchor),
            navBarView.bottomAnchor.constraint(equalTo: superview!.safeAreaLayoutGuide.topAnchor, constant: 40),
            
            walletInfoView.centerXAnchor.constraint(equalTo: centerXAnchor),
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
        let formattedAddress = formatStartEndAddress(account.tonAddress ?? "")
        let currency = TokenStore.baseCurrency
        
        addressLabel.text = formattedAddress
        
        if let totalBalanceInBaseCurrency = BalanceStore.totalBalanceInBaseCurrency {
            let totalBalanceString = formatAmountText(amount: totalBalanceInBaseCurrency,
                                                      currency: currency?.sign,
                                                      decimalsCount: currency?.decimalsCount)
            balanceLabel.text = totalBalanceString
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
        let scrollMultiplier = scrollOffset > 0 ? 0.85 : 1
        avatarTopConstraint.constant = avatarFromTop - scrollOffset * scrollMultiplier

        let blurProgress = 1 - min(1, max(0, (155 - scrollOffset * scrollMultiplier) / 155))
        avatarBlurView.blurRadius = blurProgress * 30
        avatarImageView.alpha =  min(1, max(0, (190 - scrollOffset * scrollMultiplier) / 40))
        
        let blurAlpha = min(1, max(0, (scrollOffset - 130) / 30))
        blurView.alpha = blurAlpha

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
            let collapseProgress = min(1, scrollOffset / (defaultHeight - 50))
            walletInfoViewTopConstraint.constant = interpolate(from: walletInfoTop, to: -32.5, progress: collapseProgress)
            walletNameLabel.font = .systemFont(ofSize: interpolate(from: 28, to: 17, progress: collapseProgress), weight: .semibold)
            descriptionStackView.alpha = 1 - collapseProgress
            let scale = 0.75 + 0.25 * (1 - collapseProgress)
            descriptionStackView.transform = .identity
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: 0, y: -7 * collapseProgress)
            let targetAlpha: CGFloat = collapseProgress < 1 ? 0 : 1
            if (targetAlpha < 1 && separatorView.alpha == 1) || (targetAlpha == 1 && separatorView.alpha < 1) {
                UIView.animate(withDuration: 0.3) {
                    self.separatorView.alpha = targetAlpha
                }
            }
        }
    }
    
    @objc private func qrPressed() {
        AppActions.showReceive(chain: nil, showBuyOptions: false, title: lang("Your Address"))
    }
}

