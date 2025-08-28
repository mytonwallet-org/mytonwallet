//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Kingfisher

extension ApiSite {
    func matches(_ searchString: String) -> Bool {
        let searchString = searchString.lowercased()
        return self.name.lowercased().contains(searchString) || self.url.contains(searchString)
    }
}
