//
//  WImageView.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/16/24.
//

import UIKit
import WalletCore

public class WImageView: UIImageView {    
    private var imageLoadGeneration = 0

    public func loadImage(url: URL?, completion: ((Bool) -> Void)? = nil) {
        imageLoadGeneration += 1
        let generation = imageLoadGeneration
        kf.cancelDownloadTask()
        image = nil
        guard let url else {
            completion?(false)
            return
        }
        kf.setImage(with: url) { [weak self] result in
            guard self?.imageLoadGeneration == generation else { return }
            switch result {
            case .success:
                completion?(true)
            case .failure:
                completion?(false)
            }
        }
    }

    public func loadImage(for token: ApiToken) {
        imageLoadGeneration += 1
        if let image = token.image?.nilIfEmpty {
            kf.cancelDownloadTask()
            kf.setImage(with: URL(string: image),
                                  options: [.transition(.fade(0.2))])
        } else {
            kf.cancelDownloadTask()
            if let chain = getChainByNativeSlug(token.slug) {
                image = chain.image
            } else {
                image = nil
            }
        }
    }
}
