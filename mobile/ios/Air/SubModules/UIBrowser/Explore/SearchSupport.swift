//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import Kingfisher
import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

extension ApiSite {
    func matches(_ searchString: String) -> Bool {
        let searchString = searchString.lowercased()
        // Improvement: caseInsensitiveContains()
        return name.lowercased().contains(searchString) || url.contains(searchString)
    }
}
