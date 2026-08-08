import CryptoKit
import Foundation

enum AesGcm {
    static func encrypt(_ data: Data, keyData: Data) throws -> String {
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw EnclaveError.malformedEncryptedPayload
        }
        return combined.base64EncodedString()
    }

    static func decrypt(_ encrypted: String, keyData: Data) throws -> Data {
        if encrypted.contains(":") {
            let encryptedData = try EncryptedData.fromStorageFormat(encrypted)
            return try decrypt(encryptedData, keyData: keyData)
        }

        guard let combined = Data(base64Encoded: encrypted) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        let key = SymmetricKey(data: keyData)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key)
    }

    static func encryptToEncryptedData(_ data: Data, keyData: Data) throws -> EncryptedData {
        let key = SymmetricKey(data: keyData)
        let sealed = try AES.GCM.seal(data, using: key)
        let iv = sealed.nonce.withUnsafeBytes { Data($0) }
        let ciphertextWithTag = sealed.ciphertext + sealed.tag
        return EncryptedData(iv: iv, ciphertext: ciphertextWithTag)
    }

    static func decrypt(_ encryptedData: EncryptedData, keyData: Data) throws -> Data {
        guard encryptedData.ciphertext.count >= 16 else {
            throw EnclaveError.malformedEncryptedPayload
        }

        let tag = encryptedData.ciphertext.suffix(16)
        let ciphertext = encryptedData.ciphertext.dropLast(16)

        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: encryptedData.iv)
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(box, using: key)
    }
}
