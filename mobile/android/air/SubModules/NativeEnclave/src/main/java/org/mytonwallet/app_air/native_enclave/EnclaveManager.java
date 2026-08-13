package org.mytonwallet.app_air.native_enclave;

import android.content.Context;

import androidx.fragment.app.FragmentActivity;

import org.mytonwallet.app_air.native_enclave.auth.AuthType;
import org.mytonwallet.app_air.native_enclave.auth.BiometricAuth;
import org.mytonwallet.app_air.native_enclave.auth.EnclaveAuth;
import org.mytonwallet.app_air.native_enclave.auth.PasscodeAuth;
import org.mytonwallet.app_air.native_enclave.crypto.AesGcm;
import org.mytonwallet.app_air.native_enclave.crypto.KeyDerivation;
import org.mytonwallet.app_air.native_enclave.storage.EnclaveStorage;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Objects;
import java.util.function.Consumer;
import java.util.function.IntConsumer;

import javax.crypto.SecretKey;

public class EnclaveManager {

    public static EnclaveManager sharedInstance;

    private final EnclaveStorage storage;
    private final SessionManager sessionManager;
    private final EnumMap<AuthType, EnclaveAuth> auths;

    public EnclaveManager(Context context) {
        this.storage = new EnclaveStorage(context);
        this.sessionManager = new SessionManager();
        this.auths = new EnumMap<>(AuthType.class);
        auths.put(AuthType.PASSCODE, new PasscodeAuth(storage));
        auths.put(AuthType.BIOMETRIC, new BiometricAuth(storage));
    }

    // --- Callback ---

    public interface SessionCallback {
        void onSuccess(String token, long validUntil);

        void onError(String error);
    }

    // --- Auth: Setup ---

    public void setupAuth(AuthType authType, String passcode, FragmentActivity activity, SessionCallback callback) {
        try {
            ensureStorageCanBeInitialized();
            reset();
        } catch (Exception e) {
            callback.onError("setupAuth: " + e.getMessage());
            return;
        }

        byte[] masterKey = KeyDerivation.generateMasterKey();
        Objects.requireNonNull(auths.get(authType)).setup(activity, masterKey, passcode, new EnclaveAuth.SetupCallback() {
            @Override
            public void onSuccess() {
                try {
                    storage.storeCurrentVersion();
                    resolveWithSession(authType, false, masterKey, callback);
                } catch (Exception e) {
                    reset();
                    callback.onError("setupAuth: " + e.getMessage());
                }
            }

            @Override
            public void onError(String error) {
                callback.onError(error);
            }
        });
    }

    // --- Auth: Authorize ---

    public void authorize(AuthType authType, boolean isLong, String passcode,
                          FragmentActivity activity, SessionCallback callback) {
        authorize(authType, isLong, 1, passcode, activity, callback);
    }

    public void authorize(AuthType authType, boolean isLong, int usageCount, String passcode,
                          FragmentActivity activity, SessionCallback callback) {
        try {
            requireCurrentStorageVersion();
        } catch (Exception e) {
            callback.onError("authorize: " + e.getMessage());
            return;
        }

        Objects.requireNonNull(auths.get(authType)).authorize(activity, passcode, new EnclaveAuth.AuthorizeCallback() {
            @Override
            public void onSuccess(byte[] masterKey) {
                resolveWithSession(authType, isLong, usageCount, masterKey, callback);
            }

            @Override
            public void onError(String error) {
                if (error == null)
                    callback.onSuccess(null, 0);
                else
                    callback.onError(error);
            }
        });
    }

    public void authorizeWithBiometrics(FragmentActivity activity,
                                        Consumer<IntConsumer> onAuthenticated,
                                        SessionCallback callback) {
        try {
            requireCurrentStorageVersion();
        } catch (Exception e) {
            callback.onError("authorize: " + e.getMessage());
            return;
        }

        Objects.requireNonNull(auths.get(AuthType.BIOMETRIC)).authorize(
            activity,
            null,
            new EnclaveAuth.AuthorizeCallback() {
                @Override
                public void onSuccess(byte[] masterKey) {
                    onAuthenticated.accept(usageCount -> resolveWithSession(
                        AuthType.BIOMETRIC,
                        false,
                        usageCount,
                        masterKey,
                        callback
                    ));
                }

                @Override
                public void onError(String error) {
                    if (error == null)
                        callback.onSuccess(null, 0);
                    else
                        callback.onError(error);
                }
            }
        );
    }

    // --- Auth: Migrate ---

    public void migrateAuth(String currentToken, AuthType newAuthType, String passcode,
                            boolean shouldReplace, FragmentActivity activity, SessionCallback callback) {
        migrateAuth(currentToken, newAuthType, passcode, shouldReplace, 1, activity, callback);
    }

    public void migrateAuth(String currentToken, AuthType newAuthType, String passcode,
                            boolean shouldReplace, int usageCount, FragmentActivity activity,
                            SessionCallback callback) {
        try {
            requireCurrentStorageVersion();

            // The returned array belongs to the old session, and `invalidateShortSession` below zeroizes it.
            // The new session needs its own copy - otherwise it would end up holding an all-zero key,
            // and secrets imported with its token would be encrypted unrecoverably.
            byte[] masterKey = sessionManager.validateSessionAndGetMasterKey(currentToken, false).clone();
            AuthType currentAuthType = parseAuthTypeFromToken(currentToken);

            Objects.requireNonNull(auths.get(newAuthType)).setup(activity, masterKey, passcode, new EnclaveAuth.SetupCallback() {
                @Override
                public void onSuccess() {
                    sessionManager.invalidateShortSession(currentToken);
                    if (shouldReplace && currentAuthType != newAuthType) {
                        Objects.requireNonNull(auths.get(currentAuthType)).destroy();
                    }
                    resolveWithSession(newAuthType, false, usageCount, masterKey, callback);
                }

                @Override
                public void onError(String error) {
                    callback.onError(error);
                }
            });
        } catch (Exception e) {
            callback.onError("migrateAuth: " + e.getMessage());
        }
    }

    public void removeAuth(AuthType authType) {
        Objects.requireNonNull(auths.get(authType)).destroy();
    }

    // --- Secrets ---

    public void importSecret(String id, String secret, String token) throws Exception {
        requireCurrentStorageVersion();
        byte[] masterKey = sessionManager.validateSessionAndGetMasterKey(token, true);
        storage.storeSecret(id, encryptForStorage(secret.getBytes(StandardCharsets.UTF_8), masterKey));
    }

    public String exportSecret(String id, String token) throws Exception {
        requireCurrentStorageVersion();
        byte[] masterKey = sessionManager.validateSessionAndGetMasterKey(token, true);
        byte[] decrypted = decryptFromStorage(storage.loadSecret(id), masterKey);
        return new String(decrypted, StandardCharsets.UTF_8);
    }

    public void duplicateSecret(String fromId, String toId) throws Exception {
        requireCurrentStorageVersion();
        storage.copySecret(fromId, toId);
    }

    public void removeSecret(String id) {
        storage.removeSecret(id);
    }

    public void sign(String id, String ignoredData, String token) throws Exception {
        requireCurrentStorageVersion();
        sessionManager.validateSessionAndGetMasterKey(token, true);
        if (!storage.hasSecret(id)) {
            throw new Exception("Secret not found: " + id);
        }
        // Stub: signing not yet implemented
    }

    // --- Reset ---

    public void reset() {
        sessionManager.clearAll();
        for (EnclaveAuth auth : auths.values()) {
            auth.destroy();
        }
        storage.clear();
    }

    // --- Migration from JS enclave ---

    public void migrateSecrets(List<String[]> secrets, AuthType authType, String passcode,
                               FragmentActivity activity, SessionCallback callback) {
        migrateSecrets(secrets, authType, passcode, 1, activity, callback);
    }

    public void migrateSecrets(List<String[]> secrets, AuthType authType, String passcode,
                               int usageCount, FragmentActivity activity, SessionCallback callback) {
        try {
            ensureStorageCanBeInitialized();
        } catch (Exception e) {
            callback.onError("migrateSecrets: " + e.getMessage());
            return;
        }

        reset();
        try {
            byte[] masterKey = KeyDerivation.generateMasterKey();
            List<String[]> encryptedPairs = new ArrayList<>();
            for (String[] entry : secrets) {
                String enclaveEncrypted = encryptForStorage(entry[1].getBytes(StandardCharsets.UTF_8), masterKey);
                encryptedPairs.add(new String[]{entry[0], enclaveEncrypted});
            }

            Objects.requireNonNull(auths.get(authType)).setup(activity, masterKey, passcode, new EnclaveAuth.SetupCallback() {
                @Override
                public void onSuccess() {
                    try {
                        storage.storeSecretsBatch(encryptedPairs);
                        storage.storeCurrentVersionWithLegacyCleanupPending();
                        resolveWithSession(authType, false, usageCount, masterKey, callback);
                    } catch (Exception e) {
                        reset();
                        callback.onError("migrateSecrets: " + e.getMessage());
                    }
                }

                @Override
                public void onError(String error) {
                    reset();
                    callback.onError(error);
                }
            });
        } catch (Exception e) {
            reset();
            callback.onError("migrateSecrets: " + e.getMessage());
        }
    }

    // --- Helpers ---

    public boolean isLegacyMigrationAllowed() {
        try {
            return storage.loadVersion() == null;
        } catch (Exception e) {
            return false;
        }
    }

    public boolean isLegacyCleanupPending() {
        try {
            requireCurrentStorageVersion();
            return storage.isLegacyCleanupPending();
        } catch (Exception e) {
            return false;
        }
    }

    public boolean isPasscodeAuthConfigured() {
        try {
            requireCurrentStorageVersion();
            return storage.hasPasscodeCredential();
        } catch (Exception e) {
            return false;
        }
    }

    public boolean isBiometricAuthConfigured() {
        try {
            requireCurrentStorageVersion();
            return storage.hasMasterKey(AuthType.BIOMETRIC);
        } catch (Exception e) {
            return false;
        }
    }

    public boolean hasSecret(String id) {
        return storage.hasSecret(id);
    }

    public void completeLegacyCleanup() {
        storage.completeLegacyCleanup();
    }

    private void ensureStorageCanBeInitialized() throws Exception {
        Integer version = storage.loadVersion();
        if (version == null) {
            return;
        }
        if (version == EnclaveStorage.CURRENT_VERSION) {
            throw new Exception("Authentication is already configured");
        }
        throw new Exception("Unsupported enclave version: " + version);
    }

    private void requireCurrentStorageVersion() throws Exception {
        Integer version = storage.loadVersion();
        if (version == null) {
            throw new Exception("Enclave storage is not configured");
        }
        if (version != EnclaveStorage.CURRENT_VERSION) {
            throw new Exception("Unsupported enclave version: " + version);
        }
    }

    private String encryptForStorage(byte[] data, byte[] masterKey) throws Exception {
        SecretKey aesKey = KeyDerivation.importMasterKey(masterKey);
        return AesGcm.encrypt(data, aesKey);
    }

    private byte[] decryptFromStorage(String stored, byte[] masterKey) throws Exception {
        SecretKey aesKey = KeyDerivation.importMasterKey(masterKey);
        return AesGcm.decrypt(stored, aesKey);
    }

    private void resolveWithSession(AuthType authType, boolean isLong,
                                    byte[] masterKey, SessionCallback callback) {
        resolveWithSession(authType, isLong, 1, masterKey, callback);
    }

    private void resolveWithSession(AuthType authType, boolean isLong, int usageCount,
                                    byte[] masterKey, SessionCallback callback) {
        SessionManager.SessionResult result =
                sessionManager.createSession(authType, isLong, usageCount, masterKey);
        callback.onSuccess(result.token, result.validUntil);
    }

    public static AuthType parseAuthTypeFromToken(String token) {
        String prefix = token.split(":")[0];
        for (AuthType type : AuthType.values()) {
            if (type.key.equals(prefix)) return type;
        }
        return null;
    }
}
