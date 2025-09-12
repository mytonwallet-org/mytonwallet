
public enum AccountType: String, Equatable, Hashable, Codable, Sendable {
    case mnemonic = "mnemonic"
    case hardware = "hardware"
    case view = "view"
}

extension AccountType {
    var isStoredEncrypted: Bool { self == .mnemonic }
}
