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

public class IconView: UIView, WThemedView {
    private static let labelFont = UIFont.systemFont(ofSize: 20, weight: .semibold)
    
    public var imageView: UIImageView!
    private var borderLayer: CALayer?
    private var borderWidth: CGFloat?
    private var borderColor: UIColor?
    
    public var gradientLayer: CAGradientLayer!
    
    public var largeLabel: UILabel!
    
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
        if let borderLayer {
            let borderWidth = self.borderWidth ?? 0
            borderLayer.frame = bounds.insetBy(dx: -borderWidth, dy: -borderWidth)
            borderLayer.cornerRadius = bounds.width * 0.5 + borderWidth
        }
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        borderLayer?.backgroundColor = borderColor?.cgColor
        gradientLayer.colors = resolveGradientColors?()
        super.traitCollectionDidChange(previousTraitCollection)
    }
    
    public func updateTheme() {
        if self.chainBorderColor == nil {
            chainAccessoryView.backgroundColor = WTheme.groupedItem
        }
    }
    
    public func config(with activity: ApiActivity, isTransactionConfirmation: Bool = false) {
        cachedTokenSlug = nil
        cachedActivityId = activity.id
        imageView.kf.cancelDownloadTask()
        self.resolveGradientColors = { activity.iconColors.map(\.cgColor) }
        gradientLayer.colors = resolveGradientColors?()
        let content = activity.avatarContent
        if case .image(let image) = content {
            largeLabel.text = nil
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
            imageView.contentMode = .scaleAspectFit
            imageView.image = .airBundle(image)
        }
        if let accessoryStatus = activityAccessoryStatus(for: activity), !isTransactionConfirmation {
            setChainSize(18, borderWidth: 1.667, borderColor: WTheme.groupedItem, horizontalOffset: 2 + 1.667, verticalOffset: 2 + 1.667)
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
        let tokenChanged = cachedTokenSlug != tokenSlug
        cachedTokenSlug = tokenSlug
        if tokenChanged {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
        }
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
        if let image = token.image?.nilIfEmpty {
            imageView.kf.setImage(with: URL(string: image),
                                  placeholder: nil,
                                  options: tokenChanged
                                  ? [.transition(.fade(0.2)), .alsoPrefetchToMemory, .cacheOriginalImage]
                                  : [.transition(.fade(0.2)), .keepCurrentImageWhileLoading, .alsoPrefetchToMemory, .cacheOriginalImage])
        } else {
            imageView.kf.cancelDownloadTask()
            if let chain = getChainByNativeSlug(token.slug) {
                imageView.image = chain.image
            } else {
                imageView.image = nil
            }
        }
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
        imageView.contentMode = .center
        chainAccessoryView.isHidden = true
        guard let account else {
            resolveGradientColors = nil
            gradientLayer.colors = resolveGradientColors?()
            imageView.image = UIImage(named: "AddAccountIcon", in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate)
            imageView.tintColor = WTheme.backgroundReverse
            return
        }
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
        imageView.contentMode = .scaleAspectFill
        imageView.image = earnHistoryItem.type.image
    }
    
    public func config(with image: UIImage?, tintColor: UIColor? = nil) {
        cachedTokenSlug = nil
        imageView.image = image
        imageView.contentMode = .center
        imageView.layer.cornerRadius = 0
        imageView.tintColor = tintColor
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
        } else {
            if let image = token.image?.nilIfEmpty {
                imageView.kf.setImage(with: URL(string: image),
                                      options: [.transition(.fade(0.2))])
            } else {
                imageView.kf.cancelDownloadTask()
                imageView.image = UIImage(named: "chain_ton", in: AirBundle, compatibleWith: nil)!
                forceShowPercent = true
            }
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
            largeLabel.font = UIFont.roundedNative(ofSize: 38, weight: .bold)
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
}
