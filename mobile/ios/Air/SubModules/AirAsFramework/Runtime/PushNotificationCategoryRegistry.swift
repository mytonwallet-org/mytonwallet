@preconcurrency import UserNotifications

enum PushNotificationCategoryRegistry {
    static func register() {
        let categories = Set(
            PushNotificationCategoryIdentifier.allCases.map { identifier in
                UNNotificationCategory(
                    identifier: identifier.rawValue,
                    actions: [],
                    intentIdentifiers: [],
                    options: []
                )
            }
        )

        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}

private enum PushNotificationCategoryIdentifier: String, CaseIterable {
    case domainExpiry = "domain_expiry"
    case openUrl = "open_url"
    case stakingReward = "staking_reward"
    case swapStatus = "swap_status"
    case walletActivity = "wallet_activity"
}
