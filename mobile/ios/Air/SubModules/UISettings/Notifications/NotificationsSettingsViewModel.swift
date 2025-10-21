
import Foundation
import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

private let log = Log("NotificationsVC")

struct SelectableAccount: Equatable, Hashable, Identifiable {
    
    var account: MAccount
    var isSelected: Bool
    
    var id: String { account.id }
}

final class NotificationsSettingsViewModel: ObservableObject, WalletCoreData.EventsObserver {
    
    @Published var notificationsAreAllowed: Bool = true
    @Published var selectableAccounts: [SelectableAccount]
    @Published var playSounds: Bool = AppStorageHelper.sounds
    
    var selectedCount: Int { selectableAccounts.count(where: \.isSelected) }
    var canSelectAnother: Bool { selectedCount < MAX_PUSH_NOTIFICATIONS_ACCOUNT_COUNT}
    
    var observer: Task<Void, any Error>?
    
    init() {
        let enabledIds = AccountStore.notificationsEnabledAccountIds
        self.selectableAccounts = AccountStore.orderedAccounts
            .map {
                SelectableAccount(account: $0, isSelected: enabledIds.contains($0.id) )
            }
        
        observer = Task {
            for await selectableAccounts in $selectableAccounts.debounce(for: 0.2, scheduler: RunLoop.main).values {
                try Task.checkCancellation()
                await AccountStore.selectedNotificationsAccounts(accounts: selectableAccounts.filter(\.isSelected).map(\.account))
            }
        }
        
        checkIfNotificationsAreEnabled()
    }
    
    deinit {
        observer?.cancel()
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
