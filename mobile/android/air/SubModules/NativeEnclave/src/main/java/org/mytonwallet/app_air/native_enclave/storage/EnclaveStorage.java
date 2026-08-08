package org.mytonwallet.app_air.native_enclave.storage;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Base64;

import org.mytonwallet.app_air.native_enclave.auth.AuthType;
import org.mytonwallet.app_air.native_enclave.crypto.HardwareKeyManager;

import java.util.List;

public class EnclaveStorage {

    public static final int CURRENT_VERSION = 0;

    private static final String PREF_VERSION = "state:enclave_version";
    private static final String PREF_LEGACY_CLEANUP_PENDING = "state:legacy_cleanup_pending";
    private static final String PREF_SALT = "auth:salt";
    private static final String MASTER_KEY_PREFIX = "master_key:";
    private static final String SECRET_PREFIX = "secret#";

    private final Context context;
    private final SharedPreferences prefs;

    public EnclaveStorage(Context context) {
        this.context = context.getApplicationContext();
        this.prefs = this.context.getSharedPreferences("NativeEnclavePrefs", Context.MODE_PRIVATE);
    }

    // --- Version ---

    public void storeCurrentVersion() throws Exception {
        storeCurrentVersion(false);
    }

    public void storeCurrentVersionWithLegacyCleanupPending() throws Exception {
        storeCurrentVersion(true);
    }

    private void storeCurrentVersion(boolean legacyCleanupPending) throws Exception {
        SharedPreferences.Editor editor = prefs.edit()
            .putString(PREF_VERSION, String.valueOf(CURRENT_VERSION));
        if (legacyCleanupPending) {
            editor.putBoolean(PREF_LEGACY_CLEANUP_PENDING, true);
        } else {
            editor.remove(PREF_LEGACY_CLEANUP_PENDING);
        }
        boolean committed = editor.commit();
        if (!committed) {
            throw new Exception("Failed to store enclave version");
        }
    }

    public Integer loadVersion() throws Exception {
        Object stored = prefs.getAll().get(PREF_VERSION);
        if (stored == null) {
            return null;
        }
        if (!(stored instanceof String)) {
            throw new Exception("Unsupported enclave version: " + stored);
        }

        try {
            int version = Integer.parseInt((String) stored);
            if (version < 0) {
                throw new NumberFormatException();
            }
            return version;
        } catch (NumberFormatException e) {
            throw new Exception("Unsupported enclave version: " + stored);
        }
    }

    public boolean isLegacyCleanupPending() {
        return prefs.getBoolean(PREF_LEGACY_CLEANUP_PENDING, false);
    }

    public void completeLegacyCleanup() {
        prefs.edit().remove(PREF_LEGACY_CLEANUP_PENDING).commit();
    }

    // --- Passcode credential ---

    public void storePasscodeCredential(byte[] salt, String enclaveEncryptedMasterKey) throws Exception {
        String plainBase64 = Base64.encodeToString(salt, Base64.NO_WRAP);
        String encryptedSalt = HardwareKeyManager.encrypt(context, plainBase64);
        String encryptedMasterKey = HardwareKeyManager.encrypt(context, enclaveEncryptedMasterKey);
        boolean committed = prefs.edit()
            .putString(PREF_SALT, encryptedSalt)
            .putString(MASTER_KEY_PREFIX + AuthType.PASSCODE.key, encryptedMasterKey)
            .commit();
        if (!committed) {
            throw new Exception("Failed to store passcode credential");
        }
    }

    public byte[] loadSalt() throws Exception {
        return Base64.decode(loadAndDecrypt(PREF_SALT), Base64.NO_WRAP);
    }

    public boolean hasPasscodeCredential() {
        return prefs.contains(PREF_SALT)
            && prefs.contains(MASTER_KEY_PREFIX + AuthType.PASSCODE.key);
    }

    public void removeSalt() {
        remove(PREF_SALT);
    }

    // --- Encrypted master key ---

    public void storeMasterKey(AuthType authType, String enclaveEncryptedMasterKey) throws Exception {
        String encrypted = HardwareKeyManager.encrypt(context, enclaveEncryptedMasterKey);
        boolean committed = prefs.edit()
            .putString(MASTER_KEY_PREFIX + authType.key, encrypted)
            .commit();
        if (!committed) {
            throw new Exception("Failed to store master key");
        }
    }

    public String loadMasterKey(AuthType authType) throws Exception {
        return loadAndDecrypt(MASTER_KEY_PREFIX + authType.key);
    }

    public boolean hasMasterKey(AuthType authType) {
        return prefs.contains(MASTER_KEY_PREFIX + authType.key);
    }

    public void removeMasterKey(AuthType authType) {
        remove(MASTER_KEY_PREFIX + authType.key);
    }

    // --- Secrets ---

    public void storeSecret(String id, String enclaveEncryptedSecret) throws Exception {
        String encrypted = HardwareKeyManager.encrypt(context, enclaveEncryptedSecret);
        boolean committed = prefs.edit().putString(SECRET_PREFIX + id, encrypted).commit();
        if (!committed) {
            throw new Exception("Failed to store secret");
        }
    }

    public String loadSecret(String id) throws Exception {
        String enclaveEncryptedSecret = loadAndDecrypt(SECRET_PREFIX + id);
        if (enclaveEncryptedSecret == null) {
            throw new Exception("Secret not found: " + id);
        }
        return enclaveEncryptedSecret;
    }

    public void copySecret(String fromId, String toId) throws Exception {
        String encrypted = prefs.getString(SECRET_PREFIX + fromId, null);
        if (encrypted == null) {
            throw new Exception("Secret not found: " + fromId);
        }
        boolean committed = prefs.edit().putString(SECRET_PREFIX + toId, encrypted).commit();
        if (!committed) {
            throw new Exception("Failed to copy secret");
        }
    }

    public void removeSecret(String id) {
        remove(SECRET_PREFIX + id);
    }

    public boolean hasSecret(String id) {
        return prefs.contains(SECRET_PREFIX + id);
    }

    public void storeSecretsBatch(List<String[]> idEncryptedPairs) throws Exception {
        SharedPreferences.Editor editor = prefs.edit();
        for (String[] entry : idEncryptedPairs) {
            editor.putString(SECRET_PREFIX + entry[0], HardwareKeyManager.encrypt(context, entry[1]));
        }
        boolean committed = editor.commit();
        if (!committed) {
            throw new Exception("Failed to store secrets");
        }
    }

    // --- Reset ---

    public void clear() {
        prefs.edit().clear().apply();
    }

    public void requireDeviceUnlocked() throws Exception {
        HardwareKeyManager.requireDeviceUnlocked(context);
    }

    // Encryption

    private String loadAndDecrypt(String key) throws Exception {
        String encrypted = prefs.getString(key, null);
        if (encrypted == null) return null;
        return HardwareKeyManager.decrypt(context, encrypted);
    }

    private void remove(String key) {
        prefs.edit().remove(key).apply();
    }
}
