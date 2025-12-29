//
//  WalletCollectiblesEmptyView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/19/24.
//

import UIKit
import UIComponents
import WalletContext


class CollectiblesEmptyView: UICollectionViewCell, WThemedView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var emptyView: HeaderView!
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        
        emptyView = HeaderView(animationName: "NoResults",
                                     animationPlaybackMode: .loop,
                                     title: lang("No NFTs yet"),
                                     description: nil,
                                     compactMode: true)
        emptyView.lblTitle.font = .systemFont(ofSize: 17, weight: .medium)
        contentView.addSubview(emptyView)
        NSLayoutConstraint.activate([
            emptyView.widthAnchor.constraint(equalToConstant: 200),
            emptyView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        updateTheme()
    }
    
    func updateTheme() {
    }
}
