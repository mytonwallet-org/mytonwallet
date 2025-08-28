//
//  WalletCardView.swift
//  UIHome
//
//  Created by Sina on 7/10/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Popovers
import SwiftUIIntrospect

private let log = Log("WalletCardView")
internal let defaultGradientRect = CGRect(x: 0, y: 0, width: 220, height: 100)


public class WalletCardView: WTouchPassView {
    
    public static var defaultState: State = .expanded
    public static var expansionOffset = CGFloat(40)
    public static var collapseOffset = CGFloat(10)
    
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    private weak var balanceHeaderView: BalanceHeaderView?
    private var currentNft: ApiNft? { AccountStore.currentAccountCardBackgroundNft }
    
    var expandHeader: (() -> ())?
    var makeMenu: ((_ address: String) -> UIMenu)?
    
    init() {
        super.init(frame: .zero)
        setupViews()
        prepareFeedbackGenerator()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func prepareFeedbackGenerator() {
        DispatchQueue.global(qos: .background).async {
            let start = Date()
            let g = UIImpactFeedbackGenerator(style: .soft)
            self.feedbackGenerator = g
            g.prepare()
            log.info("prepare vibrate took \(Date().timeIntervalSince(start)) isMainThread=\(Thread.isMainThread)")
        }
    }
    
    // MARK: - States and Variables
    // Updated from balance header view, on scroll
    func setScrollOffset(to scrollOffset: CGFloat, isTracking: Bool?, forceIsTracking: Bool) {
        if scrollOffset <= -WalletCardView.expansionOffset, state == .collapsed {
            if (!forceIsTracking && isTracking == false) {
                return
            }
            state = .expanded
            feedbackGenerator?.impactOccurred()
        } else if state == .expanded, scrollOffset >= WalletCardView.collapseOffset {
            state = .collapsed
            feedbackGenerator?.impactOccurred()
        }
    }
    public enum State {
        case collapsed
        case expanded
    }
    private(set) var state = defaultState {
        didSet {
            guard state != oldValue else {
                return
            }
            UIView.animate(withDuration: 0.25) {
                self.layoutCardConstraints()
                self.superview?.layoutIfNeeded()
                self.upgradeCardButton.alpha = self.state == .collapsed ? 0 : 0.75
            } completion: { _ in
                self.delayedState = self.state
            }
            UIView.animate(withDuration: 0.1, delay: state == .collapsed ? 0.15 : 0) {
                self.miniPlaceholders.alpha = self.state == .collapsed ? 1 : 0
                self.cardBackground.update(state: self.state)
            } completion: { _ in
                self.delayedState = self.state
            }
            UIView.animate(withDuration: 0.25, delay: 0) {
                let scale = (1 / WAnimatedAmountLabelConfig.cardToBalanceHeaderRatio) * 0.85
                self.balanceCopyContainer.transform = self.state == .expanded ? .identity : .identity.scaledBy(x: scale, y: scale).translatedBy(x: 10, y: 0)
            }
            
        }
    }
    private(set) var delayedState = defaultState
    var statusViewState: UpdateStatusView.State = .updated {
        didSet {
            updateContentAlpha()
        }
    }
    
    private var balanceTopConstant: CGFloat {
        if let window, window.frame.width > 410 {
            72
        } else {
            62
        }
    }
    
    func layoutCardConstraints() {
        if let balanceHeaderView {
            balanceHeaderView.walletCardViewPreferredBottomConstraint.constant = state == .expanded ? 1000 : -28
            widthConstraint.constant = state == .expanded ? balanceHeaderView.frame.width - 32 : 34
            balanceTopConstraint.constant = state == .expanded ? balanceTopConstant : 1000
            layer.cornerRadius = state == .expanded ? 16 : 3
            //        superview?.layoutIfNeeded()
        }
    }
    
    public override func didMoveToSuperview() {
        if let balanceHeaderView = superview as? BalanceHeaderView {
            self.balanceHeaderView = balanceHeaderView
            layoutCardConstraints()
            
            NSLayoutConstraint.activate([
                balanceCopyBlurView.leadingAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.leadingAnchor),
                balanceCopyBlurView.trailingAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.trailingAnchor),
                balanceCopyBlurView.topAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.topAnchor),
                balanceCopyBlurView.bottomAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.bottomAnchor),

                balanceWithArrow.centerXAnchor.constraint(equalTo: balanceHeaderView.balanceView.centerXAnchor),
                balanceCopyView.centerYAnchor.constraint(equalTo: balanceHeaderView.balanceView.centerYAnchor),
                
                walletChangeBackground.centerXAnchor.constraint(equalTo: balanceHeaderView.walletNameLabelSkeleton.centerXAnchor),
            ])
        }
    }
    
    // MARK: - Views
    private var cardBackground = CardBackground()
    
    private var balanceCopyContainer: WSensitiveData<UIView> = .init(cols: 12, rows: 3, cellSize: 12, cornerRadius: 10, theme: .light, alignment: .center)
    
    var balanceCopyBlurView: UIView = {
        //let blurEffect = UIBlurEffect(style: .light)
        let blurEffectView = UIView()
        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        blurEffectView.layer.cornerRadius = 8
        blurEffectView.layer.masksToBounds = true
        blurEffectView.backgroundColor = .white.withAlphaComponent(0.1)
        return blurEffectView
    }()
    
    var balanceCopyView: BalanceView = {
        let b = BalanceView(config: .card)
        b.alignment = .center
        return b
    }()
    
    private var chevron: UIImageView?
    
    private var menuContext = MenuContext()
    
    lazy var balanceWithArrow: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(balanceCopyView)
        view.accessibilityIdentifier = "balanceWithArrow"
        let chevron = UIImageView(image: .airBundle("ChevronDown18"))
        chevron.contentMode = .center
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        self.chevron = chevron
        chevron.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chevron)
        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: balanceCopyView.trailingAnchor, constant: 4),
            chevron.bottomAnchor.constraint(equalTo: balanceCopyView.bottomAnchor, constant: -2.333),
            
            balanceCopyView.topAnchor.constraint(equalTo: view.topAnchor),
            balanceCopyView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chevron.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            balanceCopyView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        chevron.alpha = 0.75
        chevron.tintColor = .white
        view.alpha = 0
        
        let tapTarget = HostingView(ignoreSafeArea: true) {
            Color.clear.contentShape(.rect)
                .menuSource(isEnabled: true, coordinateSpace: .global, menuContext: menuContext)
                .task {
                    self.menuContext.setMenu {
                        CurrencyMenu()
                    }
                }
        }
        view.addSubview(tapTarget)
        NSLayoutConstraint.activate([
            
            tapTarget.topAnchor.constraint(equalTo: view.topAnchor),
            tapTarget.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tapTarget.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tapTarget.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        return view
    }()
    
    var walletChangeBackground: UIView = {
        //let blurEffect = UIBlurEffect(style: .light)
        let blurEffectView = UIView()
        blurEffectView.translatesAutoresizingMaskIntoConstraints = false
        blurEffectView.layer.cornerRadius = 13
        blurEffectView.layer.masksToBounds = true
        blurEffectView.backgroundColor = .white.withAlphaComponent(0.1)
        return blurEffectView
    }()
    
    var walletChangeBlurViewMinWidthConstraint: NSLayoutConstraint!
    
    private var walletChangeContainer: WSensitiveData<UIView> = .init(cols: 14, rows: 2, cellSize: 13, cornerRadius: 13, theme: .light, alignment: .center)
    
    var walletChangeLabel: LTMorphingLabel = {
        let lbl = LTMorphingLabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .rounded(ofSize: 17, weight: .medium)
        lbl.alpha = 0.8
        NSLayoutConstraint.activate([
            lbl.heightAnchor.constraint(equalToConstant: 26),
        ])
        return lbl
    }()

    let addressView = CardAddressView()
    
    let upgradeCardButton: UIButton = {
        let button = WButton(type: .system)
        button.setImage(.airBundle("HomeMagic26"), for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 44),
            button.heightAnchor.constraint(equalToConstant: 44),
        ])
        button.tintColor = .white
        button.alpha = 0.75
        button.backgroundColor = .clear
        return button
    }()

    // Mini placeholers are shown in collapsed wallet card view
    private lazy var miniPlaceholders: CardMiniPlaceholders = CardMiniPlaceholders(state: .expanded)

    private lazy var contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(cardBackground)
        v.addSubview(balanceCopyBlurView)
        balanceCopyContainer.addContent(balanceWithArrow)
        v.addSubview(balanceCopyContainer)
        
        v.addSubview(walletChangeContainer)
        walletChangeContainer.addContent(walletChangeBackground)
        walletChangeBackground.addSubview(walletChangeLabel)
        
        v.addSubview(addressView)
        v.addSubview(upgradeCardButton)
        v.addSubview(miniPlaceholders)
        
        walletChangeBlurViewMinWidthConstraint = walletChangeBackground.widthAnchor.constraint(greaterThanOrEqualToConstant: 80)
        
        NSLayoutConstraint.activate([
            cardBackground.topAnchor.constraint(equalTo: v.topAnchor),
            cardBackground.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            cardBackground.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            cardBackground.trailingAnchor.constraint(equalTo: v.trailingAnchor),

            walletChangeBackground.topAnchor.constraint(equalTo: balanceCopyView.bottomAnchor, constant: 16),
            walletChangeBackground.heightAnchor.constraint(equalToConstant: 26),
            walletChangeBlurViewMinWidthConstraint,

            walletChangeLabel.leadingAnchor.constraint(equalTo: walletChangeBackground.leadingAnchor, constant: 8),
            walletChangeLabel.trailingAnchor.constraint(equalTo: walletChangeBackground.trailingAnchor, constant: -8),
            walletChangeLabel.centerYAnchor.constraint(equalTo: walletChangeBackground.centerYAnchor, constant: -0.6),

            // Force address to animate vertically with balance view
            addressView.bottomAnchor.constraint(greaterThanOrEqualTo: balanceCopyView.topAnchor, constant: 100 + addressView.walletAddressPadding),
            // Preffer it to be on bottom
            addressView.label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -17).withPriority(.defaultHigh),
            
            upgradeCardButton.bottomAnchor.constraint(greaterThanOrEqualTo: addressView.bottomAnchor),
            upgradeCardButton.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4).withPriority(.defaultHigh),
            upgradeCardButton.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -3).withPriority(.defaultHigh),

            miniPlaceholders.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            miniPlaceholders.topAnchor.constraint(equalTo: v.topAnchor).withPriority(.defaultHigh),
        ])
        addressView.update(currentNft: self.currentNft)
        return v
    }()

    private var widthConstraint: NSLayoutConstraint!
    private var balanceTopConstraint: NSLayoutConstraint!
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.masksToBounds = true
        addSubview(contentView)

        widthConstraint = widthAnchor.constraint(equalToConstant: 34)
        balanceTopConstraint = balanceCopyView.topAnchor.constraint(lessThanOrEqualTo: topAnchor, constant: 1000)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: 208/358),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),

            balanceCopyView.centerXAnchor.constraint(lessThanOrEqualTo: centerXAnchor),
            balanceTopConstraint,

            walletChangeBackground.centerXAnchor.constraint(equalTo: centerXAnchor),

            // Lets make it feel that address was already there and the card view is just containing it when expanding.
            addressView.centerXAnchor.constraint(equalTo: centerXAnchor),

            //miniPlaceholders.topAnchor.constraint(lessThanOrEqualTo: delegate!.topAnchor, constant: 52)
        ])

        addressView.addTarget(self, action: #selector(_addressPressed), for: .touchUpInside)
        addressView.showsMenuAsPrimaryAction = false

        upgradeCardButton.addTarget(self, action: #selector(onUpgradeCardTap), for: .primaryActionTriggered)

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped)))
        setupTapGestures()
    }
    
    // MARK: - Update methods
    
    func set(balanceChangeText: String?, animated: Bool = true) {
        guard walletChangeLabel.text != balanceChangeText || (balanceChangeText == "" && walletChangeBackground.alpha == 1) else {
            return
        }
        walletChangeLabel.morphingEnabled = animated == false ? false : (walletChangeLabel.text != nil)
        walletChangeLabel.text = balanceChangeText
        walletChangeLabel.textColor = gradientColor(in: walletChangeLabel.bounds)
        walletChangeBlurViewMinWidthConstraint.isActive = balanceChangeText?.nilIfEmpty == nil
        if balanceChangeText == "", walletChangeBackground.alpha == 1 {
            if animated {
                UIView.animate(withDuration: 0.1) {
                    self.walletChangeBackground.alpha = 0
                }
            } else {
                self.walletChangeBackground.alpha = 0
            }
        } else if balanceChangeText != "", walletChangeBackground.alpha < 1 {
            if animated {
                UIView.animate(withDuration: 0.1) {
                    self.walletChangeBackground.alpha = 1
                }
            } else {
                self.walletChangeBackground.alpha = 1
            }
        }
        walletChangeLabel.invalidateIntrinsicContentSize()
    }

    func updateWithCurrentNft(accountChanged: Bool) {
        
        cardBackground.update(accountId: AccountStore.accountId, nft: currentNft, accountChanged: accountChanged)
        
        // Set gradient on balanceCopyView
        if let nft = currentNft {
            let gradientColors = nft.gradientColors()
            balanceCopyView.setGradientColors(leftColor: gradientColors.startColor, rightColor: gradientColors.endColor, startPoint: gradientColors.startPoint)
            upgradeCardButton.tintColor = gradientColors.endColor
        } else {
            balanceCopyView.setGradientColors(leftColor: .white, rightColor: .white)
            upgradeCardButton.tintColor = .white
        }
        
        chevron?.tintColor = currentNft?.gradientColors().endColor ?? .white
        addressView.update(currentNft: currentNft)
        setNeedsLayout()
        setNeedsDisplay()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        for view in miniPlaceholders.subviews {
            view.backgroundColor = gradientColor(in: view.bounds)
        }
        walletChangeLabel.textColor = currentNft?.gradientColor(in: walletChangeLabel.bounds) ?? .white
    }
    
    private func animateAlpha(to alpha: CGFloat) {
        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            self?.contentView.alpha = alpha
        })
    }

    private var currentAlpha = 1
    private func updateContentAlpha() {
        if state == .collapsed {
            // Card view may be above stateView, so hide it if required
            switch statusViewState {
            case .waitingForNetwork, .updating:
                if currentAlpha == 1 {
                    currentAlpha = 0
                    animateAlpha(to: 0)
                }
            case .updated:
                if currentAlpha == 0 {
                    currentAlpha = 1
                    animateAlpha(to: 1)
                }
            }
        } else {
            if currentAlpha == 0 {
                currentAlpha = 1
                animateAlpha(to: 1)
            }
        }
    }

    @objc private func cardTapped() {
        if state == .collapsed {
            expandHeader?()
        }
    }

    func gradientColor(in rect: CGRect?) -> UIColor {
        currentNft?.gradientColor(in: rect ?? defaultGradientRect) ?? .white
    }
    
    // MARK: Balance context menu
    
    func setupTapGestures() {
        balanceWithArrow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onBalanceTap)))
    }
    
    private var dismissMenu: (() -> ())?
    
    func setBaseCurrency(_ bc: MBaseCurrency) {
        dismissMenu?()
        dismissMenu = nil
        Task {
            do {
                try await TokenStore.setBaseCurrency(currency: bc)
            } catch {
            }
        }
    }
    
    @objc func onBalanceTap() {
        let amountBc = BalanceStore.currentAccountBalanceData?.totalBalance ?? 0
        let exchangeRate1 = TokenStore.getExchangeRate(currency: TokenStore.baseCurrency ?? .USD)
        let amountUsd = amountBc / exchangeRate1
        
        let menu = Templates.UIKitMenu(
            sourceView: balanceWithArrow,
            configuration: { config in
                config.hapticFeedbackEnabled = true
            },
            content: {
                Templates.DividedVStack {
                    ForEach(MBaseCurrency.allCases) { bc in
                        
                        let exchangeRate = TokenStore.getExchangeRate(currency: bc)
                        let a = amountUsd * exchangeRate
                        let amount = BaseCurrencyAmount.fromDouble(a, bc)
                        
                        Templates.MenuItem({ [weak self] in self?.setBaseCurrency(bc)}) { pressed in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bc.name)
                                        .font(.system(size: 17))
                                    Text(amount.formatted())
                                        .font(.system(size: 15))
                                        .padding(.bottom, 1)
                                        .foregroundStyle(Color(WTheme.secondaryLabel))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if bc == TokenStore.baseCurrency {
                                    Image.airBundle("BaseCurrencyCheckmark")
                                }
                            }
                            .foregroundStyle(Color(WTheme.primaryLabel))
                            .padding(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                            .background(pressed ? Templates.buttonHighlightColor : Color.clear)
                        }
                    }
                }
            },
            fadeLabel: nil
        )
        dismissMenu = {
            menu.dismiss()
        }
        menu.present()
    }
    
    
    // MARK: - Address info
    
    @objc private func _addressPressed() {
        let isMultichain = AccountStore.account?.isMultichain == true
        if isMultichain {
            showAddressesMenu()
        } else {
            UIPasteboard.general.string = AccountStore.account?.firstAddress
            topWViewController()?.showToast(animationName: "Copy", message: lang("Address was copied to clipboard."))
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }
    
    func showAddressesMenu() {
        
        let menu = Templates.UIKitMenu(
            sourceView: addressView,
            configuration: { config in
                config.hapticFeedbackEnabled = true
                config.width = min(280, self.bounds.width - 48)
                config.sourceFrameInset = .init(top: 0, left: 0, bottom: 6, right: 0)
            },
            content: {
                AddressesMenuContent(dismiss: {
                    self.dismissMenu?()
                })
            },
            fadeLabel: nil
        )
        dismissMenu = {
            menu.dismiss()
        }
        menu.present()
    }
    
    // MARK: - Upgrade card
    
    
    @objc func onUpgradeCardTap() {
        AppActions.showUpgradeCard()
    }
}



struct CurrencyMenu: View {
    
    @EnvironmentObject private var menuContext: MenuContext
    
    var body: some View {
        ScrollableMenuContent {
            DividedVStack {
                let amountBc = BalanceStore.currentAccountBalanceData?.totalBalance ?? 0
                let exchangeRate1 = TokenStore.getExchangeRate(currency: TokenStore.baseCurrency ?? .USD)
                let amountUsd = amountBc / exchangeRate1
                
                ForEach(MBaseCurrency.allCases) { bc in
                    let exchangeRate = TokenStore.getExchangeRate(currency: bc)
                    let a = amountUsd * exchangeRate
                    let amount = BaseCurrencyAmount.fromDouble(a, bc)
                    
                    SelectableMenuItem(id: bc.rawValue, action: {
                        Task {
                            do {
                                try await TokenStore.setBaseCurrency(currency: bc)
                            } catch {
                            }
                        }
                        menuContext.dismiss()
                        
                    }, content: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bc.name)
                                    .font(.system(size: 17))
                                Text(amount.formatted())
                                    .font(.system(size: 15))
                                    .padding(.bottom, 1)
                                    .foregroundStyle(Color(WTheme.secondaryLabel))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            if bc == TokenStore.baseCurrency {
                                Image.airBundle("BaseCurrencyCheckmark")
                            }
                        }
                        .foregroundStyle(Color(WTheme.primaryLabel))
                        .padding(EdgeInsets(top: -3, leading: 0, bottom: -3, trailing: 0))
                    })
                }
            }
        }
    }
}
