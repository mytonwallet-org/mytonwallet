
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Perception
import SwiftNavigation

private let log = Log("NotificationsVC")

struct SelectableAccount: Equatable, Hashable, Identifiable {
    
    var account: MAccount
    var isSelected: Bool
    
    var id: String { account.id }
}

@Perceptible
final class NotificationsSettingsViewModel: WalletCoreData.EventsObserver {
    
    var notificationsAreAllowed: Bool = true
    var selectableAccounts: [SelectableAccount]
    var playSounds: Bool = AppStorageHelper.sounds
    
    var selectedCount: Int { selectableAccounts.count(where: \.isSelected) }
    var canSelectAnother: Bool { selectedCount < MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT}
    
    @PerceptionIgnored
    var observeSelectedAccounts: ObserveToken?
    @PerceptionIgnored
    var applyTask: Task<Void, any Error>?
    
    init() {
        let enabledIds = AccountStore.notificationsEnabledAccountIds
        self.selectableAccounts = AccountStore.orderedAccounts
            .map {
                SelectableAccount(account: $0, isSelected: enabledIds.contains($0.id) )
            }
        
        observeSelectedAccounts = observe { [weak self] in
            guard let self else { return }
            let selectedAccounts = selectableAccounts.filter(\.isSelected).map(\.account)
            applyTask?.cancel()
            applyTask = Task {
                try await Task.sleep(for: .seconds(0.2))
                await AccountStore.selectedNotificationsAccounts(accounts: selectedAccounts)
            }
        }
        
        checkIfNotificationsAreEnabled()
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        default:
            break
        }
    }
    
    func toggledOff() {
        selectableAccounts = selectableAccounts.map { .init(account: $0.account, isSelected: false) }
    }
    
    func toggledOn() {
        if selectedCount == 0 {
            let idsToEnable = Set(selectableAccounts.prefix(MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT).map(\.id))
            selectableAccounts = selectableAccounts.map { .init(account: $0.account, isSelected: idsToEnable.contains($0.id)) }
        }
    }
    
    func checkIfNotificationsAreEnabled() {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                withAnimation {
                    self.notificationsAreAllowed = true
                }
            case .denied:
                withAnimation {
                    self.notificationsAreAllowed = false
                }
            case .notDetermined:
                break // happens at app launch
            @unknown default:
                break
            }
        }
    }
}
