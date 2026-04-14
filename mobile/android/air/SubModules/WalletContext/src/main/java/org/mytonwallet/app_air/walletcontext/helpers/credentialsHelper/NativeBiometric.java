package org.mytonwallet.app_air.walletcontext.helpers.credentialsHelper;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.security.keystore.StrongBoxUnavailableException;
import android.util.Base64;

import androidx.biometric.BiometricManager;

import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.Key;
import java.security.ProviderException;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.cert.CertificateException;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.spec.GCMParameterSpec;

public class NativeBiometric {
    private static final String KEY_ALIAS = "https://mytonwallet.app";

    private static final int NONE = 0;
    private static final int FINGERPRINT = 3;
    private static final int FACE_AUTHENTICATION = 4;
    private static final int IRIS_AUTHENTICATION = 5;

    //protected final static int AUTH_CODE = 0102;
    private static final int MULTIPLE = 6;
    private static final String ANDROID_KEY_STORE = "AndroidKeyStore";
    private static final String TRANSFORMATION = "AES/GCM/NoPadding";
    private static final int GCM_IV_LENGTH = 12;
    private static final byte[] LEGACY_FIXED_IV = new byte[GCM_IV_LENGTH];
    private static final String NATIVE_BIOMETRIC_SHARED_PREFERENCES =
        "NativeBiometricSharedPreferences";
    private final Activity activity;
    private KeyStore keyStore;

    public NativeBiometric(Activity activity) {
        this.activity = activity;
    }

    private Context getContext() {
        return activity;
    }

    private Activity getActivity() {
        return activity;
    }

    private int getAvailableFeature() {
        // default to none
        int type = NONE;

        // if has fingerprint
        if (
            getContext()
                .getPackageManager()
                .hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        ) {
            type = FINGERPRINT;
        }

        // if has face auth
        if (
            getContext()
                .getPackageManager()
                .hasSystemFeature(PackageManager.FEATURE_FACE)
        ) {
            // if also has fingerprint
            if (type != NONE) return MULTIPLE;

            type = FACE_AUTHENTICATION;
        }

        // if has iris auth
        if (
            getContext()
                .getPackageManager()
                .hasSystemFeature(PackageManager.FEATURE_IRIS)
        ) {
            // if also has fingerprint or face auth
            if (type != NONE) return MULTIPLE;

            type = IRIS_AUTHENTICATION;
        }

        return type;
    }

    public int isAvailable(Boolean useFallback, Boolean isWeakAuthenticatorAllowed) {
        int allowedAuthenticators = BiometricManager.Authenticators.BIOMETRIC_STRONG;
        if (isWeakAuthenticatorAllowed)
            allowedAuthenticators = allowedAuthenticators | BiometricManager.Authenticators.BIOMETRIC_WEAK;

        BiometricManager biometricManager = BiometricManager.from(getContext());
        int canAuthenticateResult = biometricManager.canAuthenticate(allowedAuthenticators);
        // Using deviceHasCredentials instead of canAuthenticate(DEVICE_CREDENTIAL)
        // > "Developers that wish to check for the presence of a PIN, pattern, or password on these versions should instead use isDeviceSecure."
        // @see https://developer.android.com/reference/androidx/biometric/BiometricManager#canAuthenticate(int)
        boolean fallbackAvailable = useFallback && this.deviceHasCredentials();
        if (useFallback && !fallbackAvailable) {
            canAuthenticateResult = BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE;
        }

        boolean isAvailable = (canAuthenticateResult == BiometricManager.BIOMETRIC_SUCCESS || fallbackAvailable);
        if (!isAvailable) {
            return -1;
        }
        return getAvailableFeature();
    }

    public Boolean setCredentials(String username, String password) {
        if (username != null && password != null) {
            try {
                SharedPreferences.Editor editor = getContext()
                    .getSharedPreferences(
                        NATIVE_BIOMETRIC_SHARED_PREFERENCES,
                        Context.MODE_PRIVATE
                    )
                    .edit();
                editor.putString(
                    KEY_ALIAS + "-username",
                    encryptString(username)
                );
                editor.putString(
                    KEY_ALIAS + "-password",
                    encryptString(password)
                );
                editor.apply();
                return true;
            } catch (GeneralSecurityException | IOException | ProviderException e) {
                e.printStackTrace();
                return false;
            }
        } else {
            return false;
        }
    }

    public String getPasscode() {
        SharedPreferences sharedPreferences = getContext()
            .getSharedPreferences(
                NATIVE_BIOMETRIC_SHARED_PREFERENCES,
                Context.MODE_PRIVATE
            );
        String username = sharedPreferences.getString(
            KEY_ALIAS + "-username",
            null
        );
        String password = sharedPreferences.getString(
            KEY_ALIAS + "-password",
            null
        );
        if (KEY_ALIAS != null) {
            if (username != null && password != null) {
                try {
                    /*JSObject jsObject = new JSObject();
                    jsObject.put("username", decryptString(username, KEY_ALIAS));
                    jsObject.put("password", decryptString(password, KEY_ALIAS));*/
                    return decryptString(password);
                } catch (GeneralSecurityException | IOException e) {
                    // Can get here if not authenticated.
                    return null;
                }
            } else {
                return null;
            }
        } else {
            return null;
        }
    }

    public Boolean deleteCredentials() {
        try {
            getKeyStore().deleteEntry(KEY_ALIAS);
            SharedPreferences.Editor editor = getContext()
                .getSharedPreferences(
                    NATIVE_BIOMETRIC_SHARED_PREFERENCES,
                    Context.MODE_PRIVATE
                )
                .edit();
            editor.clear();
            editor.apply();
            return true;
        } catch (
            KeyStoreException
            | CertificateException
            | NoSuchAlgorithmException
            | IOException e
        ) {
            return false;
        }
    }

    private String encryptString(String stringToEncrypt)
        throws GeneralSecurityException, IOException {
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.ENCRYPT_MODE, getKey());
        byte[] iv = cipher.getIV();
        byte[] ciphertext = cipher.doFinal(stringToEncrypt.getBytes("UTF-8"));
        byte[] combined = new byte[iv.length + ciphertext.length];
        System.arraycopy(iv, 0, combined, 0, iv.length);
        System.arraycopy(ciphertext, 0, combined, iv.length, ciphertext.length);
        return Base64.encodeToString(combined, Base64.DEFAULT);
    }

    private String decryptString(String stringToDecrypt)
        throws GeneralSecurityException, IOException {
        byte[] data = Base64.decode(stringToDecrypt, Base64.DEFAULT);

        // Try new format first: iv(12) || ciphertext+tag
        if (data.length > GCM_IV_LENGTH) {
            try {
                byte[] iv = new byte[GCM_IV_LENGTH];
                System.arraycopy(data, 0, iv, 0, GCM_IV_LENGTH);
                byte[] ciphertext = new byte[data.length - GCM_IV_LENGTH];
                System.arraycopy(data, GCM_IV_LENGTH, ciphertext, 0, ciphertext.length);

                Cipher cipher = Cipher.getInstance(TRANSFORMATION);
                cipher.init(Cipher.DECRYPT_MODE, getKey(), new GCMParameterSpec(128, iv));
                return new String(cipher.doFinal(ciphertext), "UTF-8");
            } catch (GeneralSecurityException e) {
                // Fall through to legacy format
            }
        }

        // Legacy format: fixed zero IV, no IV prefix
        Cipher cipher = Cipher.getInstance(TRANSFORMATION);
        cipher.init(Cipher.DECRYPT_MODE, getKey(), new GCMParameterSpec(128, LEGACY_FIXED_IV));
        return new String(cipher.doFinal(data), "UTF-8");
    }

    @SuppressLint("NewAPI") // API level is already checked
    private Key generateKey()
        throws GeneralSecurityException, IOException {
        Key key;
        try {
            key = generateKey(true);
        } catch (StrongBoxUnavailableException e) {
            key = generateKey(false);
        }
        return key;
    }

    private Key generateKey(boolean isStrongBoxBacked)
        throws GeneralSecurityException, IOException, StrongBoxUnavailableException {
        KeyGenerator generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            ANDROID_KEY_STORE
        );
        KeyGenParameterSpec.Builder paramBuilder = new KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || Build.VERSION.SDK_INT > 34) {
                // Avoiding setUnlockedDeviceRequired(true) due to known issues on Android 12-14
                paramBuilder.setUnlockedDeviceRequired(true);
            }
            paramBuilder.setIsStrongBoxBacked(isStrongBoxBacked);
        }

        generator.init(paramBuilder.build());
        return generator.generateKey();
    }

    private Key getKey()
        throws GeneralSecurityException, IOException {
        KeyStore.SecretKeyEntry secretKeyEntry = (KeyStore.SecretKeyEntry) getKeyStore()
            .getEntry(KEY_ALIAS, null);
        if (secretKeyEntry != null) {
            return secretKeyEntry.getSecretKey();
        }
        return generateKey();
    }

    private KeyStore getKeyStore()
        throws KeyStoreException, CertificateException, NoSuchAlgorithmException, IOException {
        if (keyStore == null) {
            keyStore = KeyStore.getInstance(ANDROID_KEY_STORE);
            keyStore.load(null);
        }
        return keyStore;
    }

    private boolean deviceHasCredentials() {
        KeyguardManager keyguardManager = (KeyguardManager) getActivity()
            .getSystemService(Context.KEYGUARD_SERVICE);
        return keyguardManager.isDeviceSecure();
    }
}
