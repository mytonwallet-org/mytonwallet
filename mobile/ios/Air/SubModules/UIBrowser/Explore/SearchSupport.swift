//
//  ExploreVC.swift
//  UIBrowser
//
//  Created by Sina on 6/25/24.
//

import Kingfisher
import SwiftUI
import UIComponents
import UIInAppBrowser
import UIKit
import WalletContext
import WalletCore

extension ApiSite {
    func matches(_ searchString: String) -> Bool {
        let s = searchString.lowercased()
        return name.lowercased().contains(s) || description.lowercased().contains(s) || url.lowercased().contains(s)
    }
}

extension ApiDapp {
    func matches(_ searchString: String) -> Bool {
        let searchString = searchString.lowercased()
        return name.lowercased().contains(searchString) || url.lowercased().contains(searchString)
    }
}

extension BrowserHistoryItem {
    func matches(_ searchString: String) -> Bool {
        let s = searchString.lowercased()
        return title.lowercased().contains(s) || url.lowercased().contains(s)
    }
}
