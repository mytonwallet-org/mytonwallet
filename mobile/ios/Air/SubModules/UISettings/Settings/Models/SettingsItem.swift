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
//        case changeAvatar
        case editWalletName
        case account(accountId: String)
        case addAccount
        case appearance
        case assetsAndActivity
        case connectedApps
        case language
        case security
        case walletVersions
        case questionAndAnswers
        case terms
        case switchToCapacitor
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
                icon: UIImage(named: "EditWalletNameIcon", in: AirBundle, compatibleWith: nil)!.withRenderingMode(.alwaysTemplate),
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
                                                                  currency: TokenStore.baseCurrency?.sign,
                                                                  decimalsCount: TokenStore.baseCurrency?.decimalsCount) : nil
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
        case .addAccount:
            return SettingsItem(
                id: .addAccount,
                icon: UIImage(named: "AddAccountIcon", in: AirBundle, compatibleWith: nil)!.withRenderingMode(.alwaysTemplate),
                title: lang("Add Account"),
                hasPrimaryColor: true,
                hasChild: false,
                isDangerous: false
            )
        case .appearance:
            return SettingsItem(
                id: .appearance,
                icon: UIImage(named: "AppearanceIcon", in: AirBundle, compatibleWith: nil)!,
                title: lang("Appearance"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .assetsAndActivity:
            return SettingsItem(
                id: .assetsAndActivity,
                icon: UIImage(named: "AssetsAndActivityIcon", in: AirBundle, compatibleWith: nil)!,
                title: lang("Assets & Activity"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .connectedApps:
            return SettingsItem(
                id: .connectedApps,
                icon: UIImage(named: "DappsIcon", in: AirBundle, compatibleWith: nil)!,
                title: lang("Connected Dapps"),
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
                icon: UIImage(named: "WalletVersionsIcon", in: AirBundle, compatibleWith: nil)!,
                title: lang("Wallet Versions"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .questionAndAnswers:
            return SettingsItem(
                id: .questionAndAnswers,
                icon: UIImage(named: "QuestionAnswersIcon", in: AirBundle, compatibleWith: nil)!,
                title: lang("Help Center"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .terms:
            return SettingsItem(
                id: .terms,
                icon: UIImage(named: "TermsIcon", in: AirBundle, compatibleWith: nil)!,
                title: lang("Terms of Use"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: false
            )
        case .switchToCapacitor:
            return SettingsItem(
                id: .switchToCapacitor,
                icon: nil,
                title: lang("Switch to Legacy Version"),
                hasPrimaryColor: true,
                hasChild: false,
                isDangerous: true
            )
        case .signout:
            return SettingsItem(
                id: .signout,
                icon: nil,
                title: lang("Log Out"),
                hasPrimaryColor: false,
                hasChild: true,
                isDangerous: true
            )
        }
    }
}
