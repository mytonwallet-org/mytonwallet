//
//  NftCellStatic.swift
//  UIAssets
//
//  Created by nikstar on 18.08.2025.
//

import UIKit
import Kingfisher
import WalletCore

class NftCellStatic: UICollectionViewCell {
    
    var nft: ApiNft?
    var onTap: (() -> ())?
    var onLongTap: (() -> ())?
    
    let nftView = NftViewStatic()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    func setup() {
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
        
        nftView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nftView)
        NSLayoutConstraint.activate([
            nftView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nftView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            nftView.topAnchor.constraint(equalTo: contentView.topAnchor),
            nftView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(_onTap))
        contentView.addGestureRecognizer(tap)
        
        let longTap = UILongPressGestureRecognizer(target: self, action: #selector(_onLongTap))
        longTap.minimumPressDuration = 0.25
        contentView.addGestureRecognizer(longTap)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configure(nft: ApiNft?, onTap: @escaping () -> (), onLongTap: @escaping () -> ()) {
        self.nft = nft
        self.onTap = onTap
        self.onLongTap = onLongTap
        nftView.configure(nft: nft)
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        nftView.kf.cancelDownloadTask()
    }
    
    @objc func _onTap(_ gestureRecognizer: UITapGestureRecognizer) {
        onTap?()
    }
    
    @objc func _onLongTap(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if gestureRecognizer.state == .began {
            onLongTap?()
        }
    }
}
