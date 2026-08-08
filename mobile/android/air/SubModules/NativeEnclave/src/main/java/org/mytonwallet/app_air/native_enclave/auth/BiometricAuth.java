package org.mytonwallet.app_air.native_enclave.auth;

import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyPermanentlyInvalidatedException;

import androidx.annotation.NonNull;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.FragmentActivity;

import org.mytonwallet.app_air.native_enclave.R;
import org.mytonwallet.app_air.native_enclave.crypto.AesGcm;
import org.mytonwallet.app_air.native_enclave.crypto.BiometricKeyManager;
import org.mytonwallet.app_air.native_enclave.crypto.EncryptedData;
import org.mytonwallet.app_air.native_enclave.storage.EnclaveStorage;

import java.util.concurrent.Executor;
import java.util.concurrent.Executors;

import javax.crypto.Cipher;

public class BiometricAuth implements EnclaveAuth {

    private final EnclaveStorage storage;
    private final Executor executor = Executors.newSingleThreadExecutor();

    public BiometricAuth(EnclaveStorage storage) {
        this.storage = storage;
    }

    @Override
    public void setup(FragmentActivity activity, byte[] masterKey, String passcode, SetupCallback callback) {
        try {
            BiometricKeyManager.generateBiometricKey();
            Cipher cipher = BiometricKeyManager.getBiometricEncryptCipher();

            showPrompt(activity, ContextCompat.getString(activity, R.string.enclave_use_biometrics), null, cipher, result -> {
                try {
                    assert result.getCryptoObject() != null;
                    Cipher authCipher = result.getCryptoObject().getCipher();
                    assert authCipher != null;
                    EncryptedData biometricEncryptedMasterKey = AesGcm.encryptWithCipher(masterKey, authCipher);
                    storage.storeMasterKey(AuthType.BIOMETRIC, biometricEncryptedMasterKey.toStorageFormat());
                    callback.onSuccess();
                } catch (Exception e) {
                    callback.onError("BiometricAuth: Encryption failed - " + e.getMessage());
                }
            }, callback::onError);
        } catch (Exception e) {
            callback.onError("BiometricAuth: Setup failed - " + e.getMessage());
        }
    }

    @Override
    public void authorize(FragmentActivity activity, String passcode, AuthorizeCallback callback) {
        try {
            String encryptedStr = storage.loadMasterKey(AuthType.BIOMETRIC);
            if (encryptedStr == null) {
                callback.onError("Biometric auth not configured");
                return;
            }
            EncryptedData encryptedData = EncryptedData.fromStorageFormat(encryptedStr);
            Cipher cipher = BiometricKeyManager.getBiometricDecryptCipher(encryptedData.getIv());

            showPrompt(activity, ContextCompat.getString(activity, R.string.enclave_enter_passcode_or_use_biometrics), ContextCompat.getString(activity, R.string.enclave_use_pin), cipher, result -> {
                try {
                    assert result.getCryptoObject() != null;
                    Cipher authCipher = result.getCryptoObject().getCipher();
                    assert authCipher != null;
                    callback.onSuccess(AesGcm.decryptWithCipher(encryptedData.getCiphertext(), authCipher));
                } catch (Exception e) {
                    callback.onError("BiometricAuth: Decryption failed - " + e.getMessage());
                }
            }, callback::onError);
        } catch (KeyPermanentlyInvalidatedException e) {
            callback.onError("Biometric data changed. Please set up biometrics again.");
        } catch (Exception e) {
            callback.onError("BiometricAuth: " + e.getMessage());
        }
    }

    @Override
    public void destroy() {
        BiometricKeyManager.deleteBiometricKey();
        storage.removeMasterKey(AuthType.BIOMETRIC);
    }

    // --- Biometric prompt ---

    private interface AuthSuccessHandler {
        void handle(BiometricPrompt.AuthenticationResult result);
    }

    private interface AuthErrorHandler {
        void handle(String error);
    }

    private void showPrompt(FragmentActivity activity,
                            String title,
                            String cancel,
                            Cipher cipher,
                            AuthSuccessHandler onSuccess,
                            AuthErrorHandler onError) {
        BiometricPrompt.CryptoObject cryptoObject = new BiometricPrompt.CryptoObject(cipher);

        BiometricPrompt prompt = new BiometricPrompt(activity, executor,
            new BiometricPrompt.AuthenticationCallback() {
                @Override
                public void onAuthenticationSucceeded(@NonNull BiometricPrompt.AuthenticationResult result) {
                    new Handler(Looper.getMainLooper()).post(() -> onSuccess.handle(result));
                }

                @Override
                public void onAuthenticationError(int errorCode, @NonNull CharSequence errString) {
                    new Handler(Looper.getMainLooper()).post(() -> onError.handle("BiometricAuth: " + errString));
                }

                @Override
                public void onAuthenticationFailed() {
                    // Individual attempt failure; prompt remains open
                }
            }
        );

        BiometricPrompt.PromptInfo promptInfo = new BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setNegativeButtonText(cancel != null ? cancel : ContextCompat.getString(activity, R.string.enclave_cancel))
            .build();

        activity.runOnUiThread(() -> prompt.authenticate(promptInfo, cryptoObject));
    }
}
