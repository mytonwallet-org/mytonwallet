import Foundation

struct EncryptedData {
    let iv: Data
    let ciphertext: Data

    func toStorageFormat() -> String {
        iv.base64EncodedString() + ":" + ciphertext.base64EncodedString()
    }

    static func fromStorageFormat(_ stored: String) throws -> EncryptedData {
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let iv = Data(base64Encoded: parts[0]),
              let ciphertext = Data(base64Encoded: parts[1]) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        return EncryptedData(iv: iv, ciphertext: ciphertext)
    }
}
