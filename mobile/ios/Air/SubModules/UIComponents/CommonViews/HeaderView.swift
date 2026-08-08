//
//  HeaderView.swift
//  UIComponents
//
//  Created by Sina on 3/16/24.
//

import UIKit
import LottieKit

fileprivate let _animationSize = 124

public class HeaderView: UIView {
    
    // MARK: - Initializers
    public init(animationName: String,
                animationPlaybackMode: LottieAnimationPlaybackMode,
                title: String,
                description: String? = nil,
                additionalView: UIView? = nil,
                animationSize: Int? = nil,
                compactMode: Bool = false) {
        self.animationSize = animationSize ?? _animationSize
        super.init(frame: CGRect.zero)
        setupView(animationName: animationName,
                  animationPlaybackMode: animationPlaybackMode,
                  title: title,
                  description: description,
                  additionalView: additionalView,
                  compactMode: compactMode)
    }

    public init(title: String,
                description: String? = nil,
                animationSize: Int? = nil,
                compactMode: Bool = false) {
        self.animationSize = animationSize ?? _animationSize
        super.init(frame: CGRect.zero)
        setupView(title: title,
                  description: description,
                  compactMode: compactMode)
    }

    override public init(frame: CGRect) {
        fatalError()
    }
    
    required public init?(coder: NSCoder) {
        fatalError()
    }

    public let animationSize: Int
    
    // MARK: - Public subviews
    public var animatedSticker: WAnimatedSticker?
    public var lblTitle: UILabel!
    public var lblDescription: UILabel!

    // MARK: - HeaderView with animation
    private func setupView(animationName: String,
                           animationPlaybackMode: LottieAnimationPlaybackMode,
                           title: String,
                           description: String? = nil,
                           additionalView: UIView? = nil,
                           compactMode: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        
        // add animated sticker
        animatedSticker = WAnimatedSticker()
        animatedSticker!.animationName = animationName
        animatedSticker!.translatesAutoresizingMaskIntoConstraints = false
        animatedSticker!.setup(width: animationSize,
                              height: animationSize,
                              playbackMode: animationPlaybackMode)
        addSubview(animatedSticker!)
        NSLayoutConstraint.activate([
            animatedSticker!.topAnchor.constraint(equalTo: topAnchor),
            animatedSticker!.centerXAnchor.constraint(equalTo: centerXAnchor),
            animatedSticker!.widthAnchor.constraint(equalToConstant: CGFloat(animationSize)),
            animatedSticker!.heightAnchor.constraint(equalToConstant: CGFloat(animationSize))
        ])
        
        addTitleAndDescription(topView: animatedSticker!, title: title, description: description, additionalView: additionalView, compactMode: compactMode)
    }
    
    // MARK: - HeaderView with texts only
    private func setupView(title: String,
                           description: String? = nil,
                           compactMode: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false

        addTitleAndDescription(topView: nil, title: title, description: description, compactMode: compactMode)
    }

    // MARK: - Shared functions to generate required views
    private func addTitleAndDescription(topView: UIView?,
                                        title: String,
                                        description: String? = nil,
                                        additionalView: UIView? = nil,
                                        compactMode: Bool = false) {
        // title
        lblTitle = UILabel()
        lblTitle.translatesAutoresizingMaskIntoConstraints = false
        lblTitle.text = title
        lblTitle.applyTextStyle(.screenTitle)
        lblTitle.numberOfLines = 0
        lblTitle.textAlignment = .center
        lblTitle.accessibilityTraits.insert(.header)
        addSubview(lblTitle)
        NSLayoutConstraint.activate([
            lblTitle.topAnchor.constraint(equalTo: topView?.bottomAnchor ?? topAnchor, constant: compactMode ? 12 : 24),
            lblTitle.leadingAnchor.constraint(equalTo: leadingAnchor),
            lblTitle.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // description
        lblDescription = UILabel()
        lblDescription.translatesAutoresizingMaskIntoConstraints = false
        if let description, let attr = try? NSMutableAttributedString(markdown: description) {
            attr.addAttribute(.font, value: WTypography.uiFont(.body), range: NSRange(location: 0, length: attr.length))
            lblDescription.attributedText = attr
        } else {
            lblDescription.text = description
            lblDescription.applyTextStyle(.body)
        }
        lblDescription.numberOfLines = 0
        lblDescription.textAlignment = .center
        addSubview(lblDescription)
        NSLayoutConstraint.activate([
            lblDescription.topAnchor.constraint(equalTo: lblTitle.bottomAnchor, constant: description != nil ? 12 : 0),
            lblDescription.leadingAnchor.constraint(equalTo: leadingAnchor),
            lblDescription.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        
        if let additionalView {
            addSubview(additionalView)
            NSLayoutConstraint.activate([
                additionalView.topAnchor.constraint(equalTo: lblDescription.bottomAnchor, constant: 36),
                additionalView.leadingAnchor.constraint(equalTo: leadingAnchor),
                additionalView.trailingAnchor.constraint(equalTo: trailingAnchor),
                additionalView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                lblDescription.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
    
}
