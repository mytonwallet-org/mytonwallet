
public enum AccountType: String, Equatable, Hashable, Codable, Sendable {
    case mnemonic = "mnemonic"
    case hardware = "hardware"
    case view = "view"
}

extension AccountType {
    var isStoredEncrypted: Bool { self == .mnemonic }
}

public struct AccountSecretState: Equatable, Hashable, Codable, Sendable {
    public var isRecoveryRequired: Bool?

    public init(isRecoveryRequired: Bool? = nil) {
        self.isRecoveryRequired = isRecoveryRequired
    }

    public static let recoveryRequired = AccountSecretState(isRecoveryRequired: true)
}
