import Foundation

public struct HomeToolbarConfiguration: Equatable, Sendable {
    public var showsAccounts: Bool
    public var showsScan: Bool
    public var sharesBackground: Bool

    public init(showsAccounts: Bool = false, showsScan: Bool = true, sharesBackground: Bool = true) {
        self.showsAccounts = showsAccounts
        self.showsScan = showsScan
        self.sharesBackground = sharesBackground
    }
}

public enum ToolbarSettings {
    public static let accountsKey = "toolbarShowsAccounts"
    public static let scanKey = "toolbarShowsScan"
    public static let sharedBackgroundKey = "toolbarSharesBackground"
    public static let didChangeNotification = Notification.Name("ToolbarSettingsDidChange")

    public static func configuration(in defaults: UserDefaults = .standard) -> HomeToolbarConfiguration {
        HomeToolbarConfiguration(
            showsAccounts: defaults.bool(forKey: accountsKey),
            showsScan: defaults.object(forKey: scanKey) as? Bool ?? true,
            sharesBackground: defaults.object(forKey: sharedBackgroundKey) as? Bool ?? true
        )
    }

    public static func notifyDidChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
