//
//  TwoIconView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/7/24.
//


import UIKit
import WalletCore
import WalletContext
import Kingfisher

public class TwoIconView: UIView, WThemedView {

    private var imageView: UIImageView!
    private var secondImageViewContainer: UIView!
    private var secondImageView: WImageView!
    
    public init() {
        super.init(frame: CGRect.zero)
        setupView()
    }
    
    override public init(frame: CGRect) {
        fatalError()
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
        imageView.contentMode = .scaleToFill
        imageView.layer.cornerRadius = 14
        imageView.layer.masksToBounds = true
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 28),
            imageView.heightAnchor.constraint(equalToConstant: 28),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.leftAnchor.constraint(equalTo: leftAnchor)
        ])
        
        secondImageViewContainer = UIView()
        secondImageViewContainer.translatesAutoresizingMaskIntoConstraints = false
        secondImageViewContainer.layer.masksToBounds = true
        secondImageViewContainer.layer.cornerRadius = 14.5
        addSubview(secondImageViewContainer)
        NSLayoutConstraint.activate([
            secondImageViewContainer.rightAnchor.constraint(equalTo: rightAnchor, constant: 1),
            secondImageViewContainer.widthAnchor.constraint(equalToConstant: 29),
            secondImageViewContainer.heightAnchor.constraint(equalToConstant: 29),
            secondImageViewContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 1)
        ])
        secondImageView = WImageView()
        secondImageView.translatesAutoresizingMaskIntoConstraints = false
        secondImageView.contentMode = .scaleToFill
        secondImageView.layer.cornerRadius = 14
        secondImageView.layer.masksToBounds = true
        secondImageViewContainer.addSubview(secondImageView)
        NSLayoutConstraint.activate([
            secondImageView.widthAnchor.constraint(equalToConstant: 28),
            secondImageView.heightAnchor.constraint(equalToConstant: 28),
            secondImageView.centerXAnchor.constraint(equalTo: secondImageViewContainer.centerXAnchor),
            secondImageView.centerYAnchor.constraint(equalTo: secondImageViewContainer.centerYAnchor),
        ])
        
        updateTheme()
    }
    
    public func updateTheme() {
        secondImageViewContainer.backgroundColor = WTheme.groupedItem
    }
    
    public func config(with transaction: ApiActivity) {
        switch transaction {
        case .swap(let swap):
            setImage(with: swap.from, on: imageView)
            setImage(with: swap.to, on: secondImageView)
            secondImageViewContainer.isHidden = false
        case .transaction:
            imageView.kf.cancelDownloadTask()
            imageView.image = nil
            secondImageView.kf.cancelDownloadTask()
            secondImageView.image = nil
            secondImageViewContainer.isHidden = true
        }
    }
    
    private func setImage(with tokenSlug: String, on imageView: UIImageView) {
        var image: String?
        if let tokenImage = TokenStore.tokens[tokenSlug]?.image?.nilIfEmpty {
            image = tokenImage
        } else if let swapAssetImage = TokenStore.swapAssets?.first(where: { $0.slug == tokenSlug || $0.tokenAddress == tokenSlug })?.image?.nilIfEmpty {
            image = swapAssetImage
        }
        if let image {
            imageView.kf.cancelDownloadTask()
            imageView.kf.setImage(with: URL(string: image),
                                  options: [.transition(.fade(0.2))])
        } else {
            imageView.kf.cancelDownloadTask()
            if let chain = availableChains.first(where: { chain in chain.tokenSlug == tokenSlug }) {
                imageView.image = chain.image
            } else {
                imageView.image = nil
            }
        }
    }
}
