package org.mytonwallet.app_air.native_enclave.crypto;

import android.app.KeyguardManager;
import android.content.Context;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.security.keystore.StrongBoxUnavailableException;
import android.security.keystore.UserNotAuthenticatedException;
import android.util.Base64;

import org.mytonwallet.app_air.native_enclave.DeviceLockedException;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public class HardwareKeyManager {

    private static final String DATA_KEY_ALIAS = "mtw_enclave_data";
    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
    private static final String AES_GCM_TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int GCM_TAG_LENGTH = 128;

    // --- Data key: automatic encrypt/decrypt (no user auth) ---

    public static String encrypt(Context context, String plaintext) throws Exception {
        requireDeviceUnlocked(context);
        try {
            SecretKey key = getOrCreateDataKey();
            Cipher cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION);
            cipher.init(Cipher.ENCRYPT_MODE, key);
            byte[] iv = cipher.getIV();
            byte[] ciphertext = cipher.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            return Base64.encodeToString(iv, Base64.NO_WRAP)
                + ":" + Base64.encodeToString(ciphertext, Base64.NO_WRAP);
        } catch (Exception e) {
            throw normalizeCryptoException(context, e);
        }
    }

    public static String decrypt(Context context, String encrypted) throws Exception {
        requireDeviceUnlocked(context);
        try {
            String[] parts = encrypted.split(":", 2);
            byte[] iv = Base64.decode(parts[0], Base64.NO_WRAP);
            byte[] ciphertext = Base64.decode(parts[1], Base64.NO_WRAP);
            SecretKey key = getOrCreateDataKey();
            Cipher cipher = Cipher.getInstance(AES_GCM_TRANSFORMATION);
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(GCM_TAG_LENGTH, iv));
            return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw normalizeCryptoException(context, e);
        }
    }

    public static void requireDeviceUnlocked(Context context) throws DeviceLockedException {
        if (isDeviceLocked(context)) {
            throw new DeviceLockedException();
        }
    }

    public static void deleteKey() {
        deleteAlias();
    }

    // --- Keystore helpers ---

    private static void deleteAlias() {
        try {
            KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
            ks.load(null);
            ks.deleteEntry(DATA_KEY_ALIAS);
        } catch (Exception ignored) {
        }
    }

    private static SecretKey getOrCreateDataKey() throws Exception {
        KeyStore ks = KeyStore.getInstance(ANDROID_KEYSTORE);
        ks.load(null);
        if (ks.containsAlias(DATA_KEY_ALIAS)) {
            return (SecretKey) ks.getKey(DATA_KEY_ALIAS, null);
        }
        return generateDataKey();
    }

    private static SecretKey generateDataKey() throws Exception {
        KeyGenerator kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE);
        KeyGenParameterSpec.Builder builder = new KeyGenParameterSpec.Builder(
            DATA_KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            builder.setUnlockedDeviceRequired(true);
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true);
            try {
                kg.init(builder.build());
                return kg.generateKey();
            } catch (StrongBoxUnavailableException e) {
                builder.setIsStrongBoxBacked(false);
            }
        }

        kg.init(builder.build());
        return kg.generateKey();
    }

    private static Exception normalizeCryptoException(Context context, Exception exception) {
        if (isDeviceLocked(context) || requiresUserAuthentication(exception)) {
            return new DeviceLockedException(exception);
        }
        return exception;
    }

    private static boolean isDeviceLocked(Context context) {
        KeyguardManager keyguardManager =
            (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
        return keyguardManager != null && keyguardManager.isDeviceLocked();
    }

    private static boolean requiresUserAuthentication(Throwable throwable) {
        Throwable current = throwable;
        while (current != null) {
            if (current instanceof UserNotAuthenticatedException) {
                return true;
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                current instanceof android.security.KeyStoreException &&
                ((android.security.KeyStoreException) current).requiresUserAuthentication()) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }
}
