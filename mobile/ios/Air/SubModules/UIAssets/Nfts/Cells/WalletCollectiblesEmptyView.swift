//
//  WalletCollectiblesEmptyView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/19/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext

class WalletCollectiblesEmptyView: UICollectionViewCell, WThemedView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.font = .systemFont(ofSize: 17, weight: .medium)
        lbl.text = lang("No NFTs yet")
        return lbl
    }()
    
    private let subtitleButton: UIButton = {
        let btn = UIButton()
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private func setupViews() {
        backgroundColor = .clear

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints  = false
        contentView.addSubview(container)
        
        container.addSubview(titleLabel)
        container.addSubview(subtitleButton)
        
        subtitleButton.addTarget(self, action: #selector(explorePressed), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitleButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor),
            subtitleButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitleButton.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
                
        updateTheme()
    }
    
    func updateTheme() {
        titleLabel.textColor = WTheme.primaryLabel
        let attr = NSMutableAttributedString(string: lang("$nft_explore_offer"), attributes: [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: WTheme.tint,
        ])
        let forwardArrowImage = UIImage(systemName: "chevron.forward",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 14,
                                                                                    weight: .medium))
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = forwardArrowImage?.withTintColor(WTheme.tint).withRenderingMode(.alwaysTemplate)
        if imageAttachment.image != nil {
            let imageAttachmentString = NSAttributedString(attachment: imageAttachment)
            attr.append(imageAttachmentString)
        }
        subtitleButton.setAttributedTitle(attr, for: .normal)
    }
    
    func config() {
        subtitleButton.isHidden = ConfigStore.shared.shouldRestrictSwapsAndOnRamp
    }
    
    @objc func explorePressed() {
        let url = URL(string: NFT_MARKETPLACE_URL)!
        AppActions.openInBrowser(url)
    }
}
