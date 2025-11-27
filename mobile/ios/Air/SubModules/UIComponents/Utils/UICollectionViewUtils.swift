//
//  UICollectionViewUtils.swift
//  MyTonWalletAir
//
//  Created by nikstar on 9/16/25.
//

import UIKit

public extension NSCollectionLayoutSize {
    convenience init(_ width: NSCollectionLayoutDimension, _ height: NSCollectionLayoutDimension) {
        self.init(widthDimension: width, heightDimension: height)
    }
}
