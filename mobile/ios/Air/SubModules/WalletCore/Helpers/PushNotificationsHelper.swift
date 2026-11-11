
import UIKit
import UserNotifications
import WalletContext

public func normalizeNotificationTxId(_ txId: String) -> String {
    guard let splitIndex = txId.firstIndex(of: ":") else {
        return txId
    }
    let prefix = txId[..<splitIndex]
    if prefix.allSatisfy(\.isNumber) {
        return String(txId[txId.index(after: splitIndex)...])
    }
    return txId
}

@MainActor
public func requestPushNotificationPermission() async throws -> Bool {
    guard !E2EPushPermission.isSuppressed else { return false }
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        UIApplication.shared.registerForRemoteNotifications()
        return true
    case .notDetermined:
        let isGranted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        if isGranted { UIApplication.shared.registerForRemoteNotifications() }
        return isGranted
    default:
        return false
    }
}

@MainActor
func ensurePushNotificationToken() async throws -> String? {
    guard try await requestPushNotificationPermission() else { return nil }
    for _ in 0..<100 {
        if let token = AppStorageHelper.pushNotifications?.userToken { return token }
        try await Task.sleep(for: .milliseconds(100))
    }
    throw URLError(.timedOut)
}
