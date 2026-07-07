//
//  WalletSettingsViewModel.swift
//
//  Created by nikstar on 10.11.2025.
//

import UIKit
import WalletContext
import WalletCore
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

@Perceptible
final class WalletSettingsViewModel {

    enum Mode {
        case normal, reordering, select
    }
    
    var currentFilter: WalletFilter = .ledger {
        didSet {
            AppStorageHelper.walletSettingsCurrentFilter = currentFilter.rawValue
        }
    }
    
    var preferredLayout: WalletListLayout {
        didSet {
            AppStorageHelper.walletSettingsListLayout = preferredLayout.rawValue
        }
    }
    
    var filters: [WalletFilter] {
        didSet {
            AppStorageHelper.walletSettingsFilterOrder = filters.map { $0.rawValue }
        }
    }
    
    var selectedAccountIds = Set<String>()
    var segmentedControllerDidSwitchTrigger: Int = 0
    var isDeletingAccounts = false

    private(set) var mode = Mode.normal

    func walletCount(in accounts: some Collection<MAccount>) -> Int {
        let accountType = currentFilter.accountType
        var accountList = Array(accounts)
        if let accountType {
            accountList = accountList.filter { $0.type == accountType }
        }
        return accountList.count
    }
    
    func navigationHeaderTitle(in accounts: some Collection<MAccount>) -> String {
        lang("$wallets_amount", arg1: walletCount(in: accounts))
    }
    
    @MainActor func totalBalance(from balanceDataStore: _BalanceDataStore) -> BaseCurrencyAmount {
        balanceDataStore.totalBalance(ofWalletsWithType: currentFilter.accountType)
    }
    
    @MainActor func navigationHeaderBalance(from balanceDataStore: _BalanceDataStore) -> String {
        lang("$total_balance", arg1: totalBalance(from: balanceDataStore).formatted(.baseCurrencyEquivalent))
    }

    var onStartReordering: (() -> Void)?
    var onStopReordering: ((Bool) -> Void)?
    var onStartSelecting: (() -> Void)?
    var onStopSelecting: (() -> Void)?

    init() {
        let allFilters = OrderedSet(WalletFilter.allCases)
        let savedFilters = OrderedSet(AppStorageHelper.walletSettingsFilterOrder.compactMap { WalletFilter(rawValue: $0) })
        self.filters = Array(savedFilters.union(allFilters))
        self.currentFilter = .init(rawValue: AppStorageHelper.walletSettingsCurrentFilter) ?? .all
        self.preferredLayout = .init(rawValue: AppStorageHelper.walletSettingsListLayout) ?? .grid
    }

    func startSelecting(preselected: [String]) {
        guard !isDeletingAccounts else { return }
        if mode != .select {
            preselected.forEach {
                selectedAccountIds.insert($0)
            }
            mode = .select
            onStartSelecting?()
        }
    }
    
    func startReordering() {
        guard !isDeletingAccounts else { return }
        if mode != .reordering {
            mode = .reordering
            onStartReordering?()
        }
    }
    
    func stopReordering(isCanceled: Bool) {
        guard !isDeletingAccounts else { return }
        if mode == .reordering {
            mode = .normal
            onStopReordering?(isCanceled)
        }
    }
    
    func stopSelecting() {
        guard !isDeletingAccounts else { return }
        if mode == .select {
            mode = .normal
            selectedAccountIds.removeAll()
            onStopSelecting?()
        }
    }
    
    func toggleSelectAll(accountIds: [String]) {
        guard mode == .select, !isDeletingAccounts else { return }
        let allIds = Set(accountIds)
        if selectedAccountIds == allIds {
            selectedAccountIds.removeAll()
        } else {
            selectedAccountIds = allIds
        }
    }
    
    @MainActor func deleteAccounts(_ accountIds: [String]) {
        showDeleteSelectedAccountsAlert(
            accountsIdsToDelete: accountIds,
            onWillDelete: { [weak self] in
                self?.isDeletingAccounts = true
            },
            onSuccess: { [weak self] in
                self?.isDeletingAccounts = false
                self?.stopSelecting()
            },
            onFailure: { [weak self] _ in
                self?.isDeletingAccounts = false
            }
        )
    }
    
    @MainActor func deleteSelectedWallets() {
        deleteAccounts(Array(selectedAccountIds))
    }
}
