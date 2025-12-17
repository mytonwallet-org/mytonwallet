
import UIKit
import WalletContext


public enum MAutolockOption: String, Equatable, Hashable, Codable, Sendable, CaseIterable, Identifiable {
    case never = "never"
    case thirtySeconds = "1"
    case threeMinutes = "2"
    case tenMinutes = "3"

    public var period: TimeInterval? {
        switch self {
        case .never: return nil
        case .thirtySeconds: return 30
        case .threeMinutes: return 3 * 60
        case .tenMinutes: return 10 * 60
        }
    }

    public var displayName: String {
        switch self {
        case .never: return lang("Disabled")
        case .thirtySeconds: return lang("30 seconds")
        case .threeMinutes: return lang("3 minutes")
        case .tenMinutes: return lang("10 minutes")
        }
    }
    
    public var id: Self { self }
}
