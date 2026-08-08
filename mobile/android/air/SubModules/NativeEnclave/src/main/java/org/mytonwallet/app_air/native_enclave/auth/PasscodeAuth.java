package org.mytonwallet.app_air.native_enclave.auth;

import androidx.fragment.app.FragmentActivity;

import org.mytonwallet.app_air.native_enclave.crypto.AesGcm;
import org.mytonwallet.app_air.native_enclave.crypto.HardwareKeyManager;
import org.mytonwallet.app_air.native_enclave.crypto.KeyDerivation;
import org.mytonwallet.app_air.native_enclave.storage.EnclaveStorage;

import javax.crypto.AEADBadTagException;
import javax.crypto.SecretKey;

public class PasscodeAuth implements EnclaveAuth {

    private final EnclaveStorage storage;

    public PasscodeAuth(EnclaveStorage storage) {
        this.storage = storage;
    }

    @Override
    public void setup(FragmentActivity activity, byte[] masterKey, String passcode, SetupCallback callback) {
        try {
            byte[] salt = KeyDerivation.generateSalt();
            SecretKey kek = KeyDerivation.deriveKeyFromPasscode(passcode, salt);
            String kekEncrypted = AesGcm.encrypt(masterKey, kek);

            storage.storePasscodeCredential(salt, kekEncrypted);
            callback.onSuccess();
        } catch (Exception e) {
            callback.onError("setupPasscode: " + e.getMessage());
        }
    }

    @Override
    public void authorize(FragmentActivity activity, String passcode, AuthorizeCallback callback) {
        try {
            byte[] salt = storage.loadSalt();
            if (salt == null) {
                throw new Exception("Passcode not configured");
            }
            String kekEncrypted = storage.loadMasterKey(AuthType.PASSCODE);
            if (kekEncrypted == null) {
                throw new Exception("Passcode not configured");
            }

            SecretKey kek = KeyDerivation.deriveKeyFromPasscode(passcode, salt);
            callback.onSuccess(AesGcm.decrypt(kekEncrypted, kek));
        } catch (AEADBadTagException e) {
            callback.onError(null);
        } catch (Exception e) {
            callback.onError("authorize: " + e.getMessage());
        }
    }

    @Override
    public void destroy() {
        HardwareKeyManager.deleteKey();
        storage.removeMasterKey(AuthType.PASSCODE);
        storage.removeSalt();
    }
}
