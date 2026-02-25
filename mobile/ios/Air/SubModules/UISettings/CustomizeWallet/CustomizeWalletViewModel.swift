//
//  WalletSettingsVC.swift
//  UISettings
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

struct AccountInfo {
    var currentCard: ApiNft?
    var availableCards: [ApiNft?] = []
}

@Perceptible
@MainActor final class CustomizeWalletViewModel {
    
    @PerceptionIgnored
    @Dependency(\.accountStore) var accountStore
    @PerceptionIgnored
    @Dependency(\.accountSettings) var accountSettings
    @PerceptionIgnored
    @Dependency(\.balanceStore.accountBalanceData) var balanceData
    @PerceptionIgnored
    @Dependency(\.tokenStore.baseCurrency) var baseCurrency
    
    var selectedAccountId: String = ""
    var selectedAccount: MAccount { accountStore.accountsById[selectedAccountId] ?? DUMMY_ACCOUNT }
    
    var tintColor: Color { Color(getAccentColorByIndex(palletteSettingsViewModel.currentColorId)) }
    
    var accountCardsById: [String: AccountMtwCards] = [:]
    
    let palletteSettingsViewModel: PaletteSettingsViewModel
    var accountObservation: ObserveToken?
    
    var isRestricted: Bool { ConfigStore.shared.shouldRestrictBuyNfts }
    
    init(initialAccountId: String?) {
        @Dependency(\.accountStore) var accountStore
        let accountId = initialAccountId ?? accountStore.currentAccountId
        self.selectedAccountId = accountId
        self.palletteSettingsViewModel = PaletteSettingsViewModel(accountId: accountId)
        accountObservation = observe {
            withAnimation { [weak self] in
                guard let self else { return }
                palletteSettingsViewModel.accountId = selectedAccountId
            }
        }
    }
    
    func getAccountCards(accountId: String) -> AccountMtwCards {
        if let accountCards = accountCardsById[accountId] {
            return accountCards
        } else {
            let accountCards = AccountMtwCards(accountId: accountId)
            accountCardsById[accountId] = accountCards
            return accountCards
        }
    }
    
    var selectedAccountInfo: AccountInfo {
        getAccountCards(accountId: selectedAccountId).info
    }
    
    func selectCard(_ card: ApiNft?) {
        withAnimation {
            accountSettings.for(accountId: selectedAccountId).setBackgroundNft(card)
        }
    }
    
    var balance: BaseCurrencyAmount? {
        balanceData[selectedAccountId]?.totalBalance
    }
}


@Perceptible
final class AccountMtwCards: WalletCoreData.EventsObserver {
    
    let accountId: String

    @PerceptionIgnored
    @Dependency(\.accountSettings) var accountSettings
    @PerceptionIgnored
    @Dependency(\.nftStore) var nftStore
    
    private var cards: OrderedDictionary<String, ApiNft>

    init(accountId: String) {
        self.accountId = accountId
        @PerceptionIgnored
        @Dependency(\.nftStore) var nftStore
        cards = nftStore.getAccountMtwCards(accountId: accountId)
        Task {
            try await Api.fetchNftsFromCollection(
                accountId: accountId,
                collection: .mtwCardsCollection,
            )
        }
        WalletCoreData.add(eventObserver: self)
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .nftsChanged(let accountId):
            if accountId == self.accountId {
                withAnimation {
                    cards = nftStore.getAccountMtwCards(accountId: accountId)
                }
            }
        default:
            break
        }
    }
    
    var info: AccountInfo {
        AccountInfo(
            currentCard: accountSettings.for(accountId: accountId).backgroundNft,
            availableCards: [nil] + Array(cards.values)
        )
    }
}
