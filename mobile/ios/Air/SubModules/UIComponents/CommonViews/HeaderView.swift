//
//  HeaderView.swift
//  UIComponents
//
//  Created by Sina on 3/16/24.
//

import UIKit

fileprivate let _animationSize = 124

public class HeaderView: UIView {
    
    // MARK: - Initializers
    public init(animationName: String,
                animationPlaybackMode: AnimatedStickerPlaybackMode,
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

    public init(icon: UIImage,
                iconWidth: Int,
                iconHeight: Int,
                iconTintColor: UIColor,
                title: String,
                description: String? = nil,
                animationSize: Int? = nil,
                compactMode: Bool = false) {
        self.animationSize = animationSize ?? _animationSize
        super.init(frame: CGRect.zero)
        setupView(icon: icon,
                  iconWidth: iconWidth,
                  iconHeight: iconHeight,
                  iconTintColor: iconTintColor,
                  title: title,
                  description: description,
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
                           animationPlaybackMode: AnimatedStickerPlaybackMode,
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
    
    // MARK: - HeaderView with Icon
    private func setupView(icon: UIImage,
                           iconWidth: Int,
                           iconHeight: Int,
                           iconTintColor: UIColor,
                           title: String,
                           description: String? = nil,
                           compactMode: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        
        // add animated sticker
        let iconImageView = UIImageView(image: icon.withRenderingMode(.alwaysTemplate))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.contentMode = .center
        iconImageView.tintColor = iconTintColor
        addSubview(iconImageView)
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: topAnchor),
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: CGFloat(iconWidth)),
            iconImageView.heightAnchor.constraint(equalToConstant: CGFloat(iconHeight))
        ])
        
        addTitleAndDescription(topView: iconImageView, title: title, description: description)
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
        lblTitle.font = UIFont.systemFont(ofSize: 28, weight: .semibold)
        lblTitle.numberOfLines = 0
        lblTitle.textAlignment = .center
        addSubview(lblTitle)
        NSLayoutConstraint.activate([
            lblTitle.topAnchor.constraint(equalTo: topView?.bottomAnchor ?? topAnchor, constant: compactMode ? 12 : 24),
            lblTitle.leftAnchor.constraint(equalTo: leftAnchor),
            lblTitle.rightAnchor.constraint(equalTo: rightAnchor)
        ])

        // description
        lblDescription = UILabel()
        lblDescription.translatesAutoresizingMaskIntoConstraints = false
        if let description, let attr = try? NSMutableAttributedString(markdown: description) {
            attr.addAttribute(.font, value: UIFont.systemFont(ofSize: 17), range: NSRange(location: 0, length: attr.length))
            lblDescription.attributedText = attr
        } else {
            lblDescription.text = description
            lblDescription.font = UIFont.systemFont(ofSize: 17)
        }
        lblDescription.numberOfLines = 0
        lblDescription.textAlignment = .center
        addSubview(lblDescription)
        NSLayoutConstraint.activate([
            lblDescription.topAnchor.constraint(equalTo: lblTitle.bottomAnchor, constant: description != nil ? 12 : 0),
            lblDescription.leftAnchor.constraint(equalTo: leftAnchor),
            lblDescription.rightAnchor.constraint(equalTo: rightAnchor)
        ])
        
        if let additionalView {
            addSubview(additionalView)
            NSLayoutConstraint.activate([
                additionalView.topAnchor.constraint(equalTo: lblDescription.bottomAnchor, constant: 36),
                additionalView.leftAnchor.constraint(equalTo: leftAnchor),
                additionalView.rightAnchor.constraint(equalTo: rightAnchor),
                additionalView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                lblDescription.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
    
}
