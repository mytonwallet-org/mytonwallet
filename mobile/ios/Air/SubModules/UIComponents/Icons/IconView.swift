//
//  IconView.swift
//  UIComponents
//
//  Created by Sina on 4/18/24.
//

import SwiftUI
import UIKit
import WalletCore
import WalletContext
import Kingfisher

private let log = Log("IconView")
private let stockTokenCornerRadiusRatio: CGFloat = 0.3

public class IconView: UIView {
    private static let labelFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    private static let tokenPlaceholderTextColor = UIColor.air.secondaryLabel
    private static let tokenPlaceholderBorderColor = UIColor.air.secondaryLabel.withAlphaComponent(0.5)
    private static let tokenLoadingPlaceholderColor = UIColor.air.secondaryLabel.withAlphaComponent(0.08)

    private enum IconShape {
        case circle
        case roundedSquare
        case rectangle

        func cornerRadius(for size: CGFloat) -> CGFloat {
            switch self {
            case .circle:
                size / 2
            case .roundedSquare:
                size * stockTokenCornerRadiusRatio
            case .rectangle:
                0
            }
        }

        func maskPath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
            switch self {
            case .circle:
                return UIBezierPath(ovalIn: rect).cgPath
            case .roundedSquare:
                return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .path(in: rect)
                    .cgPath
            case .rectangle:
                return CGPath(rect: rect, transform: nil)
            }
        }
    }
    
    private(set) public var imageView: UIImageView!
        
    private var gradientLayer: CAGradientLayer!
    
    private var largeLabel: UILabel!
    private var tokenPlaceholderLabel: UILabel!
    private var tokenPlaceholderBorderLayer: CAShapeLayer!
    
    private var smallLabelTop: UILabel!
    private var smallLabelBottom: UILabel!
    private var smallLabelGuide: UILayoutGuide!
    private var smallLabelTopBottomConstraint: NSLayoutConstraint!
    
    private var size: CGFloat = 40
    private var sizeConstraints: [NSLayoutConstraint] = []
    
    private var imageViewChainCutoutMask: CAShapeLayer?
    private var gradientChainCutoutMask: CAShapeLayer?
    private var chainAccessoryMaskContextIconGeometry: IconAccessoryView.LayoutGeometry? = nil
    private var chainAccessoryMaskContextSize: CGFloat? = nil
    private var chainAccessoryMaskContextCornerRadius: CGFloat? = nil
    private let chainAccessoryView: IconAccessoryView
    
    private var resolveGradientColors: (() -> [CGColor]?)?
    private var iconShape: IconShape = .circle
    
    private var cachedActivityId: String?
    private var cachedAccountAvatarURL: URL?
    private var currentAccountPlaceholder: MAccount?
    private var accountAvatarState: AccountAvatarState = .none
    private var accountAvatarRetryWorkItem: DispatchWorkItem?
    private var cachedTokenSlug: String?
    private var cachedTokenImageURL: String?
    private var tokenImageState: TokenImageState = .none

    private enum AccountAvatarState {
        case none
        case loading
        case loaded
        case failed
        case unavailable
    }

    private enum TokenImageState {
        case none
        case loading
        case loaded
        case failed
    }
    
    public init(size: CGFloat, accessoryGeometry: IconAccessoryView.LayoutGeometry? = nil) {
        chainAccessoryView = IconAccessoryView(layoutGeometry: accessoryGeometry)
        
        super.init(frame: CGRect.square(size))

        setupView()
        setSize(size)
    }
    
    required public init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        
        // add symbol image
        imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 20
        imageView.layer.cornerCurve = .continuous
        imageView.layer.masksToBounds = true
        imageView.tintAdjustmentMode = .normal
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leftAnchor.constraint(equalTo: leftAnchor),
            imageView.rightAnchor.constraint(equalTo: rightAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        gradientLayer = CAGradientLayer()
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        gradientLayer.cornerRadius = 20
        gradientLayer.cornerCurve = .continuous
        gradientLayer.masksToBounds = true
        layer.insertSublayer(gradientLayer, at: 0)

        tokenPlaceholderBorderLayer = CAShapeLayer()
        tokenPlaceholderBorderLayer.fillColor = UIColor.clear.cgColor
        tokenPlaceholderBorderLayer.isHidden = true
        layer.addSublayer(tokenPlaceholderBorderLayer)
        
        // add large address name label
        largeLabel = UILabel()
        largeLabel.translatesAutoresizingMaskIntoConstraints = false
        largeLabel.font = Self.labelFont
        largeLabel.textColor = .white
        addSubview(largeLabel)
        NSLayoutConstraint.activate([
            largeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            largeLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        tokenPlaceholderLabel = UILabel()
        tokenPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tokenPlaceholderLabel.textAlignment = .center
        tokenPlaceholderLabel.adjustsFontSizeToFitWidth = true
        tokenPlaceholderLabel.minimumScaleFactor = 0.5
        tokenPlaceholderLabel.textColor = Self.tokenPlaceholderTextColor
        tokenPlaceholderLabel.isHidden = true
        addSubview(tokenPlaceholderLabel)
        NSLayoutConstraint.activate([
            tokenPlaceholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            tokenPlaceholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            tokenPlaceholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            tokenPlaceholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4)
        ])
        
        // add small address name label
        smallLabelGuide = UILayoutGuide()
        addLayoutGuide(smallLabelGuide)
        
        smallLabelTop = UILabel()
        smallLabelTop.translatesAutoresizingMaskIntoConstraints = false
        smallLabelTop.setContentHuggingPriority(.required, for: .vertical)
        addSubview(smallLabelTop)
        smallLabelBottom = UILabel()
        smallLabelBottom.translatesAutoresizingMaskIntoConstraints = false
        smallLabelBottom.setContentHuggingPriority(.required, for: .vertical)
        addSubview(smallLabelBottom)
        smallLabelTopBottomConstraint = smallLabelBottom.topAnchor.constraint(equalTo: smallLabelTop.bottomAnchor, constant: 0).withPriority(.defaultHigh)
        NSLayoutConstraint.activate([
            // centered vertically
            smallLabelGuide.centerXAnchor.constraint(equalTo: centerXAnchor),
            smallLabelTop.centerXAnchor.constraint(equalTo: smallLabelGuide.centerXAnchor),
            smallLabelBottom.centerXAnchor.constraint(equalTo: smallLabelGuide.centerXAnchor),
            
            // centered vertically in container
            smallLabelGuide.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.333),
            
            smallLabelGuide.topAnchor.constraint(equalTo: smallLabelTop.topAnchor),
            smallLabelGuide.bottomAnchor.constraint(equalTo: smallLabelBottom.bottomAnchor),
            
            // spaced vertically
            smallLabelTopBottomConstraint
        ])
        
        smallLabelTop.textColor = .white
        smallLabelBottom.textColor = .white

        addSubview(chainAccessoryView)
        chainAccessoryView.apply(layoutGeometry: chainAccessoryView.layoutGeometry, in: self)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        gradientLayer.frame = bounds
        updateTokenPlaceholderAppearance()
        updateChainAccessoryMask()
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        gradientLayer.colors = resolveGradientColors?()
        tokenPlaceholderLabel.textColor = Self.tokenPlaceholderTextColor
        tokenPlaceholderBorderLayer.strokeColor = Self.tokenPlaceholderBorderColor.cgColor
        if tokenImageState == .loading {
            imageView.backgroundColor = Self.tokenLoadingPlaceholderColor
        }
        super.traitCollectionDidChange(previousTraitCollection)
    }
    
    private func hideChainAccessoryMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.layer.mask = nil
        gradientLayer.mask = nil
        CATransaction.commit()
        imageViewChainCutoutMask = nil
        gradientChainCutoutMask = nil
        chainAccessoryMaskContextIconGeometry = nil
        chainAccessoryMaskContextSize = nil
        chainAccessoryMaskContextCornerRadius = nil
    }
        
    private func updateChainAccessoryMask(geometry: IconAccessoryView.LayoutGeometry? = nil,
                                          animationDuration: CGFloat = 0, onComplete: (() -> Void)? = nil) {
        guard !chainAccessoryView.isHidden, chainAccessoryView.alpha > 0.01, bounds.width > 0, bounds.height > 0 else {
            hideChainAccessoryMask()
            onComplete?()
            return
        }
        
        let lg = geometry ?? chainAccessoryView.layoutGeometry
        let iconCornerRadius = self.iconCornerRadius
        let shouldUpdateMask = chainAccessoryMaskContextSize != size ||
            chainAccessoryMaskContextIconGeometry != lg ||
            chainAccessoryMaskContextCornerRadius != iconCornerRadius
        chainAccessoryMaskContextIconGeometry = lg
        chainAccessoryMaskContextSize = size
        chainAccessoryMaskContextCornerRadius = iconCornerRadius
        let area = CGRect.square(size)
        let radius = lg.fullSize / 2
        let centerIn = CGPoint(x: area.width + lg.horizontalOffset - radius, y: area.height + lg.verticalOffset - radius)

        func buildPath() -> CGPath {
            let p = UIBezierPath(cgPath: iconShape.maskPath(in: area, cornerRadius: iconCornerRadius))
            p.append(UIBezierPath(ovalIn: CGRect(
                x: centerIn.x - radius,
                y: centerIn.y - radius,
                width: radius * 2,
                height: radius * 2
            )))
            return p.cgPath
        }

        func applyMask(_ existing: CAShapeLayer?, parent: CALayer) -> CAShapeLayer {
            if let m = existing {
                if shouldUpdateMask {
                    let newPath = buildPath()
                    if animationDuration > 0 {
                        let anim = CABasicAnimation(keyPath: "path")
                        anim.fromValue = m.presentation()?.path ?? m.path
                        anim.toValue = newPath
                        anim.duration = animationDuration
                        anim.timingFunction = CATransaction.animationTimingFunction() ?? CAMediaTimingFunction(name: .easeInEaseOut)
                        m.add(anim, forKey: "pathAnim")
                    }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    m.path = newPath
                    CATransaction.commit()
                }
                return m
            } else {
                let m = CAShapeLayer()
                m.fillRule = .evenOdd
                m.path = buildPath()
                m.frame = area
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                parent.mask = m
                CATransaction.commit()
                
                return m
            }
        }

        if let onComplete, animationDuration > 0, shouldUpdateMask {
            CATransaction.begin()
            CATransaction.setCompletionBlock(onComplete)
            imageViewChainCutoutMask = applyMask(imageViewChainCutoutMask, parent: imageView.layer)
            gradientChainCutoutMask = applyMask(gradientChainCutoutMask, parent: gradientLayer)
            CATransaction.commit()
        } else {
            imageViewChainCutoutMask = applyMask(imageViewChainCutoutMask, parent: imageView.layer)
            gradientChainCutoutMask = applyMask(gradientChainCutoutMask, parent: gradientLayer)
            onComplete?()
        }
    }

    public func config(with activity: ApiActivity, isTransactionConfirmation: Bool = false) {
        applyIconShape(.circle)
        resetAccountAvatarState()
        cachedTokenSlug = nil
        cachedTokenImageURL = nil
        tokenImageState = .none
        cachedActivityId = activity.id
        imageView.kf.cancelDownloadTask()
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        imageView.tintColor = nil
        self.resolveGradientColors = { activity.iconColors.map(\.cgColor) }
        gradientLayer.colors = resolveGradientColors?()
        gradientLayer.isHidden = false
        let content = activity.avatarContent
        if case .image(let image) = content {
            largeLabel.text = nil
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
            imageView.contentMode = .scaleAspectFit
            imageView.image = .airBundle(image)
        }
        
        if let accessoryStatus = activityAccessoryStatus(for: activity), !isTransactionConfirmation {
            setChainSize(18, borderWidth: 1.667, horizontalOffset: 2 + 1.667, verticalOffset: 2 + 1.667)
            switch accessoryStatus {
            case .pending:
                chainAccessoryView.configurePending()
            case .pendingTrusted:
                chainAccessoryView.configurePendingTrusted()
            case .failed:
                chainAccessoryView.configureError()
            case .hold:
                chainAccessoryView.configureHold()
            case .expired:
                chainAccessoryView.configureExpired()
            }
            chainAccessoryView.isHidden = false
            chainAccessoryView.alpha = 1
            chainAccessoryView.transform = .identity
            updateChainAccessoryMask()
        } else {
            self.hideChainAccessoryViewAnimated()
        }
    }
    
    private func hideChainAccessoryViewAnimated() {
        guard chainAccessoryView.alpha > 0 else {
            updateChainAccessoryMask()
            return
        }
        
        var geometry = self.chainAccessoryView.layoutGeometry
        let scale: CGFloat = 0.2
        let duration: CGFloat = 0.2
        let rx = (geometry.size + geometry.borderWidth) * (1.0 - scale) / 2.0
        geometry.size *= scale
        geometry.borderWidth *= scale
        geometry.horizontalOffset -= rx
        geometry.verticalOffset -= rx
        updateChainAccessoryMask(geometry: geometry, animationDuration: 0.1) {
            self.hideChainAccessoryMask()
        }
        UIView.animate(withDuration: duration, animations: {
            self.chainAccessoryView.alpha = 0
            self.chainAccessoryView.transform = .identity.scaledBy(x: scale, y: scale)
        })
    }

    public func config(with token: ApiToken?, isStaking: Bool = false, isWalletView: Bool = false, shouldShowChain: Bool) {
        defer {
            updateChainAccessoryMask()
        }
        
        let tokenSlug = token?.slug
        let tokenImageURL = token?.image?.nilIfEmpty
        let tokenChanged = cachedTokenSlug != tokenSlug
        let imageChanged = cachedTokenImageURL != tokenImageURL
        let shouldCancelAccountImageLoad = cachedAccountAvatarURL != nil || accountAvatarState == .loading
        resetAccountAvatarState(cancelDownload: shouldCancelAccountImageLoad)
        cachedTokenSlug = tokenSlug
        cachedTokenImageURL = tokenImageURL
        if tokenChanged || imageChanged {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            tokenImageState = .none
        }
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        largeLabel.text = nil
        smallLabelTop.text = nil
        smallLabelBottom.text = nil
        imageView.tintColor = nil
        applyIconShape(token?.isRwaStock == true ? .roundedSquare : .circle)
        resolveGradientColors = nil
        gradientLayer.colors = nil
        gradientLayer.isHidden = true
        guard let token else {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            chainAccessoryView.reset()
            chainAccessoryView.isHidden = true
            return
        }
        imageView.contentMode = .scaleAspectFill
        guard token.slug != STAKED_TON_SLUG else {
            configAsStakedToken(inWalletTokensList: isWalletView, token: token, shouldShowChain: shouldShowChain)
            return
        }
        configureTokenImage(token: token, tokenChanged: tokenChanged, imageChanged: imageChanged)
        if isStaking {
            chainAccessoryView.configurePercentBadge()
            chainAccessoryView.isHidden = false
        } else if shouldShowChain && !token.isNative {
            let chain = token.chain
            chainAccessoryView.configureChain(chain)
            chainAccessoryView.isHidden = false
        } else {
            chainAccessoryView.isHidden = true
        }
    }
    
    public func config(with account: MAccount?, showIcon: Bool = true) {
        defer {
            updateChainAccessoryMask()
        }

        applyIconShape(.circle)
        cachedTokenSlug = nil
        cachedTokenImageURL = nil
        currentAccountPlaceholder = account
        let avatarURL = account?.telegramAvatarUrl
        let avatarURLChanged = cachedAccountAvatarURL != avatarURL
        if avatarURLChanged {
            resetAccountAvatarState()
            cachedAccountAvatarURL = avatarURL
            currentAccountPlaceholder = account
        }
        tokenImageState = .none
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        imageView.contentMode = .center
        chainAccessoryView.isHidden = true
        if avatarURLChanged {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
        }
        guard let account else {
            resolveGradientColors = nil
            gradientLayer.colors = resolveGradientColors?()
            gradientLayer.isHidden = true
            largeLabel.text = nil
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
            imageView.image = UIImage(named: "AddAccountIcon", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
            imageView.tintColor = .air.backgroundReverse
            return
        }
        imageView.tintColor = nil
        configureAccountPlaceholder(account)
        resolveGradientColors = { account.firstAddress.gradientColors }
        gradientLayer.colors = resolveGradientColors?()
        gradientLayer.isHidden = false
        if let avatarURL {
            configureAccountAvatarImage(avatarURL, fallbackAccount: account)
        } else {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
        }
    }
    
    public func config(with earnHistoryItem: MStakingHistoryItem) {
        applyIconShape(.circle)
        resetAccountAvatarState()
        cachedTokenSlug = nil
        cachedTokenImageURL = nil
        tokenImageState = .none
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = nil
        largeLabel.text = nil
        smallLabelTop.text = nil
        smallLabelBottom.text = nil
        gradientLayer.isHidden = true
        imageView.image = earnHistoryItem.type.image
    }
    
    public func config(with image: UIImage?, tintColor: UIColor? = nil) {
        applyIconShape(.rectangle)
        resetAccountAvatarState()
        cachedTokenSlug = nil
        cachedTokenImageURL = nil
        tokenImageState = .none
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        imageView.image = image
        imageView.contentMode = .center
        imageView.tintColor = tintColor
        resolveGradientColors = nil
        gradientLayer.colors = nil
        largeLabel.text = nil
        smallLabelTop.text = nil
        smallLabelBottom.text = nil
        gradientLayer.isHidden = true
        chainAccessoryView.isHidden = true
    }
    
    private func configAsStakedToken(inWalletTokensList: Bool, token: ApiToken, shouldShowChain: Bool) {
        var forceShowPercent = false
        if inWalletTokensList {
            imageView.kf.cancelDownloadTask()
            imageView.image = UIImage(named: "chain_ton", in: AirBundle, compatibleWith: nil)!
            tokenImageState = .loaded
        } else {
            configureTokenImage(token: token, tokenChanged: false, imageChanged: false)
            forceShowPercent = tokenImageState == .failed
        }
        if shouldShowChain || inWalletTokensList || forceShowPercent {
            if inWalletTokensList || forceShowPercent {
                chainAccessoryView.configurePercentBadge()
            } else {
                imageView.kf.cancelDownloadTask()
                chainAccessoryView.configureChain(.ton)
            }
            chainAccessoryView.isHidden = false
        } else {
            chainAccessoryView.isHidden = true
        }
    }

    public func setSize(_ size: CGFloat) {
        self.size = size
        self.bounds = .init(x: 0, y: 0, width: size, height: size)

        NSLayoutConstraint.deactivate(self.sizeConstraints)
        self.sizeConstraints = [
            imageView.heightAnchor.constraint(equalToConstant: size),
            imageView.widthAnchor.constraint(equalToConstant: size)
        ]
        NSLayoutConstraint.activate(sizeConstraints)

        self.gradientLayer.frame = self.bounds
        self.imageView.frame = self.bounds
        
        applyIconShape(iconShape)

        if size >= 80 {
            largeLabel.font = UIFont.roundedNative(ofSize: 32, weight: .bold)
            smallLabelTop.font = UIFont.roundedNative(ofSize: 24, weight: .heavy)
            smallLabelBottom.font = UIFont.roundedNative(ofSize: 24, weight: .heavy)
            smallLabelTopBottomConstraint.constant = -2.333
        } else if size >= 40 {
            largeLabel.font = UIFont.roundedNative(ofSize: 16, weight: .bold)
            smallLabelTop.font = UIFont.roundedNative(ofSize: 12, weight: .heavy)
            smallLabelBottom.font = UIFont.roundedNative(ofSize: 12, weight: .heavy)
            smallLabelTopBottomConstraint.constant = -1.333
        } else {
            largeLabel.font = UIFont.roundedNative(ofSize: 14, weight: .bold)
            smallLabelTop.font = UIFont.roundedNative(ofSize: 9, weight: .heavy)
            smallLabelBottom.font = UIFont.roundedNative(ofSize: 9, weight: .heavy)
            smallLabelTopBottomConstraint.constant = -1
        }
        
        updateTokenPlaceholderAppearance()
        updateChainAccessoryMask()
    }

    private var iconCornerRadius: CGFloat {
        iconShape.cornerRadius(for: size)
    }

    private func applyIconShape(_ shape: IconShape) {
        iconShape = shape
        let cornerRadius = iconCornerRadius
        imageView.layer.cornerRadius = cornerRadius
        gradientLayer.cornerRadius = cornerRadius
        updateTokenPlaceholderAppearance()
    }
        
    public func setChainSize(_ size: CGFloat, borderWidth: CGFloat, horizontalOffset: CGFloat, verticalOffset: CGFloat) {
        let geometry = IconAccessoryView.LayoutGeometry(
            size: size,
            borderWidth: borderWidth,
            horizontalOffset: horizontalOffset,
            verticalOffset: verticalOffset
        )
        if geometry != self.chainAccessoryView.layoutGeometry {
            chainAccessoryView.apply(layoutGeometry: geometry, in: self)
            updateChainAccessoryMask()
        }
    }

    private func configureAccountPlaceholder(_ account: MAccount) {
        let content = account.avatarContent
        switch content {
        case .initial(let string):
            largeLabel.text = string
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
        case .sixCharacters(let string, let string2):
            largeLabel.text = nil
            smallLabelTop.text = string
            smallLabelBottom.text = string2
        case .typeIcon:
            largeLabel.text = nil
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
        case .image(_):
            largeLabel.text = nil
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
        }
    }

    private func hideAccountPlaceholder() {
        largeLabel.text = nil
        smallLabelTop.text = nil
        smallLabelBottom.text = nil
    }

    private func configureAccountAvatarImage(_ avatarURL: URL, fallbackAccount account: MAccount) {
        imageView.contentMode = .scaleAspectFill
        switch accountAvatarState {
        case .loaded:
            guard imageView.image != nil else {
                accountAvatarState = .none
                break
            }
            hideAccountPlaceholder()
            return
        case .loading:
            return
        case .failed, .unavailable:
            imageView.image = nil
            configureCurrentAccountPlaceholder(fallback: account)
            return
        case .none:
            break
        }

        accountAvatarState = .loading
        if imageView.image != nil {
            hideAccountPlaceholder()
        }

        imageView.kf.setImage(
            with: avatarURL,
            placeholder: nil,
            options: [
                .processor(SVGImageProcessor.default),
                .transition(.fade(0.2)),
                .keepCurrentImageWhileLoading,
                .alsoPrefetchToMemory,
                .cacheOriginalImage,
            ]
        ) { [weak self] result in
            guard let self, self.cachedAccountAvatarURL == avatarURL else { return }
            switch result {
            case .success(let value):
                if value.image.size.width <= 1, value.image.size.height <= 1 {
                    self.accountAvatarRetryWorkItem?.cancel()
                    self.accountAvatarRetryWorkItem = nil
                    self.accountAvatarState = .unavailable
                    self.imageView.image = nil
                    self.configureCurrentAccountPlaceholder(fallback: account)
                } else {
                    self.accountAvatarRetryWorkItem?.cancel()
                    self.accountAvatarRetryWorkItem = nil
                    self.accountAvatarState = .loaded
                    self.hideAccountPlaceholder()
                }
            case .failure(let error):
                guard !error.isTaskCancelled else { return }
                self.accountAvatarState = .failed
                self.imageView.image = nil
                self.configureCurrentAccountPlaceholder(fallback: account)
                self.scheduleAccountAvatarRetry(for: avatarURL, fallbackAccount: account)
            }
        }
    }

    private func scheduleAccountAvatarRetry(for avatarURL: URL, fallbackAccount account: MAccount) {
        accountAvatarRetryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.cachedAccountAvatarURL == avatarURL, self.accountAvatarState == .failed else { return }

            self.accountAvatarRetryWorkItem = nil
            self.accountAvatarState = .none
            self.configureAccountAvatarImage(avatarURL, fallbackAccount: self.currentAccountPlaceholder ?? account)
        }

        accountAvatarRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    private func resetAccountAvatarState(cancelDownload: Bool = true) {
        if cancelDownload {
            imageView.kf.cancelDownloadTask()
        }
        currentAccountPlaceholder = nil
        cachedAccountAvatarURL = nil
        accountAvatarState = .none
        accountAvatarRetryWorkItem?.cancel()
        accountAvatarRetryWorkItem = nil
    }

    private func configureCurrentAccountPlaceholder(fallback account: MAccount) {
        configureAccountPlaceholder(currentAccountPlaceholder ?? account)
    }

    private func configureTokenImage(token: ApiToken, tokenChanged: Bool, imageChanged: Bool) {
        guard let url = Self.validTokenImageURL(from: token.image?.nilIfEmpty) else {
            tokenImageState = .failed
            showTokenPlaceholder(for: token)
            return
        }

        switch tokenImageState {
        case .loaded:
            guard imageView.image != nil else {
                log.error("token icon loaded state missing image slug=\(token.slug, .public) symbol=\(token.symbol, .public) url=\(url.absoluteString, .public)")
                tokenImageState = .none
                configureTokenImage(token: token, tokenChanged: tokenChanged, imageChanged: imageChanged)
                return
            }
            hideTokenLoadingPlaceholder()
            hideTokenPlaceholder()
        case .failed:
            hideTokenLoadingPlaceholder()
            showTokenPlaceholder(for: token)
        case .loading:
            showTokenLoadingPlaceholder()
            hideTokenPlaceholder()
        case .none:
            hideTokenPlaceholder()
            tokenImageState = .loading
            showTokenLoadingPlaceholder()
            let options = Self.tokenImageOptions(
                url: url,
                tokenImageURL: token.image?.nilIfEmpty,
                tokenChanged: tokenChanged,
                imageChanged: imageChanged
            )
            let tokenSlug = token.slug
            let tokenImageURL = token.image?.nilIfEmpty
            imageView.kf.setImage(with: url, placeholder: nil, options: options) { [weak self] result in
                guard let self, self.cachedTokenSlug == tokenSlug, self.cachedTokenImageURL == tokenImageURL else { return }
                switch result {
                case .success:
                    self.tokenImageState = .loaded
                    self.hideTokenLoadingPlaceholder()
                    self.hideTokenPlaceholder()
                case .failure(let error):
                    guard !error.isTaskCancelled else { return }
                    log.error("token icon image load failed slug=\(token.slug, .public) symbol=\(token.symbol, .public) url=\(url.absoluteString, .public) error=\(error, .public)")
                    self.tokenImageState = .failed
                    self.hideTokenLoadingPlaceholder()
                    self.showTokenPlaceholder(for: token)
                }
            }
        }
    }

    private func showTokenPlaceholder(for token: ApiToken) {
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        gradientLayer.isHidden = true
        tokenPlaceholderLabel.text = Self.tokenInitials(from: token.name.nilIfEmpty ?? token.symbol)
        tokenPlaceholderLabel.isHidden = false
        tokenPlaceholderBorderLayer.isHidden = false
        updateTokenPlaceholderAppearance()
    }

    private func hideTokenPlaceholder() {
        tokenPlaceholderLabel.text = nil
        tokenPlaceholderLabel.isHidden = true
        tokenPlaceholderBorderLayer.isHidden = true
    }

    private func showTokenLoadingPlaceholder() {
        imageView.backgroundColor = Self.tokenLoadingPlaceholderColor
    }

    private func hideTokenLoadingPlaceholder() {
        imageView.backgroundColor = .clear
    }

    private func updateTokenPlaceholderAppearance() {
        tokenPlaceholderLabel.font = UIFont.roundedNative(ofSize: max(10, size * 0.45), weight: .bold)
        tokenPlaceholderBorderLayer.lineWidth = max(1, size * 0.025)
        tokenPlaceholderBorderLayer.strokeColor = Self.tokenPlaceholderBorderColor.cgColor
        let lineInset = tokenPlaceholderBorderLayer.lineWidth / 2
        tokenPlaceholderBorderLayer.path = iconShape.maskPath(
            in: bounds.insetBy(dx: lineInset, dy: lineInset),
            cornerRadius: max(0, iconCornerRadius - lineInset)
        )
    }

    private static func validTokenImageURL(from string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.nilIfEmpty != nil else { return nil }
        return url
    }

    private static func tokenImageOptions(
        url: URL,
        tokenImageURL: String?,
        tokenChanged: Bool,
        imageChanged: Bool
    ) -> KingfisherOptionsInfo {
        var options: KingfisherOptionsInfo = [
            .transition(.fade(0.2)),
            .alsoPrefetchToMemory,
            .cacheOriginalImage,
        ]
        if !(tokenChanged || imageChanged) {
            options.append(.keepCurrentImageWhileLoading)
        }
        if isSVGImageURL(url, originalString: tokenImageURL) {
            options.append(.processor(SVGImageProcessor.default))
        }
        return options
    }

    private static func isSVGImageURL(_ url: URL, originalString: String?) -> Bool {
        if url.pathExtension.lowercased() == "svg" {
            return true
        }

        guard url.scheme?.lowercased() == "data",
              let originalString,
              originalString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("data:image/svg+xml") else {
            return false
        }
        return true
    }

    private static func tokenInitials(from name: String) -> String {
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2 {
            return String(parts.prefix(2).compactMap(\.first)).uppercased()
        }
        if let first = parts.first {
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }
}
