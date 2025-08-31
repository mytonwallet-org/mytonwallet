package org.mytonwallet.app_air.walletcontext.helpers.credentialsHelper;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.KeyguardManager;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.security.KeyPairGeneratorSpec;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.security.keystore.StrongBoxUnavailableException;
import android.util.Base64;

import androidx.biometric.BiometricManager;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.security.InvalidAlgorithmParameterException;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.KeyStoreException;
import java.security.NoSuchAlgorithmException;
import java.security.NoSuchProviderException;
import java.security.SecureRandom;
import java.security.UnrecoverableEntryException;
import java.security.cert.CertificateException;
import java.util.ArrayList;

import javax.crypto.Cipher;
import javax.crypto.CipherInputStream;
import javax.crypto.CipherOutputStream;
import javax.crypto.KeyGenerator;
import javax.crypto.NoSuchPaddingException;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

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
    private static final String RSA_MODE = "RSA/ECB/PKCS1Padding";
    private static final String AES_MODE = "AES/ECB/PKCS7Padding";
    private static final byte[] FIXED_IV = new byte[12];
    private static final String ENCRYPTED_KEY = "NativeBiometricKey";
    private static final String NATIVE_BIOMETRIC_SHARED_PREFERENCES =
        "NativeBiometricSharedPreferences";
    private final Activity activity;
    private KeyStore keyStore;
    private SharedPreferences encryptedSharedPreferences;

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
            } catch (GeneralSecurityException | IOException e) {
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
        Cipher cipher;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(
                Cipher.ENCRYPT_MODE,
                getKey(),
                new GCMParameterSpec(128, FIXED_IV)
            );
        } else {
            cipher = Cipher.getInstance(AES_MODE, "BC");
            cipher.init(Cipher.ENCRYPT_MODE, getKey());
        }
        byte[] encodedBytes = cipher.doFinal(stringToEncrypt.getBytes("UTF-8"));
        return Base64.encodeToString(encodedBytes, Base64.DEFAULT);
    }

    private String decryptString(String stringToDecrypt)
        throws GeneralSecurityException, IOException {
        byte[] encryptedData = Base64.decode(stringToDecrypt, Base64.DEFAULT);

        Cipher cipher;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            cipher = Cipher.getInstance(TRANSFORMATION);
            cipher.init(
                Cipher.DECRYPT_MODE,
                getKey(),
                new GCMParameterSpec(128, FIXED_IV)
            );
        } else {
            cipher = Cipher.getInstance(AES_MODE, "BC");
            cipher.init(Cipher.DECRYPT_MODE, getKey());
        }
        byte[] decryptedData = cipher.doFinal(encryptedData);
        return new String(decryptedData, "UTF-8");
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
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
                .setRandomizedEncryptionRequired(false);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || Build.VERSION.SDK_INT > 34) {
                    // Avoiding setUnlockedDeviceRequired(true) due to known issues on Android 12-14
                    paramBuilder.setUnlockedDeviceRequired(true);
                }
                paramBuilder.setIsStrongBoxBacked(isStrongBoxBacked);
            }

            generator.init(paramBuilder.build());
            return generator.generateKey();
        } else {
            return getAESKey();
        }
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

    private Key getAESKey()
        throws CertificateException, NoSuchPaddingException, InvalidKeyException, NoSuchAlgorithmException, KeyStoreException, NoSuchProviderException, UnrecoverableEntryException, IOException, InvalidAlgorithmParameterException {
        SharedPreferences sharedPreferences = getContext()
            .getSharedPreferences("", Context.MODE_PRIVATE);
        String encryptedKeyB64 = sharedPreferences.getString(ENCRYPTED_KEY, null);
        if (encryptedKeyB64 == null) {
            byte[] key = new byte[16];
            SecureRandom secureRandom = new SecureRandom();
            secureRandom.nextBytes(key);
            byte[] encryptedKey = rsaEncrypt(key);
            encryptedKeyB64 = Base64.encodeToString(encryptedKey, Base64.DEFAULT);
            SharedPreferences.Editor edit = sharedPreferences.edit();
            edit.putString(ENCRYPTED_KEY, encryptedKeyB64);
            edit.apply();
            return new SecretKeySpec(key, "AES");
        } else {
            byte[] encryptedKey = Base64.decode(encryptedKeyB64, Base64.DEFAULT);
            byte[] key = rsaDecrypt(encryptedKey);
            return new SecretKeySpec(key, "AES");
        }
    }

    private KeyStore.PrivateKeyEntry getPrivateKeyEntry(String KEY_ALIAS)
        throws NoSuchProviderException, NoSuchAlgorithmException, InvalidAlgorithmParameterException, CertificateException, KeyStoreException, IOException, UnrecoverableEntryException {
        KeyStore.PrivateKeyEntry privateKeyEntry = (KeyStore.PrivateKeyEntry) getKeyStore()
            .getEntry(KEY_ALIAS, null);

        if (privateKeyEntry == null) {
            KeyPairGenerator keyPairGenerator = KeyPairGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_RSA,
                ANDROID_KEY_STORE
            );
            keyPairGenerator.initialize(
                new KeyPairGeneratorSpec.Builder(getContext())
                    .setAlias(KEY_ALIAS)
                    .build()
            );
            keyPairGenerator.generateKeyPair();
        }

        return privateKeyEntry;
    }

    private byte[] rsaEncrypt(byte[] secret)
        throws CertificateException, NoSuchAlgorithmException, KeyStoreException, IOException, UnrecoverableEntryException, NoSuchProviderException, NoSuchPaddingException, InvalidKeyException, InvalidAlgorithmParameterException {
        KeyStore.PrivateKeyEntry privateKeyEntry = getPrivateKeyEntry(KEY_ALIAS);
        // Encrypt the text
        Cipher inputCipher = Cipher.getInstance(RSA_MODE, "AndroidOpenSSL");
        inputCipher.init(
            Cipher.ENCRYPT_MODE,
            privateKeyEntry.getCertificate().getPublicKey()
        );

        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        CipherOutputStream cipherOutputStream = new CipherOutputStream(
            outputStream,
            inputCipher
        );
        cipherOutputStream.write(secret);
        cipherOutputStream.close();

        byte[] vals = outputStream.toByteArray();
        return vals;
    }

    private byte[] rsaDecrypt(byte[] encrypted)
        throws UnrecoverableEntryException, NoSuchAlgorithmException, KeyStoreException, NoSuchProviderException, NoSuchPaddingException, InvalidKeyException, IOException, CertificateException, InvalidAlgorithmParameterException {
        KeyStore.PrivateKeyEntry privateKeyEntry = getPrivateKeyEntry(KEY_ALIAS);
        Cipher output = Cipher.getInstance(RSA_MODE, "AndroidOpenSSL");
        output.init(Cipher.DECRYPT_MODE, privateKeyEntry.getPrivateKey());
        CipherInputStream cipherInputStream = new CipherInputStream(
            new ByteArrayInputStream(encrypted),
            output
        );
        ArrayList<Byte> values = new ArrayList<>();
        int nextByte;
        while ((nextByte = cipherInputStream.read()) != -1) {
            values.add((byte) nextByte);
        }

        byte[] bytes = new byte[values.size()];
        for (int i = 0; i < bytes.length; i++) {
            bytes[i] = values.get(i).byteValue();
        }
        return bytes;
    }

    private boolean deviceHasCredentials() {
        KeyguardManager keyguardManager = (KeyguardManager) getActivity()
            .getSystemService(Context.KEYGUARD_SERVICE);
        // Can only use fallback if the device has a pin/pattern/password lockscreen.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return keyguardManager.isDeviceSecure();
        } else {
            return keyguardManager.isKeyguardSecure();
        }
    }
}
