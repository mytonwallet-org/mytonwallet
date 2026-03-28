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

class WalletCollectiblesEmptyView: UICollectionViewCell {
    
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
        btn.titleLabel?.numberOfLines = 0
        btn.titleLabel?.font = .systemFont(ofSize: 14)
        btn.titleLabel?.textAlignment = .center
        btn.setTitle(lang("$nft_explore_offer"), for: .normal)
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
    
    private func updateTheme() {
        titleLabel.textColor = UIColor.label
        subtitleButton.setTitleColor(.tintColor, for: .normal)
    }
    
    func config() {
        subtitleButton.isHidden = ConfigStore.shared.shouldRestrictSwapsAndOnRamp
    }
    
    @objc func explorePressed() {
        let url = URL(string: NFT_MARKETPLACE_URL)!
        AppActions.openInBrowser(url)
    }
}
