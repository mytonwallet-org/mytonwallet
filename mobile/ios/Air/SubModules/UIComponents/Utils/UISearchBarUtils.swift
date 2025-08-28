//
//  UISearchBarUtils.swift
//  MyTonWalletAir
//
//  Created by Sina on 12/25/24.
//

import UIKit

public extension UISearchBar {
    func setCenteredPlaceholder() {
        let textFieldInsideSearchBar = self.value(forKey: "searchField") as? UITextField

        let searchBarWidth = self.frame.width
        let placeholderIconWidth = textFieldInsideSearchBar?.leftView?.frame.width
        let placeHolderWidth = textFieldInsideSearchBar?.attributedPlaceholder?.size().width ?? 0
        guard placeHolderWidth > 0 else { return }
        let offsetIconToPlaceholder: CGFloat = 8
        let placeHolderWithIcon = placeholderIconWidth! + offsetIconToPlaceholder

        let offset = UIOffset(horizontal: ((searchBarWidth / 2) - (placeHolderWidth / 2) - placeHolderWithIcon), vertical: 0)
        self.setPositionAdjustment(offset, for: .search)
        self.searchTextPositionAdjustment = .init(horizontal: 5, vertical: 0)
    }
}
