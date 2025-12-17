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
    
    public var chainImageViewContainer: UIView!
    public var chainImageView: WImageView!
    public var chainConstraints: [NSLayoutConstraint] = []
    public var chainSize: CGFloat = 16
    public var chainBorderWidth: CGFloat = 1
    public var chainBorderColor: UIColor?
    
    private var resolveGradientColors: (() -> [CGColor]?)?
    
    private var cachedActivityId: String?
    
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

        chainImageViewContainer = UIView()
        chainImageViewContainer.translatesAutoresizingMaskIntoConstraints = false
        chainImageViewContainer.isHidden = true
        chainImageViewContainer.layer.masksToBounds = true
        chainImageViewContainer.layer.cornerRadius = (chainSize + 2*chainBorderWidth) / 2
        addSubview(chainImageViewContainer)
        chainImageView = WImageView()
        chainImageView.translatesAutoresizingMaskIntoConstraints = false
        chainImageView.contentMode = .scaleToFill
        chainImageView.layer.cornerRadius = chainSize / 2
        chainImageView.layer.masksToBounds = true
        chainImageViewContainer.addSubview(chainImageView)
        NSLayoutConstraint.activate([
            chainImageView.centerXAnchor.constraint(equalTo: chainImageViewContainer.centerXAnchor),
            chainImageView.centerYAnchor.constraint(equalTo: chainImageViewContainer.centerYAnchor),
        ])
        
        self.chainConstraints = [
            chainImageViewContainer.rightAnchor.constraint(equalTo: rightAnchor, constant: 3),
            chainImageViewContainer.widthAnchor.constraint(equalToConstant: chainSize + 2*chainBorderWidth),
            chainImageViewContainer.heightAnchor.constraint(equalToConstant: chainSize + 2*chainBorderWidth),
            chainImageViewContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 1),
            chainImageView.widthAnchor.constraint(equalToConstant: chainSize),
            chainImageView.heightAnchor.constraint(equalToConstant: chainSize),
        ]
        NSLayoutConstraint.activate(self.chainConstraints)
        
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
            chainImageViewContainer.backgroundColor = WTheme.groupedItem
        }
    }
    
    public func config(with activity: ApiActivity) {
        let sameActivity = activity.id == self.cachedActivityId
        cachedActivityId = activity.id
        imageView.contentMode = .scaleAspectFill
        imageView.kf.cancelDownloadTask()
        self.resolveGradientColors = { activity.iconColors.map(\.cgColor) }
        gradientLayer.colors = resolveGradientColors?()
        let content = activity.avatarContent
        if case .image(let image) = content {
            largeLabel.text = nil
            smallLabelTop.text = nil
            smallLabelBottom.text = nil
            imageView.contentMode = .center
            imageView.image = .airBundle(image)
        }
        let isFailed = activity.transaction?.status == .failed || activity.swap?.status == .failed || activity.swap?.status == .expired
        let isPending = activity.isLocal || getIsActivityPending(activity)
        if isPending && !isFailed {
            setChainSize(18, borderWidth: 1.667, borderColor: WTheme.groupedItem, horizontalOffset: 2 + 1.667, verticalOffset: 2 + 1.667)
            chainImageView.image = .airBundle("ActivityWaiting")
            chainImageViewContainer.isHidden = false
            chainImageViewContainer.alpha = 1
            chainImageViewContainer.transform = .identity
        } else {
            if sameActivity {
                UIView.animate(withDuration: 0.2) {
                    self.chainImageViewContainer.alpha = 0
                    self.chainImageViewContainer.transform = .identity.scaledBy(x: 0.2, y: 0.2)
                }
            } else {
                chainImageViewContainer.alpha = 0
            }
        }
    }
    
    public func config(with nft: ApiNft) {
        imageView.kf.cancelDownloadTask()
        imageView.contentMode = .scaleAspectFill
        imageView.image = UIImage(named: "chain_ton", in: AirBundle, compatibleWith: nil)!
        imageView.isHidden = false
        largeLabel.text = nil
        smallLabelTop.text = nil
        smallLabelBottom.text = nil
        chainImageViewContainer.isHidden = true
    }
    
    public func config(with token: ApiToken?, isStaking: Bool = false, isWalletView: Bool = false, shouldShowChain: Bool) {
        guard let token else {
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            chainImageView.kf.cancelDownloadTask()
            chainImageView.image = nil
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
                                  options: [.transition(.fade(0.2)), .keepCurrentImageWhileLoading, .alsoPrefetchToMemory, .cacheOriginalImage])
        } else {
            imageView.kf.cancelDownloadTask()
            if let chain = availableChains.first(where: { chain in
                chain.tokenSlug == token.slug
            }) {
                imageView.image = chain.image
            } else {
                imageView.image = nil
            }
        }
        if isStaking {
            chainImageView.contentMode = .center
            chainImageView.image = .airBundle("Percent")
            chainImageView.contentMode = .scaleToFill
            chainImageView.tintColor = .white
            chainImageView.backgroundColor = WTheme.positiveAmount
            chainImageViewContainer.isHidden = false
        } else if shouldShowChain && !token.isNative {
            let chain = token.chain
            chainImageView.contentMode = .scaleToFill
            chainImageView.image = UIImage(named: "chain_\(chain)", in: AirBundle, compatibleWith: nil)
            chainImageViewContainer.isHidden = false
            updateTheme()
        } else {
            chainImageViewContainer.isHidden = true
        }
    }
    
    public func config(with recentAddress: MRecentAddress) {
        imageView.contentMode = .center
        resolveGradientColors = { (recentAddress.addressAlias ?? recentAddress.address).gradientColors }
        gradientLayer.colors = resolveGradientColors?()
        imageView.image = UIImage(named: "AddressIcon", in: AirBundle, compatibleWith: nil)
        largeLabel.text = nil
        chainImageViewContainer.isHidden = true
    }
    
    public func config(with account: MAccount?, showIcon: Bool = true) {
        imageView.contentMode = .center
        chainImageViewContainer.isHidden = true
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
        resolveGradientColors = { account.firstAddress?.gradientColors }
        gradientLayer.colors = resolveGradientColors?()
        gradientLayer.isHidden = false
        imageView.image = nil
    }
    
    public func config(with earnHistoryItem: MStakingHistoryItem) {
        imageView.contentMode = .scaleAspectFill
        imageView.image = earnHistoryItem.type.image
    }
    
    public func config(with chain: ApiChain) {
        chainImageViewContainer.isHidden = true
        imageView.contentMode = .scaleAspectFill
        imageView.image = chain.image
    }
    
    public func config(with image: UIImage?, tintColor: UIColor? = nil) {
        imageView.image = image
        imageView.contentMode = .center
        imageView.layer.cornerRadius = 0
        imageView.tintColor = tintColor
        largeLabel.text = nil
        smallLabelTop.text = nil
        smallLabelBottom.text = nil
        gradientLayer.isHidden = true
        chainImageViewContainer.isHidden = true
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
                chainImageView.contentMode = .center
                chainImageView.image = UIImage(named: "Percent", in: AirBundle, with: nil)
                chainImageView.contentMode = .scaleToFill
                chainImageView.tintColor = .white
                chainImageView.backgroundColor = WTheme.positiveAmount
            } else {
                chainImageView.contentMode = .scaleToFill
                imageView.kf.cancelDownloadTask()
                chainImageView.image = UIImage(named: "chain_ton", in: AirBundle, compatibleWith: nil)!
            }
            chainImageViewContainer.isHidden = false
        } else {
            chainImageViewContainer.isHidden = true
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
        NSLayoutConstraint.deactivate(self.chainConstraints)
        self.chainConstraints = [
            chainImageViewContainer.rightAnchor.constraint(equalTo: rightAnchor, constant: horizontalOffset),
            chainImageViewContainer.widthAnchor.constraint(equalToConstant: chainSize + 2*chainBorderWidth),
            chainImageViewContainer.heightAnchor.constraint(equalToConstant: chainSize + 2*chainBorderWidth),
            chainImageViewContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: verticalOffset),
            chainImageView.widthAnchor.constraint(equalToConstant: chainSize),
            chainImageView.heightAnchor.constraint(equalToConstant: chainSize),
        ]
        NSLayoutConstraint.activate(chainConstraints)
        chainImageViewContainer.layer.cornerRadius = (chainSize + 2*chainBorderWidth) / 2
        chainImageView.layer.cornerRadius = chainSize / 2
        chainImageViewContainer.backgroundColor = borderColor
    }
}


public struct WUIIconViewToken: UIViewRepresentable {
    
    public var token: ApiToken?
    public var isStaking: Bool
    public var isWalletView: Bool
    public var showldShowChain: Bool
    public var size: CGFloat
    public var chainSize: CGFloat
    public var chainBorderWidth: CGFloat
    public var chainBorderColor: UIColor
    public var chainHorizontalOffset: CGFloat
    public var chainVerticalOffset: CGFloat
    
    public init(token: ApiToken? = nil, isStaking: Bool = false, isWalletView: Bool, showldShowChain: Bool, size: CGFloat, chainSize: CGFloat, chainBorderWidth: CGFloat, chainBorderColor: UIColor, chainHorizontalOffset: CGFloat, chainVerticalOffset: CGFloat) {
        self.token = token
        self.isStaking = isStaking
        self.isWalletView = isWalletView
        self.showldShowChain = showldShowChain
        self.size = size
        self.chainSize = chainSize
        self.chainBorderWidth = chainBorderWidth
        self.chainBorderColor = chainBorderColor
        self.chainHorizontalOffset = chainHorizontalOffset
        self.chainVerticalOffset = chainVerticalOffset
    }
    
    public func makeUIView(context: Context) -> IconView {
        let uiView = IconView(size: size)
        NSLayoutConstraint.activate([
            uiView.heightAnchor.constraint(equalToConstant: size),
            uiView.widthAnchor.constraint(equalToConstant: size)
        ])
        uiView.setChainSize(chainSize, borderWidth: chainBorderWidth, borderColor: chainBorderColor, horizontalOffset: chainHorizontalOffset, verticalOffset: chainVerticalOffset)
        uiView.config(with: token, isStaking: isStaking, isWalletView: isWalletView, shouldShowChain: showldShowChain)
        uiView.imageView.layer.cornerRadius = size/2
        return uiView
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        uiView.setChainSize(chainSize, borderWidth: chainBorderWidth, borderColor: chainBorderColor, horizontalOffset: chainHorizontalOffset, verticalOffset: chainVerticalOffset)
        uiView.config(with: token, isStaking: isStaking, isWalletView: isWalletView, shouldShowChain: showldShowChain)
    }
}


public struct AccountIcon: View {
    
    var account: MAccount
    
    public init(account: MAccount) {
        self.account = account
    }
    
    public var body: some View {
        ZStack {
            Color.clear
            if let _colors = account.firstAddress?.gradientColors {
                let colors = _colors.map { Color($0) }
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            let content = account.avatarContent
            switch content {
            case .initial(let string):
                Text(verbatim: string)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .fixedSize()
            case .sixCharaters(_, _):
                EmptyView()
            case .typeIcon:
                EmptyView()
            case .image(_):
                EmptyView()
            }
        }
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .drawingGroup()
    }
}
