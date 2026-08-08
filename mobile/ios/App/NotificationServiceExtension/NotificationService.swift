import Foundation
import UserNotifications
import WalletContext
import WalletCoreTypes

final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        if let bestAttemptContent {
            NotificationContentAdjuster.adjust(bestAttemptContent)
            contentHandler(bestAttemptContent)
        } else {
            contentHandler(request.content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }
}

private enum NotificationContentAdjuster {
    private static let stakingAmountLocalizationKeys: Set<String> = [
        "push_activity_staking_profit",
        "push_activity_staking_loyalty_profit",
    ]
    private static let domainDaysPluralKeys: [String: String] = [
        "push_domain_expires_in_days": "push_domain_expires_in_days_number",
        "push_domain_expired_days_ago": "push_domain_expired_days_ago_number",
    ]

    static func adjust(_ content: UNMutableNotificationContent) {
        guard
            let alert = NotificationAlert(userInfo: content.userInfo),
            let bodyKey = alert.bodyLocalizationKey
        else {
            return
        }

        if let body = adjustedStakingProfitBody(alert, bodyKey: bodyKey) {
            content.body = body
            return
        }

        if let body = adjustedDomainDaysBody(alert, bodyKey: bodyKey) {
            content.body = body
            return
        }        
    }

    private static func adjustedStakingProfitBody(_ alert: NotificationAlert, bodyKey: String) -> String? {
        guard
            stakingAmountLocalizationKeys.contains(bodyKey),
            let amountArg = alert.bodyLocalizationArgs.first,
            let formattedAmount = formattedGramAmount(amountArg)
        else {
            return nil
        }

        var bodyArgs = alert.bodyLocalizationArgs
        bodyArgs[0] = formattedAmount

        return localizedString(forKey: bodyKey, stringArguments: bodyArgs)
    }

    private static func adjustedDomainDaysBody(_ alert: NotificationAlert, bodyKey: String) -> String? {
        guard
            let localKey = domainDaysPluralKeys[bodyKey],
            alert.bodyLocalizationArgs.count >= 2,
            let days = Int64(alert.bodyLocalizationArgs[1].trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }

        return localizedString(
            forKey: localKey,
            arguments: [alert.bodyLocalizationArgs[0] as NSString, days]
        )
    }

    private static func formattedGramAmount(_ amount: String) -> String? {
        guard amount.contains(where: \.isWholeNumber) else {
            return nil
        }

        let token = ApiToken.TONCOIN
        let tokenAmount = TokenAmount(amountValue(amount, digits: token.decimals), token)

        return DecimalAmountFormatStyle<ApiToken>(preset: .defaultAdaptive, showSymbol: false)
            .format(tokenAmount)
    }

    private static func localizedString(forKey key: String, stringArguments: [String]) -> String? {
        localizedString(forKey: key, arguments: stringArguments.map { $0 as NSString })
    }

    private static func localizedString(forKey key: String, arguments: [CVarArg]) -> String? {
        let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        guard format != key, !format.isEmpty else {
            return nil
        }

        guard !arguments.isEmpty else {
            return format
        }

        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}

private struct NotificationAlert {
    let bodyLocalizationKey: String?
    let bodyLocalizationArgs: [String]

    init?(userInfo: [AnyHashable: Any]) {
        guard
            let aps = userInfo["aps"] as? [String: Any],
            let alert = aps["alert"] as? [String: Any]
        else {
            return nil
        }

        bodyLocalizationKey = alert["loc-key"] as? String
        bodyLocalizationArgs = Self.stringArray(alert["loc-args"])
    }

    private static func stringArray(_ value: Any?) -> [String] {
        if let strings = value as? [String] {
            return strings
        }

        if let values = value as? [Any] {
            return values.map { String(describing: $0) }
        }

        return []
    }
}
