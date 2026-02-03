//
//  NftViewStatic.swift
//  UIAssets
//
//  Created by nikstar on 18.08.2025.
//

import UIKit
import Kingfisher
import WalletCore


final class NftViewStatic: UIImageView {
    
    var nft: ApiNft?
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.contentMode = .scaleAspectFit
    }
    
    func configure(nft: ApiNft?) {
        guard nft != self.nft else { return }
        if let url = nft?.thumbnail.flatMap(URL.init(string:)) {
            self.kf.cancelDownloadTask()
            self.kf.setImage(with: .network(url), placeholder: nil, options: [.alsoPrefetchToMemory, .cacheOriginalImage, .cacheOriginalImage], completionHandler: nil)
        } else {
            self.kf.cancelDownloadTask()
            self.image = nil
        }
    }
}



#if DEBUG
@available(iOS 18, *)
#Preview {
    let view = NftViewStatic()
    let _  = view.configure(nft: ApiNft.sample)
    view
}
#endif
