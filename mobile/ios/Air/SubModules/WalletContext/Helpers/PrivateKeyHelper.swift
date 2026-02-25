import Foundation

private let PRIVATE_KEY_HEX_LENGTH = 64
private let PRIVATE_KEY_WITH_PUBLIC_KEY_HEX_LENGTH = 128

public func isValidPrivateKeyHex(_ privateKey: String) -> Bool {
    privateKey.count == PRIVATE_KEY_HEX_LENGTH || privateKey.count == PRIVATE_KEY_WITH_PUBLIC_KEY_HEX_LENGTH
}

public func normalizePrivateKeyHex(_ privateKey: String) -> String? {
    guard isValidPrivateKeyHex(privateKey) else { return nil }
    return privateKey.count == PRIVATE_KEY_HEX_LENGTH
        ? privateKey
        : String(privateKey.prefix(PRIVATE_KEY_HEX_LENGTH))
}

public func normalizeMnemonicPrivateKey(_ mnemonic: [String]) -> [String]? {
    guard mnemonic.count == 1, let privateKey = normalizePrivateKeyHex(mnemonic[0]) else {
        return nil
    }
    return [privateKey]
}

public func isMnemonicPrivateKey(_ mnemonic: [String]) -> Bool {
    normalizeMnemonicPrivateKey(mnemonic) != nil
}
