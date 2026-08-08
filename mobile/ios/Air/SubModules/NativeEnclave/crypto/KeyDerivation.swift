import CommonCrypto
import Foundation
import Security

enum KeyDerivation {
    private static let pbkdf2Iterations = 100_000
    private static let keyLength = 32

    static func generateSalt() throws -> Data {
        try randomBytes(length: 16)
    }

    static func generateMasterKey() throws -> Data {
        try randomBytes(length: 32)
    }

    static func derivePasscodeKey(passcode: String, salt: Data) throws -> Data {
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                passcode,
                passcode.lengthOfBytes(using: .utf8),
                saltBytes.bindMemory(to: UInt8.self).baseAddress,
                salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(pbkdf2Iterations),
                &derived,
                keyLength
            )
        }

        guard status == kCCSuccess else {
            throw EnclaveError.malformedEncryptedPayload
        }

        return Data(derived)
    }

    private static func randomBytes(length: Int) throws -> Data {
        var data = Data(count: length)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, length, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw EnclaveError.keychainError(status)
        }
        return data
    }
}
