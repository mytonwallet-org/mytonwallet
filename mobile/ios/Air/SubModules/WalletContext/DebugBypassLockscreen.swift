import Foundation

public enum DebugBypassLockscreen {
    public static let environmentVariable = "BYPASS_LOCKSCREEN"
    public static let userDefaultsKey = "debug_bypassLockscreen"

    public static var isEnabled: Bool {
        #if DEBUG
        return isEnabledFromEnvironment || isEnabledFromUserDefaults
        #else
        return false
        #endif
    }

    public static var isEnabledFromEnvironment: Bool {
        #if DEBUG
        guard let rawValue = ProcessInfo.processInfo.environment[environmentVariable] else {
            return false
        }
        return isTruthy(rawValue)
        #else
        return false
        #endif
    }

    public static var isEnabledFromUserDefaults: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
        #else
        return false
        #endif
    }

    #if DEBUG
    private static func isTruthy(_ rawValue: String) -> Bool {
        switch rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        {
        case "1", "true", "yes", "y", "on":
            return true
        default:
            return false
        }
    }
    #endif
}
