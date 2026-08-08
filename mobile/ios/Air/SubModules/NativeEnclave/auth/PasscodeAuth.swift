import Foundation

final class PasscodeAuth: EnclaveAuth {
    private let storage: EnclaveStorage

    init(storage: EnclaveStorage) {
        self.storage = storage
    }

    func setup(masterKey: Data, passcode: String?) async throws {
        guard let passcode else {
            throw EnclaveError.passcodeRequired
        }

        let salt = try KeyDerivation.generateSalt()
        let kek = try KeyDerivation.derivePasscodeKey(passcode: passcode, salt: salt)
        let kekEncrypted = try AesGcm.encrypt(masterKey, keyData: kek)
        let hwEncrypted = try HardwareKeyManager.encrypt(kekEncrypted)

        try storage.storePasscodeCredential(
            PasscodeCredential(
                salt: salt,
                wrappedMasterKey: hwEncrypted
            )
        )
    }

    func authorize(passcode: String?) async throws -> Data {
        guard let passcode else {
            throw EnclaveError.passcodeRequired
        }
        guard let credential = try storage.loadPasscodeCredential() else {
            throw EnclaveError.passcodeNotConfigured
        }

        do {
            let kekEncrypted = try HardwareKeyManager.decrypt(credential.wrappedMasterKey)
            let kek = try KeyDerivation.derivePasscodeKey(
                passcode: passcode,
                salt: credential.salt
            )
            return try AesGcm.decrypt(kekEncrypted, keyData: kek)
        } catch {
            throw EnclaveError.invalidSessionToken
        }
    }

    func destroy() async {
        HardwareKeyManager.deleteDataKey()
        storage.removePasscodeCredential()
    }
}
