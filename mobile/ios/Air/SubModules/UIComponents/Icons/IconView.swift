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

public class IconView: UIView {
    private static let labelFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    private static let tokenPlaceholderTextColor = UIColor.air.secondaryLabel
    private static let tokenPlaceholderBorderColor = UIColor.air.secondaryLabel.withAlphaComponent(0.5)
    private static let tokenLoadingPlaceholderColor = UIColor.air.secondaryLabel.withAlphaComponent(0.08)
    
    public var imageView: UIImageView!
    private var borderLayer: CALayer?
    private var borderWidth: CGFloat?
    private var borderColor: UIColor?
    
    public var gradientLayer: CAGradientLayer!
    
    public var largeLabel: UILabel!
    private var tokenPlaceholderLabel: UILabel!
    private var tokenPlaceholderBorderLayer: CAShapeLayer!
    
    public var smallLabelTop: UILabel!
    public var smallLabelBottom: UILabel!
    public var smallLabelGuide: UILayoutGuide!
    public var smallLabelTopBottomConstraint: NSLayoutConstraint!
    
    public var size: CGFloat = 40
    public var sizeConstraints: [NSLayoutConstraint] = []
    
    private var chainAccessoryView: IconAccessoryView!
    public var chainSize: CGFloat = 16
    public var chainBorderWidth: CGFloat = 1
    public var chainBorderColor: UIColor?
    
    private var resolveGradientColors: (() -> [CGColor]?)?
    
    private var cachedActivityId: String?
    private var cachedTokenSlug: String?
    private var cachedTokenImageURL: String?
    private var tokenImageState: TokenImageState = .none

    private enum TokenImageState {
        case none
        case loading
        case loaded
        case failed
    }
    
    public init(size: CGFloat, borderWidth: CGFloat? = nil, borderColor: UIColor? = nil) {
        super.init(frame: CGRect.zero)
        setupView()
        setSize(size)
        if let borderWidth {
            setBorder(width: borderWidth, color: borderColor, layout: false)
        }
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
        gradientLayer.masksToBounds = true
        layer.insertSublayer(gradientLayer, at: 0)

        tokenPlaceholderBorderLayer = CAShapeLayer()
        tokenPlaceholderBorderLayer.fillColor = UIColor.clear.cgColor
        tokenPlaceholderBorderLayer.isHidden = true
        layer.addSublayer(tokenPlaceholderBorderLayer)
        
        // add large address name label
        largeLabel = UILabel()
        largeLabel.translatesAutoresizingMaskIntoConstraints = false
        largeLabel.font = IconView.labelFont
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

        chainAccessoryView = IconAccessoryView()
        addSubview(chainAccessoryView)
        chainAccessoryView.apply(size: chainSize, borderWidth: chainBorderWidth, borderColor: chainBorderColor, horizontalOffset: 3, verticalOffset: 1, in: self)
        
        updateTheme()
    }
    
    public override func layoutSubviews() {
        gradientLayer.frame = bounds
        updateTokenPlaceholderAppearance()
        if let borderLayer {
            let borderWidth = self.borderWidth ?? 0
            borderLayer.frame = bounds.insetBy(dx: -borderWidth, dy: -borderWidth)
            borderLayer.cornerRadius = bounds.width * 0.5 + borderWidth
        }
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        borderLayer?.backgroundColor = borderColor?.cgColor
        gradientLayer.colors = resolveGradientColors?()
        tokenPlaceholderLabel.textColor = Self.tokenPlaceholderTextColor
        tokenPlaceholderBorderLayer.strokeColor = Self.tokenPlaceholderBorderColor.cgColor
        if tokenImageState == .loading {
            imageView.backgroundColor = Self.tokenLoadingPlaceholderColor
        }
        super.traitCollectionDidChange(previousTraitCollection)
    }
    
    private func updateTheme() {
        if self.chainBorderColor == nil {
            chainAccessoryView.backgroundColor = .air.groupedItem
        }
    }
    
    public func config(with activity: ApiActivity, isTransactionConfirmation: Bool = false) {
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
            setChainSize(18, borderWidth: 1.667, borderColor: .air.groupedItem, horizontalOffset: 2 + 1.667, verticalOffset: 2 + 1.667)
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
        } else {
            UIView.animate(withDuration: 0.2) {
                self.chainAccessoryView.alpha = 0
                self.chainAccessoryView.transform = .identity.scaledBy(x: 0.2, y: 0.2)
            }
        }
    }

    public func config(with token: ApiToken?, isStaking: Bool = false, isWalletView: Bool = false, shouldShowChain: Bool) {
        let tokenSlug = token?.slug
        let tokenImageURL = token?.image?.nilIfEmpty
        let tokenChanged = cachedTokenSlug != tokenSlug
        let imageChanged = cachedTokenImageURL != tokenImageURL
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
        imageView.layer.cornerRadius = size / 2
        resolveGradientColors = nil
        gradientLayer.colors = nil
        gradientLayer.isHidden = true
        guard let token else {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            chainAccessoryView.reset()
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
            updateTheme()
        } else {
            chainAccessoryView.isHidden = true
        }
    }
    
    public func config(with account: MAccount?, showIcon: Bool = true) {
        cachedTokenSlug = nil
        cachedTokenImageURL = nil
        tokenImageState = .none
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        imageView.contentMode = .center
        chainAccessoryView.isHidden = true
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
        let content = account.avatarContent
        switch content {
        case .initial(let string):
            largeLabel.text = string
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
        case .sixCharaters(let string, let string2):
            largeLabel.text = nil
            smallLabelTop.text = string
            smallLabelBottom.text = string2
        case .typeIcon:
            break
        case .image(_):
            break
        }
        resolveGradientColors = { account.firstAddress.gradientColors }
        gradientLayer.colors = resolveGradientColors?()
        gradientLayer.isHidden = false
        imageView.image = nil
    }
    
    public func config(with earnHistoryItem: MStakingHistoryItem) {
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
        cachedTokenSlug = nil
        cachedTokenImageURL = nil
        tokenImageState = .none
        hideTokenLoadingPlaceholder()
        hideTokenPlaceholder()
        imageView.image = image
        imageView.contentMode = .center
        imageView.layer.cornerRadius = 0
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
        updateTheme()
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
        
        self.imageView.layer.cornerRadius = size / 2
        self.gradientLayer.cornerRadius = size / 2

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
    }
    
    public func setBorder(width: CGFloat?, color: UIColor?, layout: Bool = true) {
        if width == self.borderWidth {
            // do nothing
        } else if let width {
            self.borderWidth = width
            if borderLayer == nil {
                let layer = CALayer()
                self.layer.insertSublayer(layer, at: 0)
                layer.masksToBounds = true
                self.borderLayer = layer
            }
            setNeedsLayout()
        } else {
            self.borderWidth = nil
            setNeedsLayout()
        }
        self.borderColor = color
        self.borderLayer?.backgroundColor = color?.cgColor
        if layout {
            layoutIfNeeded()
        }
    }
    
    public func setChainSize(_ size: CGFloat, borderWidth: CGFloat, borderColor: UIColor? = nil, horizontalOffset: CGFloat = 3, verticalOffset: CGFloat = 1) {
        self.chainSize = size
        self.chainBorderWidth = borderWidth
        self.chainBorderColor = borderColor
        chainAccessoryView.apply(size: chainSize, borderWidth: chainBorderWidth, borderColor: borderColor, horizontalOffset: horizontalOffset, verticalOffset: verticalOffset, in: self)
    }

    private func configureTokenImage(token: ApiToken, tokenChanged: Bool, imageChanged: Bool) {
        guard let url = Self.validTokenImageURL(from: token.image?.nilIfEmpty) else {
            tokenImageState = .failed
            showTokenPlaceholder(for: token)
            return
        }

        switch tokenImageState {
        case .loaded:
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
            let options: KingfisherOptionsInfo = (tokenChanged || imageChanged)
                ? [.transition(.fade(0.2)), .alsoPrefetchToMemory, .cacheOriginalImage]
                : [.transition(.fade(0.2)), .keepCurrentImageWhileLoading, .alsoPrefetchToMemory, .cacheOriginalImage]
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
        tokenPlaceholderBorderLayer.path = UIBezierPath(
            ovalIn: bounds.insetBy(dx: tokenPlaceholderBorderLayer.lineWidth / 2, dy: tokenPlaceholderBorderLayer.lineWidth / 2)
        ).cgPath
    }

    private static func validTokenImageURL(from string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.nilIfEmpty != nil else { return nil }
        return url
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
