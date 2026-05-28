//
//  WImageView.swift
//  MyTonWalletAir
//
//  Created by Sina on 10/16/24.
//

import UIKit
import WalletCore

public class WImageView: UIImageView {    
    public func loadImage(for token: ApiToken) {
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
