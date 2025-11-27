//
//  SettingsItem.swift
//  UISettings
//
//  Created by Sina on 6/26/24.
//

import Foundation
import UIKit
import WalletCore
import WalletContext

struct SettingsItem: Equatable, Identifiable {
    
    enum Identifier: Equatable, Hashable {
        case editWalletName
        case account(accountId: String)
        case walletSettings
        case addAccount
        case notifications
        case appearance
        case assetsAndActivity
        case connectedApps
        case language
        case security
        case walletVersions
        case tips
        case helpCenter
        case support
        case about
        case signout
    }
    
    let id: Identifier
    let icon: UIImage?
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    let hasPrimaryColor: Bool
    let hasChild: Bool
    let isDangerous: Bool
}


extension SettingsItem.Identifier {
    var content: SettingsItem {
        switch self {
        case .editWalletName:
            return SettingsItem(
                id: .editWalletName,
                icon: UIImage.airBundle("EditWalletNameIcon").withRenderingMode(.alwaysTemplate),
                title: lang("Edit Wallet Name"),
                hasPrimaryColor: true,
                hasChild: false,
                isDangerous: false
            )
        case .account(let accountId):
            let account = AccountStore.accountsById[accountId]
            let title: String
            let subtitle: String?
            if let t = account?.title?.nilIfEmpty {
                title = t
                subtitle = formatStartEndAddress(account?.firstAddress ?? "")
            } else {
                title = formatStartEndAddress(account?.firstAddress ?? "")
                subtitle = nil
            }
            let balanceAmount = BalanceStore.getTotalBalanceInBaseCurrency(for: accountId)
            let balance = balanceAmount != nil ? formatAmountText(amount: balanceAmount!,
                                                                  currency: TokenStore.baseCurrency.sign,
                                                                  decimalsCount: TokenStore.baseCurrency.decimalsCount) : nil
            return SettingsItem(
                id: .account(accountId: accountId),
                icon: .avatar(for: account, withSize: 30) ?? UIImage(),
                title: title,
                subtitle: subtitle,
                value: balance,
                hasPrimaryColor: false,
                hasChild: false,
                isDangerous: false
            )
        case .walletSettings:
            return SettingsItem(
                id: .walletSettings,
                icon: UIImage(systemName: "ellipsis"),
                title: lang("Show All Wallets"),
                hasPrimaryColor: true,
                hasChild: false,
                isDangerous: false
            )
        case .addAccount:
            return SettingsItem(
                id: .addAccount,
                icon: UIImage.airBundle("AddAccountIcon").withRenderingMode(.alwaysTemplate),
                title: lang("Add Account"),
                hasPrimaryColor: true,
                hasChild: false,
                isDangerous: false
            )
        case .notifications:
            return SettingsItem(
                id: .notifications,
                icon: UIImage.airBundle("NotificationsSettingsIcon"),
                title: lang("Notifications & Sounds"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .appearance:
            return SettingsItem(
                id: .appearance,
                icon: UIImage.airBundle("AppearanceIcon"),
                title: lang("Appearance"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .assetsAndActivity:
            return SettingsItem(
                id: .assetsAndActivity,
                icon: UIImage.airBundle("AssetsAndActivityIcon"),
                title: lang("Assets & Activity"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .connectedApps:
            return SettingsItem(
                id: .connectedApps,
                icon: UIImage.airBundle("DappsIcon"),
                title: lang("Connected Apps"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .language:
            return SettingsItem(
                id: .language,
                icon: .airBundle("LanguageIcon"),
                title: lang("Language"),
                value: Language.current.nativeName,
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .security:
            return SettingsItem(
                id: .security,
                icon: .airBundle("SecurityIcon"),
                title: lang("Security"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .walletVersions:
            return SettingsItem(
                id: .walletVersions,
                icon: UIImage.airBundle("WalletVersionsIcon"),
                title: lang("Wallet Versions"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .tips:
            return SettingsItem(
                id: .tips,
                icon: UIImage.airBundle("TipsIcon30"),
                title: lang("MyTonWallet Tips"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .helpCenter:
            return SettingsItem(
                id: .helpCenter,
                icon: UIImage.airBundle("BookIcon"),
                title: lang("Help Center"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .support:
            return SettingsItem(
                id: .support,
                icon: UIImage.airBundle("SupportIcon30"),
                title: lang("Get Support"),
                hasPrimaryColor: false,
                hasChild: false,
                isDangerous: false
            )
        case .about:
            return SettingsItem(
                id: .about,
                icon: UIImage.airBundle("TermsIcon"),
                title: lang("About %app_name%", arg1: APP_NAME),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .signout:
            return SettingsItem(
                id: .signout,
                icon: nil,
                title: lang("Remove Wallet"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: true
            )
        }
    }
}
