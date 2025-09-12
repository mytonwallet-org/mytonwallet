//
//  SettingsVM.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext


class SettingsVM {
    
    func makeSnapshot() -> NSDiffableDataSourceSnapshot<SettingsVC.Section, SettingsVC.Row> {
        var snapshot = NSDiffableDataSourceSnapshot<SettingsVC.Section, SettingsVC.Row>()
        snapshot.appendSections([.header])
        snapshot.appendItems([.editWalletName])
        
        snapshot.appendSections([.accounts])
        let currentAccountId = AccountStore.accountId
        let otherAccounts = AccountStore.accountsById
            .keys
            .filter { $0 != currentAccountId }
            .map(SettingsItem.Identifier.account(accountId:))
        snapshot.appendItems(otherAccounts)
        snapshot.appendItems([.addAccount])
        
        snapshot.appendSections([.general])
        snapshot.appendItems([.appearance])
        snapshot.appendItems([.assetsAndActivity])
        if let count = DappsStore.dappsCount, count > 0 {
            snapshot.appendItems([.connectedApps])
        }
        snapshot.appendItems([.language])

        snapshot.appendSections([.walletData])
        if AuthSupport.accountsSupportAppLock {
            snapshot.appendItems([.security])
        }
        if let count = AccountStore.walletVersionsData?.versions.count, count > 0 {
            snapshot.appendItems([.walletVersions])
        }
        
        snapshot.appendSections([.questionAndAnswers])
        snapshot.appendItems([.questionAndAnswers])
        snapshot.appendItems([.terms])
        
        snapshot.appendSections([.signout])
        snapshot.appendItems([.signout])
        
        return snapshot
    }
    
    func value(for item: SettingsItem) -> String? {
        if let value = item.value {
            // item already has a cached value on the item model
            return value
        }
        switch item.id {
        case .language:
            return Language.current.nativeName
        case .walletVersions:
            return AccountStore.walletVersionsData?.currentVersion
        case .connectedApps:
            return DappsStore.dappsCount != nil ? "\(DappsStore.dappsCount!)" : ""
        default:
            return nil
        }
    }
}
