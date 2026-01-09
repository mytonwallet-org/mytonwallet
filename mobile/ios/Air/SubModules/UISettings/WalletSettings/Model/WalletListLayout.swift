//
//  WalletListLayout.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import WalletContext

enum WalletListLayout {
    case grid
    case list
    
    var other: WalletListLayout {
        switch self {
        case .grid: .list
        case .list: .grid
        }
    }
    
    var title: String {
        switch self {
        case .grid: lang("View as Cards")
        case .list: lang("View as List")
        }
    }
    
    var imageName: String {
        switch self {
        case .grid: "rectangle.grid.2x2"
        case .list: "list.bullet"
        }
    }
}
